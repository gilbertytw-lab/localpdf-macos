import CoreGraphics
import Foundation

// Reject a candidate when rebuilding its stream changes unselected content.
// This is a bounded pixel check, not a promise of print or archival fidelity.
enum PDFContentAppearance {
  private struct Render {
    let data: Data
    let width: Int
    let height: Int
    let transform: CGAffineTransform
  }

  private static func render(_ data: Data, page index: Int) throws -> Render {
    guard let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider),
      let page = pdf.page(at: index + 1)
    else { throw PDFContentError.engineFailure }
    let crop = page.getBoxRect(.cropBox)
    let rotated = abs(page.rotationAngle) % 180 == 90
    let size = rotated ? CGSize(width: crop.height, height: crop.width) : crop.size
    let scale = min(1, 1024 / max(size.width, size.height))
    let width = max(1, Int(ceil(size.width * scale)))
    let height = max(1, Int(ceil(size.height * scale)))
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    let drawing = page.getDrawingTransform(
      .cropBox, rect: rect, rotate: 0, preserveAspectRatio: true
    )
    let transform = drawing.concatenating(
      CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(height)))
    var pixels = Data(count: width * height * 4)
    try pixels.withUnsafeMutableBytes { bytes in
      guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
          data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
      else { throw PDFContentError.engineFailure }
      context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
      context.fill(rect)
      context.concatenate(drawing)
      context.drawPDFPage(page)
    }
    return Render(data: pixels, width: width, height: height, transform: transform)
  }

  static func validate(before: Data, after: Data, page: Int, allowed: CGRect) throws {
    let first = try render(before, page: page)
    let second = try render(after, page: page)
    guard first.width == second.width, first.height == second.height else {
      throw PDFContentError.engineFailure
    }
    let region = allowed.applying(first.transform).insetBy(dx: -5, dy: -5)
    var changed = 0
    first.data.withUnsafeBytes { left in
      second.data.withUnsafeBytes { right in
        let a = left.bindMemory(to: UInt8.self)
        let b = right.bindMemory(to: UInt8.self)
        for y in 0..<first.height {
          for x in 0..<first.width where !region.contains(CGPoint(x: x, y: y)) {
            let offset = (y * first.width + x) * 4
            if (0..<3).contains(where: { abs(Int(a[offset + $0]) - Int(b[offset + $0])) > 24 }) {
              changed += 1
            }
          }
        }
      }
    }
    guard changed <= max(24, first.width * first.height / 2000) else {
      throw PDFContentError.unsupported("此頁其他內容的外觀也會改變，已取消修改。特殊字距、字型或色彩需進一步支援。")
    }
  }
}
