import AppKit
let space = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Icon context unavailable") }
context.setFillColor(CGColor(red: 0.975, green: 0.966, blue: 0.941, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.translateBy(x: 64, y: 736)
context.scaleBy(x: 3.2, y: -3.2)
context.setStrokeColor(CGColor(red: 0.40, green: 0.30, blue: 0.21, alpha: 1))
context.setLineWidth(2.8); context.setLineCap(.round); context.setLineJoin(.round)
for p in LedgerInk.strokes { context.addPath(p.cgPath); context.strokePath() }
guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("Icon render failed") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
// Render the full word for visual review of the same production paths.
guard let word = CGContext(data: nil, width: 1120, height: 560, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError() }
word.setFillColor(CGColor(red: 0.975, green: 0.966, blue: 0.941, alpha: 1)); word.fill(CGRect(x: 0, y: 0, width: 1120, height: 560))
word.translateBy(x: 0, y: 560); word.scaleBy(x: 4, y: -4)
word.setStrokeColor(CGColor(red: 0.57, green: 0.46, blue: 0.29, alpha: 1)); word.setLineWidth(1.7); word.setLineCap(.round); word.setLineJoin(.round)
for p in LedgerInk.strokes { word.addPath(p.cgPath); word.strokePath() }
if let image = word.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) { try png.write(to: URL(fileURLWithPath: "/tmp/ledger-wordmark.png")) }
