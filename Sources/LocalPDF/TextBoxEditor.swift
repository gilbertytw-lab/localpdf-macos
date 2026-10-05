import AppKit
import LocalPDFCore
import PDFKit

@MainActor
struct TextBoxFormat {
  var family = "Helvetica"
  var size = 18.0
  var color = NSColor.black
  var bold = false
  var italic = false
  var underline = false
  var alignment = NSTextAlignment.left

  var attributes: [NSAttributedString.Key: Any] {
    let font = NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    var attributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
    ]
    attributes = TextBoxEditor.traits(attributes, bold: bold, italic: italic)
    if underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
    return attributes
  }
}

enum TextFormatField { case family, size, color, bold, italic, underline, alignment }

@MainActor
final class TextBoxEditor: NSView, NSTextViewDelegate {
  private(set) var box: PDFTextBox
  private let original: PDFTextBox?
  weak var controller: DocumentController?
  private let scroll = NSScrollView()
  let textView = BoxTextView()
  private var dragStart: (point: CGPoint, bounds: CGRect, resize: Bool)?
  private var loading = false

  var changed: Bool {
    guard let original else {
      return !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return box.bounds != original.bounds || !textView.attributedString().isEqual(to: original.text)
  }

  init(box: PDFTextBox, original: PDFTextBox?, controller: DocumentController) {
    self.box = box
    self.original = original
    self.controller = controller
    super.init(frame: .zero)
    scroll.borderType = .noBorder
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    textView.isRichText = true
    textView.importsGraphics = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 6, height: 6)
    textView.textContainer?.lineFragmentPadding = 0
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(width: 100000, height: 100000)
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.containerSize.height = 100000
    textView.setAccessibilityLabel("頁面文字框")
    scroll.documentView = textView
    addSubview(scroll)
    loading = true
    textView.textStorage?.setAttributedString(box.text)
    textView.typingAttributes = controller.textFormat.attributes
    textView.delegate = self
    loading = false
    setAccessibilityLabel("可移動文字框；拖曳上方把手移動，右下角調整大小")
  }

  required init?(coder: NSCoder) { nil }

  func focus() {
    window?.makeFirstResponder(textView)
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    updateFormat()
  }

  func snapshot() -> PDFTextBox {
    PDFTextBox(id: box.id, page: box.page, bounds: box.bounds, text: textView.attributedString())
  }

