// Koklayıcı: yt-dlp'nin tanımadığı sayfalar için. Sayfayı görünmez bir tarayıcıda açar, oynatıcıyı
// sessizce başlatır ve sayfanın çektiği video adreslerini (m3u8, mpd, mp4…) yakalar. Bulunanlar
// sayfanın adresi, tarayıcı kimliği ve çerezleriyle birlikte yt-dlp'ye verilir.

import Cocoa
import WebKit

final class Koklayici: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    struct Sonuc {
        let adresler: [String]
        let baslik: String
        let sayfa: URL
        let cerez: URL?
    }

    static let kimlik = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    private let sayfa: URL
    private let klasor: URL
    private var web: WKWebView?
    private var pencere: NSWindow?
    private var bulunan: [String] = []
    private var sonBulus = Date.distantPast
    private let baslangic = Date()
    private var ilkYuklemeBitti = false
    private var zamanlayici: Timer?
    private var tamam: ((Sonuc) -> Void)?

    init(sayfa: URL, klasor: URL) {
        self.sayfa = sayfa
        self.klasor = klasor
    }

    func basla(_ tamam: @escaping (Sonuc) -> Void) {
        self.tamam = tamam
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        if #available(macOS 14.0, *) { cfg.preferences.inactiveSchedulingPolicy = .none }
        let uc = WKUserContentController()
        uc.add(self, name: "koku")
        uc.addUserScript(WKUserScript(source: Koklayici.betik, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        cfg.userContentController = uc

        let w = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: cfg)
        w.customUserAgent = Koklayici.kimlik
        w.navigationDelegate = self
        // oynatıcılar gizli sayfada başlamaz: görünmez ama ekranda sayılan bir pencereye konur
        let p = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.borderless],
                         backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.alphaValue = 0.01
        p.ignoresMouseEvents = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .transient]
        p.contentView = w
        p.orderFrontRegardless()
        pencere = p
        web = w
        w.load(URLRequest(url: sayfa))

        let z = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.denetle() }
        RunLoop.main.add(z, forMode: .common)
        zamanlayici = z
    }

    func durdur() { bitir() }

    private func denetle() {
        let gecen = Date().timeIntervalSince(baslangic)
        let sessiz = Date().timeIntervalSince(sonBulus)
        let manifestVar = bulunan.contains { Koklayici.puan($0) >= 90 }
        if gecen > 25 || (manifestVar && sessiz > 2.5) || (!bulunan.isEmpty && sessiz > 4 && gecen > 8) { bitir() }
    }

    private func bitir() {
        guard let tamam else { return }
        self.tamam = nil
        zamanlayici?.invalidate()
        let adresler = bulunan.enumerated()
            .sorted { (Koklayici.puan($0.element), -$0.offset) > (Koklayici.puan($1.element), -$1.offset) }
            .map(\.element)
            .filter { Koklayici.puan($0) > 10 }
        guard let w = web else { tamam(Sonuc(adresler: [], baslik: "", sayfa: sayfa, cerez: nil)); return }
        w.evaluateJavaScript("document.title") { b, _ in
            let baslik = (b as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            w.configuration.websiteDataStore.httpCookieStore.getAllCookies { cerezler in
                let dosya = self.cerezYaz(cerezler)
                self.temizle()
                tamam(Sonuc(adresler: Array(adresler.prefix(4)), baslik: baslik, sayfa: self.sayfa, cerez: dosya))
            }
        }
    }

    private func temizle() {
        web?.stopLoading()
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "koku")
        web?.navigationDelegate = nil
        pencere?.orderOut(nil)
        pencere?.contentView = nil
        web = nil
        pencere = nil
    }

    /// Netscape biçiminde çerez dosyası (yt-dlp --cookies).
    private func cerezYaz(_ cerezler: [HTTPCookie]) -> URL? {
        guard !cerezler.isEmpty else { return nil }
        var s = "# Netscape HTTP Cookie File\n"
        for c in cerezler {
            let alan = c.domain
            let alt = alan.hasPrefix(".") ? "TRUE" : "FALSE"
            let son = c.expiresDate.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
            s += [alan, alt, c.path, c.isSecure ? "TRUE" : "FALSE", son, c.name, c.value].joined(separator: "\t") + "\n"
        }
        let u = klasor.appendingPathComponent("cerez.txt")
        return (try? s.write(to: u, atomically: true, encoding: .utf8)) != nil ? u : nil
    }

    /// Yüksek puan önce: manifestler, sonra tam dosyalar; reklam ve parça adresleri elenir.
    static func puan(_ u: String) -> Int {
        let l = u.lowercased()
        if l.range(of: #"doubleclick|googlesyndication|imasdk|adservice|/ads?/|vast|preroll|advert"#, options: .regularExpression) != nil { return 0 }
        if l.range(of: #"\.m3u8(\?|#|$)|mpegurl"#, options: .regularExpression) != nil { return 100 }
        if l.range(of: #"\.mpd(\?|#|$)|dash\+xml|\.ism/manifest"#, options: .regularExpression) != nil { return 95 }
        if l.range(of: #"segment|/seg[-_]|chunk|init\.mp4|frag|range=|bytes="#, options: .regularExpression) != nil { return 5 }
        if l.range(of: #"\.(mp4|m4v|webm|mov|mkv|flv)(\?|#|$)"#, options: .regularExpression) != nil { return 60 }
        return 40   // video etiketinden ya da içerik türünden bulunan
    }

    // MARK: - WebKit

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let d = m.body as? [String: Any], let u = d["u"] as? String, !bulunan.contains(u) else { return }
        bulunan.append(u)
        sonBulus = Date()
    }

    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { ilkYuklemeBitti = true }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { ilkYuklemeBitti = true }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { bitir() }

    /// Sayfa yüklendikten sonra ana çerçeve başka yere gidemez (reklam yönlendirmeleri); başka uygulama açılmaz.
    func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let sema = a.request.url?.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "blob", "data"].contains(sema) else { decisionHandler(.cancel); return }
        if a.targetFrame?.isMainFrame == true && ilkYuklemeBitti { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }

    // Her çerçeveye belge başında eklenir.
    static let betik = #"""
    (() => {
      if (window.__olayUfku) return; window.__olayUfku = 1;
      const yolla = u => { try { webkit.messageHandlers.koku.postMessage({u}); } catch (e) {} };
      const MEDYA = /\.(m3u8|mpd|mp4|m4v|webm|mov|mkv|flv)(\?|#|$)|\.ism\/manifest/i;
      const bak = (u, kesin) => {
        if (!u) return;
        try { u = new URL(String(u), location.href).href; } catch (e) { return; }
        if (!/^https?:/.test(u)) return;
        if (kesin || MEDYA.test(u)) yolla(u);
      };
      const tur = (u, ct) => { if (ct && /mpegurl|dash\+xml|^video\//i.test(ct)) bak(u, true); };
      const f = window.fetch;
      if (f) window.fetch = function (g) {
        bak(g && g.url || g);
        return f.apply(this, arguments).then(r => { try { tur(r.url, r.headers.get('content-type')); } catch (e) {} return r; });
      };
      const ac = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (m, u) {
        bak(u);
        this.addEventListener('load', () => { try { tur(this.responseURL, this.getResponseHeader('content-type')); } catch (e) {} });
        return ac.apply(this, arguments);
      };
      try { new PerformanceObserver(l => l.getEntries().forEach(e => bak(e.name))).observe({type: 'resource', buffered: true}); } catch (e) {}
      const oynat = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function () { this.muted = true; return oynat.apply(this, arguments); };
      let tur_ = 0;
      setInterval(() => {
        tur_++;
        document.querySelectorAll('video, audio').forEach(v => {
          v.muted = true;
          const s = v.currentSrc || v.src;
          if (s && !/^(blob|data):/.test(s)) bak(s, true);
          v.querySelectorAll('source').forEach(k => bak(k.src, true));
          if (v.tagName === 'VIDEO' && v.paused && !v.__denendi) { v.__denendi = 1; v.play().catch(() => {}); }
        });
        document.querySelectorAll('meta[property^="og:video"], meta[name="twitter:player:stream"]').forEach(m => bak(m.content));
        // oynatıcı tıklama bekliyorsa bilinen oynat düğmelerine bir kez bas
        if (tur_ === 5) document.querySelectorAll('.vjs-big-play-button, .jw-icon-display, .plyr__control--overlaid, .fp-play, .mejs__overlay-button, .shaka-play-button, button[aria-label*="play" i], button[title*="play" i]').forEach((d, i) => { if (i < 3) try { d.click(); } catch (e) {} });
        if (tur_ === 4 && document.body) window.scrollTo(0, Math.min(800, document.body.scrollHeight / 3));
      }, 600);
    })();
    """#
}
