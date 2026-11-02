// Olay Ufku: menü çubuğunda duran küçük bir indirici. Simgeye tıkla, ⌘V'ye bas:
// panodaki linkteki video yt-dlp ile İndirilenler'e iner.

import Cocoa
import ServiceManagement

/// yt-dlp çıktısını satırlara böler (ilerleme satırları \r ile de gelebilir).
final class SatirOkuyucu {
    private var tampon = Data()
    func besle(_ d: Data) -> [String] {
        tampon.append(d)
        var satirlar: [String] = []
        while let i = tampon.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let parca = tampon[tampon.startIndex..<i]
            tampon.removeSubrange(tampon.startIndex...i)
            if !parca.isEmpty, let s = String(data: parca, encoding: .utf8) { satirlar.append(s) }
        }
        return satirlar
    }
}

final class Ufuk: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var cubuk: NSStatusItem!
    let ayar = UserDefaults.standard

    var kuyruk: [URL] = []
    var surec: Process?
    var iptalEdildi = false
    var mod = "bos", baslik = "", mesaj = ""
    var yuzde = 0.0, sonYuzde = 0.0
    var parca = 0, parcaSayisi = 1
    var dosya: URL?
    var bosaDonus: Timer?
    var cubukNotu: String?

    // Bir işin denemeleri: normal → Chrome kılığı (403) → tarayıcı oturumu (giriş) → sayfayı tara.
    var aktifURL: URL?
    var denenen: Set<String> = []
    var ekArgumanlar: [String] = []
    var ciktiAdi: String?
    var hataTuru = ""
    var koklayici: Koklayici?
    var kokuAdaylari: [String] = []
    var kokuSonucu: Koklayici.Sonuc?

    enum Bicim: String { case uyumlu, enIyi, ses }
    var bicim: Bicim {
        get { Bicim(rawValue: ayar.string(forKey: "bicim") ?? "") ?? .uyumlu }
        set { ayar.set(newValue.rawValue, forKey: "bicim") }
    }
    var oturumKullan: Bool {
        get { ayar.object(forKey: "oturumKullan") as? Bool ?? true }
        set { ayar.set(newValue, forKey: "oturumKullan") }
    }

    /// Varsayılan tarayıcı, yt-dlp'nin çerez okuyabildikleri arasındaysa adı.
    var tarayici: (kod: String, ad: String)? {
        guard let a = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
              let id = Bundle(url: a)?.bundleIdentifier?.lowercased() else { return nil }
        let harita: [String: (String, String)] = [
            "com.google.chrome": ("chrome", "Chrome"), "com.apple.safari": ("safari", "Safari"),
            "org.mozilla.firefox": ("firefox", "Firefox"), "com.brave.browser": ("brave", "Brave"),
            "com.microsoft.edgemac": ("edge", "Edge"), "com.operasoftware.opera": ("opera", "Opera"),
            "com.vivaldi.vivaldi": ("vivaldi", "Vivaldi"), "org.chromium.chromium": ("chromium", "Chromium")]
        return harita[id].map { (kod: $0.0, ad: $0.1) }
    }

    // MARK: - Açılış

    func applicationDidFinishLaunching(_ n: Notification) {
        cubuk = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        cubuk.button?.image = Ufuk.cubukSimgesi()
        cubuk.button?.imagePosition = .imageLeading
        cubuk.button?.toolTip = "Olay Ufku"
        let m = NSMenu()
        m.delegate = self
        cubuk.menu = m

        // Deneme için: OlayUfku --gunluk <klasör> --yut <adres>
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--yut"), i + 1 < a.count, let u = URL(string: a[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.indir(u) }
        }
        araclariHazirla()
        tani("# çubuk: görünür=\(cubuk.isVisible) yt-dlp=\(ytdlpKomutu()?.yol ?? "-") ffmpeg=\(ffmpegYolu() ?? "-")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.ytdlpGuncelle() }
    }

    func applicationWillTerminate(_ n: Notification) { surec?.terminate() }

    // MARK: - Tanı: --gunluk <klasör> durumları yazar, indirmeyi o klasöre yapar

    lazy var taniKlasoru: URL? = {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--gunluk"), i + 1 < a.count else { return nil }
        return URL(fileURLWithPath: a[i + 1])
    }()

    func tani(_ satir: String) {
        guard let k = taniKlasoru else { return }
        let dosya = k.appendingPathComponent("durum.log")
        if let h = try? FileHandle(forWritingTo: dosya) {
            h.seekToEndOfFile(); h.write((satir + "\n").data(using: .utf8)!); try? h.close()
        } else { try? (satir + "\n").write(to: dosya, atomically: true, encoding: .utf8) }
    }

    func durumDegisti() {
        cubukGuncelle()
        tani("\(mod) \(Int(yuzde * 100)) \(baslik) \(mesaj)")
    }

    // MARK: - Bağlantı

    static func webMi(_ u: URL) -> Bool { ["http", "https"].contains(u.scheme?.lowercased() ?? "") && u.host != nil }

    static func baglanti(_ pb: NSPasteboard) -> URL? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for u in urls where webMi(u) { return u }
        }
        if let s = pb.string(forType: .string),
           let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for m in det.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                if let u = m.url, webMi(u) { return u }
            }
        }
        return nil
    }

    func indir(_ u: URL) {
        kuyruk.append(u)
        if surec == nil && koklayici == nil && aktifURL == nil { siradaki() } else { durumDegisti() }
    }

    @objc func panodanIndir() {
        guard let u = Ufuk.baglanti(NSPasteboard.general) else { notGoster("panoda link yok"); return }
        indir(u)
    }

    func notGoster(_ n: String) {
        cubukNotu = n
        cubukGuncelle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.cubukNotu = nil; self.cubukGuncelle() }
    }

    // MARK: - İndirme

    // Araçlar uygulamanın içindedir: kendi Python'u (XML okuyucusu gömülü), ffmpeg ve kitaplıkları.
    // yt-dlp paketi güncellenebilsin diye Application Support'a kopyalanır; uygulamanın içi imzalı kalır.

    var kaynaklar: URL? { Bundle.main.resourceURL }
    var icPython: String? {
        guard let p = kaynaklar?.appendingPathComponent("python/bin/python3.12").path,
              FileManager.default.isExecutableFile(atPath: p) else { return nil }
        return p
    }
    lazy var destek: URL = {
        let k = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Olay Ufku")
        try? FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
        return k
    }()
    var paket: URL { destek.appendingPathComponent("paket") }
    let paketTanimi = "yt-dlp[default,curl-cffi]"

    /// Açılışta: yt-dlp paketini yerine koyar (yeni sürümle gelen paket eskisinin yerine geçer),
    /// arkadaştan gelen kopyada karantina işaretini kaldırır, eski sürümün artığını siler.
    func araclariHazirla() {
        let fm = FileManager.default
        try? fm.removeItem(at: destek.appendingPathComponent("yt-dlp"))   // 1.1'in tek dosyalık yt-dlp'si
        guard let ic = kaynaklar?.appendingPathComponent("paket") else { return }
        let surum = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if !fm.fileExists(atPath: paket.path) || ayar.string(forKey: "paketSurumu") != surum {
            let gecici = destek.appendingPathComponent("paket-kopya")
            try? fm.removeItem(at: gecici)
            if (try? fm.copyItem(at: ic, to: gecici)) != nil {
                try? fm.removeItem(at: paket)
                try? fm.moveItem(at: gecici, to: paket)
                ayar.set(surum, forKey: "paketSurumu")
            }
        }
        for yol in [Bundle.main.bundlePath, paket.path] {
            let x = Process()
            x.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            x.arguments = ["-dr", "com.apple.quarantine", yol]
            x.standardError = FileHandle.nullDevice
            try? x.run(); x.waitUntilExit()
        }
    }

    /// yt-dlp'yi çalıştıracak komut: uygulamanın Python'u, yoksa (geliştirme) Homebrew'daki yt-dlp.
    func ytdlpKomutu() -> (yol: String, onEk: [String], ortam: [String: String])? {
        if let py = icPython, FileManager.default.fileExists(atPath: paket.appendingPathComponent("yt_dlp").path) {
            return (py, ["-s", "-m", "yt_dlp"],
                    ["PYTHONPATH": paket.path, "PYTHONNOUSERSITE": "1",
                     "PYTHONPYCACHEPREFIX": destek.appendingPathComponent("onbellek").path])
        }
        if let y = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return (y, [], [:])
        }
        return nil
    }

    func ffmpegYolu() -> String? {
        let fm = FileManager.default
        if let ic = kaynaklar?.appendingPathComponent("bin/ffmpeg"), fm.isExecutableFile(atPath: ic.path) { return ic.path }
        return ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { fm.isExecutableFile(atPath: $0) }
    }

    /// Siteler sık değişir: yt-dlp paketi haftada bir sessizce güncellenir (yan klasöre kurulur, başarılıysa yer değiştirir).
    func ytdlpGuncelle() {
        guard let py = icPython, surec == nil else { return }
        let son = ayar.object(forKey: "guncelleme") as? Date ?? .distantPast
        guard Date().timeIntervalSince(son) > 7 * 24 * 3600 else { return }
        let yeni = destek.appendingPathComponent("paket-yeni")
        try? FileManager.default.removeItem(at: yeni)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: py)
        p.arguments = ["-s", "-m", "pip", "install", "--quiet", "--disable-pip-version-check", "--no-compile",
                       "--target", yeni.path, paketTanimi]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONNOUSERSITE"] = "1"
        env["PYTHONPYCACHEPREFIX"] = destek.appendingPathComponent("onbellek").path
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { pr in
            DispatchQueue.main.async {
                let fm = FileManager.default
                guard pr.terminationStatus == 0, fm.fileExists(atPath: yeni.appendingPathComponent("yt_dlp").path) else {
                    try? fm.removeItem(at: yeni); return
                }
                // indirme sürerken paketi değiştirme; sonraki açılışa ya da sonraki denemeye kalsın
                guard self.surec == nil else { try? fm.removeItem(at: yeni); return }
                let eski = self.destek.appendingPathComponent("paket-eski")
                try? fm.removeItem(at: eski)
                try? fm.moveItem(at: self.paket, to: eski)
                try? fm.moveItem(at: yeni, to: self.paket)
                try? fm.removeItem(at: eski)
                self.ayar.set(Date(), forKey: "guncelleme")
                self.tani("# güncellendi")
            }
        }
        try? p.run()
    }

    func argumanlar(_ u: URL) -> [String] {
        // tanı modunda indirme tanı klasörüne gider, İndirilenler kirlenmez
        let klasor = taniKlasoru?.path ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path
        var a = ["--no-playlist", "--newline", "--no-simulate", "--progress",
                 "--print", "before_dl:@@T %(title)s",
                 "--print", "before_dl:@@N %(format_id)s",
                 "--print", "after_move:@@F %(filepath)s",
                 "--progress-template", "download:@@P %(progress._percent_str)s",
                 "-P", klasor, "-o", ciktiAdi.map { Ufuk.sablonaCevir($0) + ".%(ext)s" } ?? "%(title).150B [%(id)s].%(ext)s"]
        if let ff = ffmpegYolu() { a += ["--ffmpeg-location", ff] }
        a += ekArgumanlar
        switch bicim {
        case .uyumlu: a += ["-S", "vcodec:h264,res,acodec:m4a", "--merge-output-format", "mp4"]
        case .enIyi: a += ["-S", "res,acodec:m4a", "--merge-output-format", "mp4"]
        case .ses: a += ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0"]
        }
        return a + ["--", u.absoluteString]
    }

    /// Sayfa başlığı dosya adı olur: yol ayırıcıları ve yt-dlp şablon işaretleri ayıklanır.
    static func sablonaCevir(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"[/\\:\n\r\t]"#, with: "-", options: .regularExpression)
        t = String(t.prefix(120)).trimmingCharacters(in: .whitespaces)
        if t.isEmpty { t = "video" }
        return t.replacingOccurrences(of: "%", with: "%%")
    }

    func siradaki() {
        guard surec == nil, koklayici == nil, !kuyruk.isEmpty else { return }
        let u = kuyruk.removeFirst()
        bosaDonus?.invalidate()
        aktifURL = u; denenen = []; ekArgumanlar = []; ciktiAdi = nil; kokuAdaylari = []; kokuSonucu = nil
        iptalEdildi = false
        calistir(u)
    }

    func sonrakine() {
        aktifURL = nil
        if !kuyruk.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.siradaki() } }
    }

    func calistir(_ u: URL) {
        guard let komut = ytdlpKomutu() else { hataVer("indirme aracı bulunamadı"); sonrakine(); return }
        mod = "cozuyor"; baslik = ciktiAdi ?? ""; mesaj = ""; hataTuru = ""
        yuzde = 0; sonYuzde = 0; parca = 0; parcaSayisi = 1; dosya = nil
        durumDegisti()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: komut.yol)
        p.arguments = komut.onEk + argumanlar(u)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        env["PYTHONUNBUFFERED"] = "1"
        env.merge(komut.ortam) { $1 }
        p.environment = env
        let cikti = Pipe(), hataCikti = Pipe()
        p.standardOutput = cikti
        p.standardError = hataCikti

        let grup = DispatchGroup()
        for (boru, hataMi) in [(cikti, false), (hataCikti, true)] {
            let okuyucu = SatirOkuyucu()
            grup.enter()
            boru.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; grup.leave(); return }
                let satirlar = okuyucu.besle(d)
                DispatchQueue.main.async { for s in satirlar { if hataMi { self.hataSatiri(s) } else { self.satir(s) } } }
            }
        }
        grup.enter()
        p.terminationHandler = { _ in grup.leave() }
        grup.notify(queue: .main) { self.bitti(p.terminationStatus) }
        do {
            try p.run()
            surec = p
        } catch {
            cikti.fileHandleForReading.readabilityHandler = nil
            hataCikti.fileHandleForReading.readabilityHandler = nil
            hataVer("yt-dlp başlatılamadı")
            sonrakine()
        }
    }

    func satir(_ s: String) {
        if s.hasPrefix("@@T ") {
            baslik = ciktiAdi ?? String(s.dropFirst(4)); mod = "iniyor"; durumDegisti()
        } else if s.hasPrefix("@@N ") {
            parcaSayisi = max(1, s.dropFirst(4).split(separator: "+").count)
        } else if s.hasPrefix("@@F ") {
            dosya = URL(fileURLWithPath: String(s.dropFirst(4)))
        } else if s.hasPrefix("@@P ") {
            guard let y = Double(s.dropFirst(4).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")) else { return }
            // video ve ses ayrı iner: yüzde sıfıra dönerse sonraki parçaya geçilmiştir
            if y + 25 < sonYuzde && parca < parcaSayisi - 1 { parca += 1 }
            sonYuzde = y
            yuzde = min(1, (Double(parca) + y / 100) / Double(parcaSayisi))
            mod = y >= 100 && parca >= parcaSayisi - 1 ? "isleniyor" : "iniyor"
            cubukGuncelle()
        }
    }

    func hataSatiri(_ s: String) {
        guard s.hasPrefix("ERROR:") else { return }
        let l = s.lowercased()
        let var_ = { (k: [String]) in k.contains { l.contains($0) } }
        if var_(["drm"]) { hataTuru = "drm"; mesaj = "DRM korumalı, indirilemez" }
        else if var_(["403", "cloudflare", "impersonat", "429", "too many requests"]) { hataTuru = "engel"; mesaj = "site erişimi engelledi" }
        else if var_(["unsupported url", "no video formats", "unable to extract", "no video could be found", "is not a valid url", "requested format is not available"]) {
            hataTuru = "desteksiz"; mesaj = "sayfada video bulunamadı"
        }
        else if var_(["private"]) { hataTuru = "giris"; mesaj = "video gizli" }
        else if var_(["sign in", "login", "logged-in", "log in", "cookies", "account", "age"]) { hataTuru = "giris"; mesaj = "site giriş istiyor" }
        else if var_(["operation not permitted"]) && l.contains("safari") { hataTuru = "diger"; mesaj = "Safari için Tam Disk Erişimi gerekli" }
        else if var_(["unavailable", "removed", "deleted"]) { hataTuru = "diger"; mesaj = "video erişilemez" }
        else if var_(["timed out", "network", "resolve", "connection"]) { hataTuru = "ag"; mesaj = "ağ sorunu" }
        else {
            hataTuru = "diger"
            var t = String(s.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if let r = t.range(of: #"^\[[^\]]+\]\s*[^:]*:\s*"#, options: .regularExpression) { t.removeSubrange(r) }
            mesaj = String(t.prefix(44))
        }
    }

    func bitti(_ kod: Int32) {
        surec = nil
        if iptalEdildi {
            mod = "bos"; durumDegisti()
        } else if kod == 0 {
            mod = "tamam"; yuzde = 1; durumDegisti()
            bosaDonus = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in self?.bosa() }
        } else {
            tani("# hata (\(hataTuru)): \(mesaj)")
            if yenidenDene() { return }
            hataVer(mesaj.isEmpty ? "bilinmeyen hata (\(kod))" : mesaj)
        }
        sonrakine()
    }

    /// Başarısız denemeden sonra hata türüne göre bir sonraki yolu seçer; seçtiyse true.
    func yenidenDene() -> Bool {
        guard let u = aktifURL else { return false }
        if kokuSonucu != nil {
            if !kokuAdaylari.isEmpty { kokuAdayiniDene(); return true }
            if hataTuru != "drm" { mesaj = "sayfada indirilebilir video bulunamadı" }
            return false
        }
        if hataTuru == "engel" && !denenen.contains("taklit") {
            denenen.insert("taklit")
            ekArgumanlar = ["--impersonate", "chrome"]
            calistir(u); return true
        }
        if hataTuru == "giris" && oturumKullan, let t = tarayici, !denenen.contains("oturum") {
            denenen.insert("oturum")
            ekArgumanlar = ["--cookies-from-browser", t.kod]
            calistir(u); return true
        }
        if ["desteksiz", "engel", "diger"].contains(hataTuru) && !denenen.contains("koku") {
            denenen.insert("koku")
            sayfayiTara(u); return true
        }
        return false
    }

    /// yt-dlp sayfayı tanımadı: sayfayı görünmez tarayıcıda açıp oynatıcının çektiği adresleri topla.
    func sayfayiTara(_ u: URL) {
        mod = "taraniyor"; durumDegisti()
        let k = Koklayici(sayfa: u, klasor: destek)
        koklayici = k
        k.basla { sonuc in
            self.koklayici = nil
            self.tani("# koku: \(sonuc.adresler.count) aday · \(sonuc.baslik) · \(sonuc.adresler.joined(separator: " , "))")
            if self.iptalEdildi { self.mod = "bos"; self.durumDegisti(); self.sonrakine(); return }
            guard !sonuc.adresler.isEmpty else {
                self.hataVer("sayfada video bulunamadı"); self.sonrakine(); return
            }
            self.kokuSonucu = sonuc
            self.kokuAdaylari = sonuc.adresler
            self.kokuAdayiniDene()
        }
    }

    /// Yakalanan adreslerden sıradakini sayfanın kimliğiyle (adres, tarayıcı, çerezler) indir.
    func kokuAdayiniDene() {
        guard let s = kokuSonucu, !kokuAdaylari.isEmpty, let aday = URL(string: kokuAdaylari.removeFirst()) else { return }
        let koken = "\(s.sayfa.scheme ?? "https")://\(s.sayfa.host ?? "")"
        ekArgumanlar = ["--referer", s.sayfa.absoluteString, "--user-agent", Koklayici.kimlik, "--add-header", "Origin:\(koken)"]
        if let c = s.cerez { ekArgumanlar += ["--cookies", c.path] }
        let site = (s.sayfa.host ?? "").replacingOccurrences(of: "www.", with: "")
        ciktiAdi = s.baslik.isEmpty ? site : "\(s.baslik) [\(site)]"
        calistir(aday)
    }

    func hataVer(_ m: String) {
        mod = "hata"; mesaj = m; durumDegisti()
        bosaDonus?.invalidate()
        bosaDonus = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in self?.bosa() }
    }

    func bosa() {
        guard surec == nil, mod == "tamam" || mod == "hata" else { return }
        mod = "bos"; durumDegisti()
    }

    // MARK: - Menü çubuğu

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        m.autoenablesItems = false
        @discardableResult
        func ekle(_ baslik: String, _ s: Selector?, _ acik: Bool? = nil, menu: NSMenu? = nil, deger: String? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: baslik, action: s, keyEquivalent: "")
            i.target = self
            if let acik { i.state = acik ? .on : .off }
            i.representedObject = deger
            (menu ?? m).addItem(i)
            return i
        }

        // durum satırı yalnız iş varken görünür; bitince tıklanınca dosyayı gösterir
        if let d = durumSatiri() {
            ekle(d, mod == "tamam" ? #selector(dosyayiGoster) : nil).isEnabled = mod == "tamam"
            m.addItem(.separator())
        }
        // menü açıkken ⌘V doğrudan bu satırı çalıştırır
        let yapistir = ekle("Linki yapıştır ve indir", #selector(panodanIndir))
        yapistir.keyEquivalent = "v"
        yapistir.keyEquivalentModifierMask = .command
        if surec != nil || koklayici != nil { ekle("İndirmeyi durdur", #selector(iptal)) }
        m.addItem(.separator())

        let b = NSMenuItem(title: "Biçim", action: nil, keyEquivalent: "")
        let bm = NSMenu()
        for (ad, x) in [("Video (MP4)", Bicim.uyumlu), ("Video · en yüksek kalite", .enIyi), ("Yalnız ses (MP3)", .ses)] {
            ekle(ad, #selector(bicimSec(_:)), bicim == x, menu: bm, deger: x.rawValue)
        }
        b.submenu = bm
        m.addItem(b)
        if let t = tarayici {
            ekle("Giriş isteyen sitelerde \(t.ad) oturumumu kullan", #selector(oturumDegis), oturumKullan)
        }
        ekle("Girişte başlat", #selector(giristeDegis), SMAppService.mainApp.status == .enabled)
        m.addItem(.separator())
        ekle("İndirilenler klasörünü aç", #selector(klasoruAc))
        ekle("Kapat", #selector(kapat))
    }

    func durumSatiri() -> String? {
        let ad = baslik.count > 36 ? String(baslik.prefix(35)) + "…" : baslik
        switch mod {
        case "cozuyor": return "Hazırlanıyor…"
        case "taraniyor": return "Sayfa taranıyor…"
        case "iniyor": return "%\(Int(yuzde * 100)) · \(ad)"
        case "isleniyor": return "Birleştiriliyor · \(ad)"
        case "tamam": return "✓ \(ad)  ·  göster"
        case "hata": return "İndirilemedi · \(mesaj)"
        default: return nil
        }
    }

    /// Simgenin yanında: iş sürerken yüzde, bitince ✓, hatada !, kısa notlar.
    func cubukGuncelle() {
        guard let b = cubuk?.button else { return }
        let yazi: String
        if let n = cubukNotu { yazi = " " + n }
        else {
            switch mod {
            case "cozuyor", "isleniyor", "taraniyor": yazi = " …"
            case "iniyor": yazi = " %\(Int(yuzde * 100))"
            case "tamam": yazi = " ✓"
            case "hata": yazi = " !"
            default: yazi = ""
            }
        }
        if b.title != yazi {
            b.attributedTitle = NSAttributedString(string: yazi, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)])
        }
    }

    /// Menü çubuğu simgesi: eğik disk ve önünden geçtiği karanlık küre (şablon görsel).
    static func cubukSimgesi() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            let disk = CGRect(x: 0.5, y: 7.5, width: 17, height: 3)
            c.setStrokeColor(.black); c.setFillColor(.black)
            // diskin arka yarısı
            c.saveGState()
            c.clip(to: CGRect(x: 0, y: 9, width: 18, height: 9))
            c.setLineWidth(1.2); c.strokeEllipse(in: disk)
            c.restoreGState()
            c.fillEllipse(in: CGRect(x: 4.5, y: 4.5, width: 9, height: 9))
            // ön yarı: küreyi ince bir boşlukla keserek önünden geçer
            c.saveGState()
            c.clip(to: CGRect(x: 0, y: 0, width: 18, height: 9))
            c.setBlendMode(.clear)
            c.setLineWidth(2.8); c.strokeEllipse(in: disk)
            c.setBlendMode(.normal)
            c.setLineWidth(1.2); c.strokeEllipse(in: disk)
            c.restoreGState()
            return true
        }
        img.isTemplate = true
        return img
    }

    @objc func dosyayiGoster() {
        if let d = dosya, FileManager.default.fileExists(atPath: d.path) {
            NSWorkspace.shared.activateFileViewerSelecting([d])
        } else { klasoruAc() }
    }
    @objc func iptal() { iptalEdildi = true; surec?.terminate(); koklayici?.durdur() }
    @objc func oturumDegis() { oturumKullan.toggle() }
    @objc func bicimSec(_ i: NSMenuItem) {
        if let r = i.representedObject as? String, let b = Bicim(rawValue: r) { bicim = b }
    }
    @objc func klasoruAc() { NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) }
    @objc func giristeDegis() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { notGoster("ayarlanamadı") }
    }
    @objc func kapat() { NSApp.terminate(nil) }
}

let uygulama = NSApplication.shared
let temsilci = Ufuk()
uygulama.delegate = temsilci
uygulama.setActivationPolicy(.accessory)
uygulama.run()
