// Uygulama simgesi: kadife karanlıkta eğik bir yığılma diski ve ışığı bükülmüş arka yüzü.
// Kullanım: ikon <cikti.png>

import Cocoa

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let c = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func renk(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
func gradyan(_ r: [CGColor], _ k: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: cs, colors: r as CFArray, locations: k)! }

let O = CGPoint(x: 512, y: 512)
let govde = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186, cornerHeight: 186, transform: nil)

// gövde ve gölgesi
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: renk(0, 0, 0, 0.45))
c.addPath(govde); c.setFillColor(renk(0.02, 0.015, 0.04)); c.fillPath()
c.restoreGState()

c.saveGState()
c.addPath(govde); c.clip()
c.drawRadialGradient(gradyan([renk(0.16, 0.06, 0.24), renk(0.05, 0.03, 0.10), renk(0.01, 0.01, 0.03)], [0, 0.55, 1]),
                     startCenter: CGPoint(x: 470, y: 560), startRadius: 0, endCenter: O, endRadius: 560, options: [])
// yıldızlar (sabit tohum)
var tohum: UInt64 = 0x9E3779B97F4A7C15
func rnd() -> CGFloat { tohum = tohum &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(tohum >> 33) / CGFloat(1 << 31) }
for _ in 0..<140 {
    let p = CGPoint(x: 100 + rnd() * 824, y: 100 + rnd() * 824), r = 0.8 + rnd() * 2.2
    c.setFillColor(renk(1, 0.92 + rnd() * 0.08, 0.85 + rnd() * 0.15, 0.25 + rnd() * 0.6))
    c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
}
// sıcak hale
c.drawRadialGradient(gradyan([renk(1, 0.55, 0.2, 0.32), renk(1, 0.4, 0.15, 0)], [0, 1]),
                     startCenter: O, startRadius: 120, endCenter: O, endRadius: 440, options: [])

// disk şeridi (eğik elips halka), yatay renk geçişiyle: solda yaklaşan taraf parlak
func diskSeridi(ust: Bool) {
    c.saveGState()
    c.clip(to: ust ? CGRect(x: 0, y: 512, width: 1024, height: 512) : CGRect(x: 0, y: 0, width: 1024, height: 512))
    let dis = CGPath(ellipseIn: CGRect(x: 512 - 380, y: 512 - 66, width: 760, height: 132), transform: nil)
    let ic = CGPath(ellipseIn: CGRect(x: 512 - 170, y: 512 - 30, width: 340, height: 60), transform: nil)
    let yol = CGMutablePath(); yol.addPath(dis); yol.addPath(ic)
    c.setShadow(offset: .zero, blur: 40, color: renk(1, 0.55, 0.2, 0.9))
    c.addPath(yol); c.setFillColor(renk(1, 0.6, 0.25)); c.fillPath(using: .evenOdd)
    c.setShadow(offset: .zero, blur: 0, color: nil)
    c.addPath(yol); c.clip(using: .evenOdd)
    c.drawLinearGradient(gradyan([renk(1, 0.97, 0.88), renk(1, 0.72, 0.38), renk(0.85, 0.32, 0.18), renk(0.42, 0.08, 0.24)], [0, 0.35, 0.7, 1]),
                         start: CGPoint(x: 140, y: 512), end: CGPoint(x: 890, y: 512), options: [])
    c.restoreGState()
}

// arka yüz: ışık bükülüp deliğin çevresinde halka olur
func bukulmusHalka() {
    c.saveGState()
    let halka = CGPath(ellipseIn: CGRect(x: 512 - 182, y: 512 - 172, width: 364, height: 344), transform: nil)
    c.setShadow(offset: .zero, blur: 46, color: renk(1, 0.6, 0.25, 0.95))
    c.addPath(halka); c.setLineWidth(40); c.setStrokeColor(renk(1, 0.65, 0.3)); c.strokePath()
    c.setShadow(offset: .zero, blur: 0, color: nil)
    c.addPath(halka); c.setLineWidth(40); c.replacePathWithStrokedPath(); c.clip()
    c.drawLinearGradient(gradyan([renk(1, 0.96, 0.86), renk(1, 0.66, 0.32), renk(0.7, 0.2, 0.25)], [0, 0.5, 1]),
                         start: CGPoint(x: 330, y: 600), end: CGPoint(x: 700, y: 420), options: [])
    c.restoreGState()
}

diskSeridi(ust: true)
bukulmusHalka()
// gölge: olay ufku ve ince foton halkası
c.setFillColor(renk(0, 0, 0)); c.fillEllipse(in: CGRect(x: 512 - 150, y: 512 - 150, width: 300, height: 300))
c.saveGState()
c.setShadow(offset: .zero, blur: 14, color: renk(1, 0.85, 0.6, 1))
c.setStrokeColor(renk(1, 0.9, 0.75, 0.95)); c.setLineWidth(3.5)
c.strokeEllipse(in: CGRect(x: 512 - 152, y: 512 - 152, width: 304, height: 304))
c.restoreGState()
diskSeridi(ust: false)
c.restoreGState()

let img = c.makeImage()!
let veri = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
try! veri.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
