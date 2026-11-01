import AppKit
let output = CommandLine.arguments[1]
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(red: 223/255, green: 234/255, blue: 1, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
for index in 0..<6 {
  NSGraphicsContext.saveGraphicsState()
  let petal = NSBezierPath(roundedRect: NSRect(x: 445, y: 644, width: 134, height: 210), xRadius: 44, yRadius: 44)
  petal.transform(using: AffineTransform(translationByX: -512, byY: -512))
  var rotation = AffineTransform()
  rotation.rotate(byDegrees: CGFloat(index * 60))
  petal.transform(using: rotation)
  petal.transform(using: AffineTransform(translationByX: 512, byY: 512))
  if index == 5 { NSColor.white.setFill() }
  else { NSColor(red: 48/255, green: 104/255, blue: 219/255, alpha: 1).setFill() }
  petal.fill()
  NSGraphicsContext.restoreGraphicsState()
}
NSColor(red: 48/255, green: 104/255, blue: 219/255, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 448, y: 448, width: 128, height: 128)).fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
