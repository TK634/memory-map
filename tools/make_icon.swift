import AppKit

// あしあと アプリアイコン生成 (1024x1024)
// デザイン: 暖色グラデ背景 + 白丸バッジ + オレンジの足あと(アプリ内ピンと同じ世界観)

let W = 1024, H = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("rep") }
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// 1. 背景: 上=薄クリーム → 下=あたたかいオレンジベージュ
let grad = NSGradient(colors: [rgb(0xFFF6EA), rgb(0xFFD9A8)])!
grad.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

// うっすら大きな円(背景の飾り)
rgb(0xE8963E).withAlphaComponent(0.10).setFill()
NSBezierPath(ovalIn: NSRect(x: -180, y: -180, width: 700, height: 700)).fill()
NSBezierPath(ovalIn: NSRect(x: 620, y: 640, width: 560, height: 560)).fill()

// 2. 白丸バッジ(影付き)
let badge = NSRect(x: 172, y: 172, width: 680, height: 680)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -18)
NSGraphicsContext.current?.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
NSBezierPath(ovalIn: badge).fill()
NSGraphicsContext.current?.restoreGraphicsState()

// バッジの縁(薄オレンジ)
let ring = NSBezierPath(ovalIn: badge.insetBy(dx: 14, dy: 14))
ring.lineWidth = 22
rgb(0xE8963E).withAlphaComponent(0.35).setStroke()
ring.stroke()

// 3. 足あとシンボル(オレンジ)
let config = NSImage.SymbolConfiguration(pointSize: 340, weight: .bold)
guard let base = NSImage(systemSymbolName: "shoeprints.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) else { fatalError("symbol") }

// オレンジに着色
let tinted = NSImage(size: base.size)
tinted.lockFocus()
base.draw(in: NSRect(origin: .zero, size: base.size))
rgb(0xE8963E).set()
NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
tinted.unlockFocus()

// 中央に描画(バッジ内に収まるサイズへ)
let target: CGFloat = 430
let aspect = base.size.height / base.size.width
let dw = target
let dh = target * aspect
let dst = NSRect(x: (CGFloat(W) - dw) / 2, y: (CGFloat(H) - dh) / 2, width: dw, height: dh)
tinted.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1)

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

// 4. PNG書き出し
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
let out = "AppIcon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
