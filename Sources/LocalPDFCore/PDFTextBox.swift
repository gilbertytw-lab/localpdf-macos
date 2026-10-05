import AppKit
import PDFKit

/// Page coordinates and attributed text, independent of the read-only display document.
public struct PDFTextBox: Identifiable {
  public let id: String
  public let page: Int
  public var bounds: CGRect
  public var text: NSAttributedString

  public init(id: String = UUID().uuidString, page: Int, bounds: CGRect, text: NSAttributedString) {
    self.id = id
    self.page = page
    self.bounds = bounds
    self.text = NSAttributedString(attributedString: text)
  }

  static let dataKey = PDFAnnotationKey(rawValue: "/LocalPDFRTF")
  static let identityKey = PDFAnnotationKey(rawValue: "/LocalPDFID")
  static let prefix = "LocalPDFText:"

  public static func requiredHeight(for text: NSAttributedString, width: CGFloat) -> CGFloat {
    let storage = NSTextStorage(attributedString: text)
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: CGSize(width: max(1, width - 12), height: 100000))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    layout.ensureLayout(for: container)
    return ceil(layout.usedRect(for: container).height) + 12
  }

  @MainActor static func decode(_ annotation: PDFAnnotation, page: Int) -> PDFTextBox? {
    guard let name = annotation.value(forAnnotationKey: identityKey) as? String,
      name.hasPrefix(prefix),
      let encoded = annotation.value(forAnnotationKey: dataKey) as? String,
      encoded.utf8.count <= 1_400_000, let data = Data(base64Encoded: encoded),
      let text = try? NSAttributedString(
        data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil)
    else { return nil }
    guard let clean = try? normalized(text) else { return nil }
    return PDFTextBox(
      id: String(name.dropFirst(prefix.count)), page: page, bounds: annotation.bounds, text: clean)
  }

  /// Only native text attributes are accepted; pasted attachments are not document content.
  @MainActor static func normalized(_ text: NSAttributedString) throws -> NSAttributedString {
    guard !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PDFEditError.emptyText
    }
    guard text.length <= 50000 else { throw PDFEditError.textBoxOverflow }
    let output = NSMutableAttributedString(string: text.string)
    var invalid = false
    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) {
      attributes, range, _ in
      if attributes[.attachment] != nil { invalid = true }
      let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 18)
      if !font.pointSize.isFinite || !(6...144).contains(font.pointSize) { invalid = true }
      var clean: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: attributes[.foregroundColor] as? NSColor ?? NSColor.black,
      ]
      for key: NSAttributedString.Key in [
        .underlineStyle, .obliqueness, .strokeWidth, .paragraphStyle, .kern, .ligature,
      ] {
        if let value = attributes[key] { clean[key] = value }
      }
      output.setAttributes(clean, range: range)
    }
    guard !invalid else { throw PDFEditError.invalidTextStyle }
    return output
  }
}

final class RichTextAnnotation: PDFAnnotation {
  private let richText: NSAttributedString

  init(_ box: PDFTextBox, rtf: Data) {
    richText = box.text
    super.init(bounds: box.bounds, forType: .freeText, withProperties: nil)
    contents = box.text.string
    font = box.text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    fontColor = box.text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    color = .clear
    let border = PDFBorder()
    border.lineWidth = 0
    self.border = border
    setValue(PDFTextBox.prefix + box.id, forAnnotationKey: PDFTextBox.identityKey)
    setValue(rtf.base64EncodedString(), forAnnotationKey: PDFTextBox.dataKey)
  }

  required init?(coder: NSCoder) { nil }

  override func draw(with box: PDFDisplayBox, in context: CGContext) {
    context.saveGState()
    context.clip(to: bounds)
    // Match NSTextView's top-left layout, including identical insets and line padding.
    context.translateBy(x: bounds.minX + 6, y: bounds.maxY - 6)
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    let storage = NSTextStorage(attributedString: richText)
    let layout = NSLayoutManager()
    let container = NSTextContainer(
      size: CGSize(width: max(1, bounds.width - 12), height: max(1, bounds.height - 12)))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    let range = layout.glyphRange(for: container)
    layout.drawBackground(forGlyphRange: range, at: .zero)
    layout.drawGlyphs(forGlyphRange: range, at: .zero)
    NSGraphicsContext.restoreGraphicsState()
    context.restoreGState()
  }
}
