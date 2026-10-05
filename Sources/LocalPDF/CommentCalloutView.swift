import AppKit
import PDFKit

@MainActor
final class CommentCalloutView: NSView, NSTextFieldDelegate {
  private let field = NSTextField()
  private let draft: Bool
  private let onCommit: ((String) -> Void)?
  private let onChange: ((String) -> Void)?
  private var box = CGRect.zero
  private var start = CGPoint.zero
  private var tip = CGPoint.zero
  private let boxSize = CGSize(width: 250, height: 86)

  var draftText: String { field.currentEditor()?.string ?? field.stringValue }

  func setDraftText(_ text: String) {
    field.stringValue = text
    onChange?(text)
  }

  init(
    text: String, draft: Bool, onCommit: ((String) -> Void)? = nil,
    onChange: ((String) -> Void)? = nil
  ) {
    self.draft = draft
    self.onCommit = onCommit
    self.onChange = onChange
    super.init(frame: .zero)
    field.stringValue = text
    field.isEditable = draft
    field.isSelectable = draft
    field.isBordered = false
    field.drawsBackground = false
    field.usesSingleLineMode = false
    field.cell?.wraps = true
    field.cell?.isScrollable = false
    field.maximumNumberOfLines = 4
    field.font = NSFont.systemFont(ofSize: 13)
    field.textColor = .labelColor
    field.placeholderString = draft ? "輸入註解，Enter 或點外確認" : nil
    field.setAccessibilityLabel(draft ? "註解文字方塊" : "註解內容")
    field.delegate = self
    field.target = self
    field.action = #selector(pressedEnter)
    addSubview(field)
    setAccessibilityLabel(draft ? "新增註解" : "滑鼠懸停註解")
  }

  required init?(coder: NSCoder) { nil }

  @objc private func pressedEnter() { onCommit?(field.stringValue) }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
    -> Bool
  {
    guard commandSelector == #selector(NSResponder.insertNewline(_:)),
      !textView.hasMarkedText()
    else { return false }
    onCommit?(textView.string)
    return true
  }

  func controlTextDidChange(_ obj: Notification) { onChange?(field.stringValue) }

  func focus() { window?.makeFirstResponder(field) }

  func position(in view: PDFView, page: PDFPage, anchor: CGRect) {
    let point = view.convert(CGPoint(x: anchor.maxX, y: anchor.maxY), from: page)
    let dx: CGFloat = point.x + boxSize.width + 24 < view.bounds.maxX ? 24 : -24
    let dy: CGFloat = point.y + boxSize.height + 24 < view.bounds.maxY ? 24 : -24
    let absoluteBox = CGRect(
      x: point.x + dx - (dx < 0 ? boxSize.width : 0),
      y: point.y + dy - (dy < 0 ? boxSize.height : 0),
      width: boxSize.width, height: boxSize.height)
    let newFrame = absoluteBox.union(CGRect(origin: point, size: .zero)).insetBy(dx: -2, dy: -2)
    if frame != newFrame { frame = newFrame }
    start = CGPoint(x: point.x - newFrame.minX, y: point.y - newFrame.minY)
    box = absoluteBox.offsetBy(dx: -newFrame.minX, dy: -newFrame.minY)
    tip = CGPoint(
      x: (dx > 0 ? box.minX : box.maxX), y: (dy > 0 ? box.minY : box.maxY))
    field.frame = box.insetBy(dx: 10, dy: 10)
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let red = NSColor(calibratedRed: 0.76, green: 0.08, blue: 0.12, alpha: 1)
    red.setStroke()
    let pointer = NSBezierPath()
    pointer.lineWidth = 2
    pointer.move(to: start)
    pointer.line(to: tip)
    let length = hypot(tip.x - start.x, tip.y - start.y)
    if length > 0 {
      let x = (tip.x - start.x) / length
      let y = (tip.y - start.y) / length
      let base = CGPoint(x: tip.x - x * 8, y: tip.y - y * 8)
      pointer.move(to: CGPoint(x: base.x - y * 4, y: base.y + x * 4))
      pointer.line(to: tip)
      pointer.line(to: CGPoint(x: base.x + y * 4, y: base.y - x * 4))
    }
    pointer.stroke()
    NSColor.white.withAlphaComponent(0.98).setFill()
    let bubble = NSBezierPath(roundedRect: box, xRadius: 9, yRadius: 9)
    bubble.fill()
    red.setStroke()
    bubble.lineWidth = 1.5
    bubble.stroke()
  }
}
