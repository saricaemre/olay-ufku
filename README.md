# Olay Ufku

Mac menü çubuğunda duran küçük video indirici. Linki kopyala, simgeye tıkla, ⌘V'ye bas; video İndirilenler klasörüne iner. İndirme işini [yt-dlp](https://github.com/yt-dlp/yt-dlp) yapar.

## İndir ve kur

1. [Releases](../../releases/latest) sayfasından `Olay.Ufku.dmg` dosyasını indir.
2. DMG'yi aç, "Olay Ufku" simgesini "Uygulamalar" klasörüne sürükle.
3. İlk açılışta macOS "Apple doğrulayamadı" diye uyarır (uygulama imzalı değil). "Bitti"ye bas, sonra
   **Sistem Ayarları › Gizlilik ve Güvenlik** › en altta "Olay Ufku engellendi" yazısının yanındaki **Yine de Aç**'a bas. Bunu bir kez yaparsın.

Gerekenler: Apple çipli Mac (M1 ve sonrası), macOS 15 ya da daha yeni.

## Kullanım

1. Tarayıcıda videonun linkini kopyala (⌘C).
2. Ekranın en üstünde, sağda, önünden halka geçen küçük siyah topa tıkla.
3. ⌘V'ye bas (ya da "Linki yapıştır ve indir"e tıkla).

İnerken simgenin yanında yüzde, bitince ✓ görünür. Menüdeki "Biçim" ile yalnız sesi (MP3) alabilirsin. "Girişte başlat" ile bilgisayar açılınca kendiliğinden başlar. yt-dlp haftada bir kendini günceller.

## Kaynaktan derleme

```bash
./yap.sh            # build/Olay Ufku.app
./yap.sh --kur      # ~/Applications'a kurar ve açar
./yap.sh --dmg      # build/Olay Ufku.dmg
./yap.sh --araclar  # vendor/ klasörünü (Python + yt-dlp) yeniden kurar, sonra derler
```

`vendor/` repoda yok; `--araclar` onu `uv` ile kurulu CPython 3.12'den ve PyPI'dan yeniden oluşturur. ffmpeg, `yap.sh` içindeki `FF` yolundan alınır; kendi makinende bu yolu taşınabilir bir arm64 ffmpeg'e çevirmen gerekebilir.
