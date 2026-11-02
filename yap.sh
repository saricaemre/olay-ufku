#!/bin/zsh
# Olay Ufku (menü çubuğu indiricisi) derler. Eski masaüstü kara deliği: eski/ufuk.html
#   ./yap.sh         → build/Olay Ufku.app
#   ./yap.sh --kur   → ~/Applications'a kurar ve açar
#   ./yap.sh --dmg   → build/Olay Ufku.dmg (başka bir Mac'e gönderilecek paket)
#   ./yap.sh --araclar → vendor/ klasörünü sıfırdan kurar (aşağıya bak), sonra derler
# Uygulama kendi araçlarını taşır:
#   vendor/python : bağımsız CPython 3.12 (python-build-standalone, uv'nin kopyası; XML okuyucusu gömülü)
#   vendor/paket  : PyPI'dan yt-dlp[default,curl-cffi] (her sitede çalışsın diye bütün isteğe bağlı parçalar)
#   ffmpeg        : stüdyonun Remotion paketindeki taşınabilir sürüm (Apple çip, macOS 15+)
set -euo pipefail
cd "${0:A:h}"

if [[ "${1:-}" == "--araclar" ]]; then
  rm -rf vendor/python vendor/paket
  cp -R ~/.local/share/uv/python/cpython-3.12.13-macos-aarch64-none vendor/python
  L=vendor/python/lib
  rm -rf vendor/python/include vendor/python/share $L/python3.12/{test,idlelib,tkinter,turtledemo} $L/tcl* $L/tk* $L/itcl* $L/thread* $L/libtcl* $L/python3.12/lib-dynload/_tkinter*(N)
  vendor/python/bin/python3.12 -m pip install --quiet --disable-pip-version-check --no-compile --target vendor/paket "yt-dlp[default,curl-cffi]"
  shift
fi

AD="Olay Ufku"
APP="build/$AD.app"
FF="../../studio/node_modules/@remotion/compositor-darwin-arm64"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" build/Ufuk.iconset

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 main.swift koku.swift -o "$APP/Contents/MacOS/OlayUfku"

# araçlar: ffmpeg kitaplıklarını kendi yanından bulsun diye bağlar @loader_path'e çevrilir
BIN="$APP/Contents/Resources/bin"
cp -R vendor/python vendor/paket "$APP/Contents/Resources/"
find "$APP/Contents/Resources" -name __pycache__ -type d -prune -exec rm -rf {} +
cp "$FF/ffmpeg" "$FF/ffprobe" "$FF"/*.dylib "$BIN/"
chmod 755 "$BIN"/*
LIBS=(${(f)"$(cd $BIN && ls *.dylib)"})
for f in "$BIN"/ffmpeg "$BIN"/ffprobe "$BIN"/*.dylib; do
  for l in $LIBS; do install_name_tool -change "$l" "@loader_path/$l" "$f" 2>/dev/null; done
  [[ "$f" == *.dylib ]] && install_name_tool -id "@loader_path/${f:t}" "$f"
done
for f in "$BIN"/*.dylib "$BIN"/ffmpeg "$BIN"/ffprobe; do codesign --force --sign - "$f" 2>/dev/null; done

swiftc -O ikon.swift -o build/ikon
build/ikon build/ikon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/ikon.png --out build/Ufuk.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/ikon.png --out build/Ufuk.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/Ufuk.iconset -o "$APP/Contents/Resources/Ufuk.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Olay Ufku</string>
  <key>CFBundleDisplayName</key><string>Olay Ufku</string>
  <key>CFBundleIdentifier</key><string>com.emre.olayufku</string>
  <key>CFBundleExecutable</key><string>OlayUfku</string>
  <key>CFBundleIconFile</key><string>Ufuk</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.3</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDownloadsFolderUsageDescription</key><string>İndirilen videolar İndirilenler klasörüne kaydedilir.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "derlendi: $APP"

if [[ "${1:-}" == "--kur" ]]; then
  pkill -x OlayUfku 2>/dev/null || true
  sleep 0.5
  mkdir -p ~/Applications
  rm -rf ~/Applications/"$AD.app"
  cp -R "$APP" ~/Applications/
  open ~/Applications/"$AD.app"
  echo "kuruldu ve açıldı: ~/Applications/$AD.app"
fi

if [[ "${1:-}" == "--dmg" ]]; then
  K=build/dmg
  mkdir -p "$K"
  cp -R "$APP" "$K/"
  ln -s /Applications "$K/Uygulamalar"
  cp BENIOKU.txt "$K/Önce beni oku.txt"
  hdiutil create -volname "$AD" -srcfolder "$K" -fs HFS+ -format UDZO -ov "build/$AD.dmg" >/dev/null
  echo "dmg: build/$AD.dmg ($(du -h "build/$AD.dmg" | cut -f1))"
fi