  func position(in pdfView: PDFView) {
    guard let page = pdfView.document?.page(at: box.page) else { return }
    let origin = pdfView.convert(box.bounds.origin, from: page)
    let axis = pdfView.convert(CGPoint(x: box.bounds.minX + 1, y: box.bounds.minY), from: page)
    let delta = CGPoint(x: axis.x - origin.x, y: axis.y - origin.y)
    let scale = hypot(delta.x, delta.y)
    guard scale.isFinite, scale > 0 else { return }
    frameRotation = 0
    frame = CGRect(
      origin: origin,
      size: CGSize(width: box.bounds.width * scale, height: (box.bounds.height + 22) * scale))
    bounds = CGRect(x: 0, y: 0, width: box.bounds.width, height: box.bounds.height + 22)
    frameRotation = atan2(delta.y, delta.x) * 180 / .pi
    scroll.frame = CGRect(x: 0, y: 0, width: box.bounds.width, height: box.bounds.height)
    textView.setFrameSize(
      NSSize(
        width: scroll.contentSize.width,
        height: max(scroll.contentSize.height, textView.frame.height)))
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let height = box.bounds.height
    NSColor.white.withAlphaComponent(0.94).setFill()
    CGRect(x: 0, y: 0, width: box.bounds.width, height: height).fill()
    NSColor(calibratedRed: 0.05, green: 0.43, blue: 0.39, alpha: 1).setFill()
    CGRect(x: 0, y: height, width: box.bounds.width, height: 22).fill()
    CGRect(x: box.bounds.width - 11, y: 0, width: 11, height: 11).fill()
    let border = NSBezierPath(
      rect: CGRect(x: 0.5, y: 0.5, width: box.bounds.width - 1, height: height - 1))
    border.lineWidth = 1
    border.stroke()
    ("⠿ 拖曳移動文字框" as NSString).draw(
      at: CGPoint(x: 7, y: height + 5),
      withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.white])
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    if local.x >= bounds.maxX - 14, local.y < 14, bounds.contains(local) { return self }
    return super.hitTest(point)
  }

  override func resetCursorRects() {
    addCursorRect(
      CGRect(x: 0, y: box.bounds.height, width: box.bounds.width, height: 22), cursor: .openHand)
    addCursorRect(CGRect(x: box.bounds.width - 14, y: 0, width: 14, height: 14), cursor: .crosshair)
  }

  private func pagePoint(_ event: NSEvent) -> CGPoint? {
    guard let pdfView = controller?.pdfView, let page = pdfView.document?.page(at: box.page) else {
      return nil
    }
    return pdfView.convert(pdfView.convert(event.locationInWindow, from: nil), to: page)
  }

  override func mouseDown(with event: NSEvent) {
    guard let point = pagePoint(event) else { return }
    let local = convert(event.locationInWindow, from: nil)
    dragStart = (point, box.bounds, local.y < 14)
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start = dragStart, let point = pagePoint(event), let pdfView = controller?.pdfView,
      let page = pdfView.document?.page(at: box.page)
    else { return }
    let crop = page.bounds(for: .cropBox)
    let delta = CGPoint(x: point.x - start.point.x, y: point.y - start.point.y)
    if start.resize {
      let width = max(48, min(start.bounds.width + delta.x, crop.maxX - start.bounds.minX))
      let height = max(36, min(start.bounds.height - delta.y, start.bounds.maxY - crop.minY))
      box.bounds = CGRect(
        x: start.bounds.minX, y: start.bounds.maxY - height, width: width, height: height)
    } else {
      box.bounds.origin = CGPoint(
        x: max(crop.minX, min(start.bounds.minX + delta.x, crop.maxX - box.bounds.width)),
        y: max(crop.minY, min(start.bounds.minY + delta.y, crop.maxY - box.bounds.height)))
    }
    position(in: pdfView)
    controller?.textDraftChanged()
  }

  override func mouseUp(with event: NSEvent) { dragStart = nil }

  func textDidChange(_ notification: Notification) {
    guard !loading else { return }
    controller?.textDraftChanged()
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    if !loading { updateFormat() }
  }

  func updateFormat() {
    guard let controller else { return }
    let selection = textView.selectedRange()
    let attributes =
      textView.string.isEmpty
      ? textView.typingAttributes
      : textView.attributedString().attributes(
        at: min(selection.location, textView.string.utf16.count - 1), effectiveRange: nil)
    let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 18)
    let traits = NSFontManager.shared.traits(of: font)
    controller.textFormat = TextBoxFormat(
      family: font.familyName ?? "Helvetica", size: font.pointSize,
      color: attributes[.foregroundColor] as? NSColor ?? .black,
      bold: traits.contains(.boldFontMask)
        || (attributes[.strokeWidth] as? NSNumber)?.doubleValue ?? 0 < 0,
      italic: traits.contains(.italicFontMask)
        || (attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0 != 0,
      underline: (attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0 != 0,
      alignment: (attributes[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .left)
  }

  static func traits(_ input: [NSAttributedString.Key: Any], bold: Bool, italic: Bool)
    -> [NSAttributedString.Key: Any]
  {
    var output = input
    var font = input[.font] as? NSFont ?? NSFont.systemFont(ofSize: 18)
    font =
      bold
      ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
      : NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
    font =
      italic
      ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
      : NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
    output[.font] = font
    let traits = NSFontManager.shared.traits(of: font)
    output[.strokeWidth] = bold && !traits.contains(.boldFontMask) ? -2.5 : 0
    output[.obliqueness] = italic && !traits.contains(.italicFontMask) ? 0.2 : 0
    return output
  }

  func apply(_ field: TextFormatField, format: TextBoxFormat) {
    guard let storage = textView.textStorage else { return }
    var range = textView.selectedRange()
    if range.length == 0 { range = NSRange(location: 0, length: storage.length) }
    if field == .alignment, range.length > 0 {
      range = (storage.string as NSString).paragraphRange(for: range)
    }
    func changed(_ input: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
      var attributes = input
      let font = input[.font] as? NSFont ?? NSFont.systemFont(ofSize: format.size)
      switch field {
      case .family:
        let new = NSFontManager.shared.convert(font, toFamily: format.family)
        attributes[.font] = new
        attributes = Self.traits(attributes, bold: format.bold, italic: format.italic)
      case .size: attributes[.font] = NSFontManager.shared.convert(font, toSize: format.size)
      case .color: attributes[.foregroundColor] = format.color
      case .bold:
        attributes = Self.traits(
          attributes, bold: format.bold,
          italic: NSFontManager.shared.traits(of: font).contains(.italicFontMask)
            || (input[.obliqueness] as? NSNumber)?.doubleValue ?? 0 != 0)
      case .italic:
        attributes = Self.traits(
          attributes,
          bold: NSFontManager.shared.traits(of: font).contains(.boldFontMask)
            || (input[.strokeWidth] as? NSNumber)?.doubleValue ?? 0 < 0, italic: format.italic)
      case .underline: attributes[.underlineStyle] = format.underline ? 1 : 0
      case .alignment:
        let paragraph =
          (input[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
          ?? NSMutableParagraphStyle()
        paragraph.alignment = format.alignment
        attributes[.paragraphStyle] = paragraph
      }
      return attributes
    }
    let before = NSAttributedString(attributedString: storage)
    if range.length > 0 {
      let segment = storage.attributedSubstring(from: range)
      segment.enumerateAttributes(in: NSRange(location: 0, length: segment.length)) {
        attributes, run, _ in
        storage.setAttributes(
          changed(attributes),
          range: NSRange(location: range.location + run.location, length: run.length))
      }
      textView.undoManager?.registerUndo(withTarget: self) { target in
        MainActor.assumeIsolated { target.restore(before) }
      }
    }
    textView.typingAttributes = changed(textView.typingAttributes)
    controller?.textDraftChanged()
    if field == .bold || field == .italic || field == .underline || field == .alignment {
      window?.makeFirstResponder(textView)
    }
  }

  private func restore(_ text: NSAttributedString) {
    let before = textView.attributedString()
    textView.undoManager?.registerUndo(withTarget: self) { target in
      MainActor.assumeIsolated { target.restore(before) }
    }
    textView.textStorage?.setAttributedString(text)
    controller?.textDraftChanged()
    updateFormat()
  }
}

@MainActor
final class BoxTextView: NSTextView {
  private let localUndo = UndoManager()
  override var undoManager: UndoManager? { localUndo }
}
