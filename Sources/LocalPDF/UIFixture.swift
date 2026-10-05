import AppKit
import CoreGraphics

enum UIFixture {
  private static let secondary = NSColor(calibratedWhite: 0.4, alpha: 1)
  static func write(to url: URL) throws {
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    for page in 1...3 {
      context.beginPDFPage(nil)
      let graphics = NSGraphicsContext(cgContext: context, flipped: false)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = graphics
      NSColor.white.setFill()
      box.fill()
      NSColor(calibratedRed: 0.06, green: 0.42, blue: 0.38, alpha: 1).setFill()
      CGRect(x: 55, y: 710, width: 38, height: 5).fill()
      draw("LOCALPDF / WORKSPACE", x: 55, y: 750, size: 10, color: secondary)
      draw(
        page == 1 ? "A simpler PDF workflow." : "Keep your ideas together.", x: 55, y: 660, size: 28
      )
      draw("Read. Arrange. Edit.", x: 55, y: 616, size: 17, color: secondary)
      draw("Your documents stay on your Mac.", x: 55, y: 535, size: 13)
      draw("Every edit starts with a recoverable snapshot.", x: 55, y: 506, size: 13)
      draw("Save a copy when you are ready to share.", x: 55, y: 477, size: 13)
      NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
      CGRect(x: 55, y: 345, width: 485, height: 82).fill()
      draw("01  /  Make space for better work", x: 72, y: 391, size: 13)
      draw(
        "A local, open-source PDF editor for macOS.", x: 72, y: 368, size: 11,
        color: secondary)
      draw("\(page) / 3", x: 55, y: 52, size: 11, color: secondary)
      if page == 1 {
        let bitmap = CGContext(
          data: nil, width: 180, height: 90, bitsPerComponent: 8, bytesPerRow: 180 * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        bitmap?.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        bitmap?.fill(CGRect(x: 0, y: 0, width: 180, height: 90))
        if let image = bitmap?.makeImage() {
          context.draw(image, in: CGRect(x: 55, y: 160, width: 180, height: 90))
        }
      }
      NSGraphicsContext.restoreGraphicsState()
      context.endPDFPage()
    }
    context.closePDF()
  }

  private static func draw(
    _ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = .black
  ) {
    (text as NSString).draw(
      at: CGPoint(x: x, y: y),
      withAttributes: [
        .font: NSFont(name: "Helvetica", size: size) ?? NSFont.systemFont(ofSize: size),
        .foregroundColor: color, .kern: 0, .ligature: 0,
      ])
  }
}
