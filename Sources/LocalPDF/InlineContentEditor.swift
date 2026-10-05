import AppKit
import LocalPDFCore
import PDFKit

@MainActor
final class InlineContentEditor: NSView, NSTextFieldDelegate {
  let item: PDFContentItem
  weak var controller: DocumentController?
  private let field = NSTextField()

  var text: String { field.stringValue }
  var changed: Bool { text != item.text }
  var textUndoManager: UndoManager? { field.currentEditor()?.undoManager }

  init(item: PDFContentItem, controller: DocumentController) {
    self.item = item
    self.controller = controller
    super.init(frame: .zero)
    field.stringValue = item.text
    field.font = NSFont.systemFont(ofSize: max(11, min(32, item.bounds.height * 0.82)))
    field.textColor = .black
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.usesSingleLineMode = true
    field.lineBreakMode = .byClipping
    field.delegate = self
    field.setAccessibilityLabel("直接修改原有文字")
    addSubview(field)
    setAccessibilityLabel("頁面內原有文字編輯欄")
  }

  required init?(coder: NSCoder) { nil }

  func focus() {
    window?.makeFirstResponder(field)
    if let editor = field.currentEditor() {
      (editor as? NSTextView)?.allowsUndo = true
      editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }
  }

  func setText(_ value: String) {
    field.stringValue = value
    controller?.contentDraftChanged()
  }

  func position(in pdfView: PDFView) {
    guard let page = pdfView.document?.page(at: item.page) else { return }
    let editorFrame = pageFrame(in: page)
    let origin = pdfView.convert(editorFrame.origin, from: page)
    let axis = pdfView.convert(CGPoint(x: editorFrame.minX + 1, y: editorFrame.minY), from: page)
    let delta = CGPoint(x: axis.x - origin.x, y: axis.y - origin.y)
    let scale = hypot(delta.x, delta.y)
    guard scale.isFinite, scale > 0 else { return }
    frameRotation = 0
    frame = CGRect(
      origin: origin,
      size: CGSize(width: editorFrame.width * scale, height: editorFrame.height * scale))
    bounds = CGRect(x: 0, y: 0, width: editorFrame.width, height: editorFrame.height)
    frameRotation = atan2(delta.y, delta.x) * 180 / .pi
    field.frame = CGRect(x: 7, y: 4, width: editorFrame.width - 14, height: editorFrame.height - 8)
    needsDisplay = true
  }

  func pageFrame(in page: PDFPage) -> CGRect {
    let crop = page.bounds(for: .cropBox)
    let width = min(max(item.bounds.width + 18, 160), crop.width)
    let x = max(crop.minX, min(item.bounds.minX, crop.maxX - width))
    let height = min(max(item.bounds.height + 12, 25), crop.height)
    let y = max(crop.minY, min(item.bounds.minY - 6, crop.maxY - height))
    return CGRect(x: x, y: y, width: width, height: height)
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.setFill()
    bounds.fill()
    let border = NSBezierPath(
      roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: 4, yRadius: 4)
    border.lineWidth = 1.5
    NSColor(calibratedRed: 0.05, green: 0.43, blue: 0.39, alpha: 1).setStroke()
    border.stroke()
  }

  func controlTextDidChange(_ notification: Notification) { controller?.contentDraftChanged() }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
    -> Bool
  {
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
      controller?.completeContentEditing()
      return true
    }
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      controller?.cancelContentEditing()
      return true
    }
    return false
  }
}
