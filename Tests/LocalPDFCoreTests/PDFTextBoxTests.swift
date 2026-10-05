import AppKit
import LocalPDFCore
import PDFKit
import Testing

@Suite("Editable rich text boxes")
@MainActor
struct PDFTextBoxTests {
  @Test func mixedStylesSurviveSaveReopenAndAnotherEdit() throws {
    let fixture = try TextFixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let original = try Data(contentsOf: fixture.source)
    let rich = NSMutableAttributedString(
      string: "文字框 Bold italic\nBlue underline",
      attributes: [.font: NSFont(name: "Helvetica", size: 22)!, .foregroundColor: NSColor.red])
    let bold = (rich.string as NSString).range(of: "Bold")
    rich.addAttribute(.font, value: NSFont(name: "Helvetica-Bold", size: 26)!, range: bold)
    rich.addAttribute(
      .obliqueness, value: 0.2, range: (rich.string as NSString).range(of: "italic"))
    let blue = (rich.string as NSString).range(of: "Blue underline")
    rich.addAttributes(
      [.foregroundColor: NSColor.blue, .underlineStyle: NSUnderlineStyle.single.rawValue],
      range: blue)
    let box = PDFTextBox(
      page: 0, bounds: CGRect(x: 50, y: 120, width: 380, height: 140), text: rich)
    try workspace.saveTextBox(box)
    try workspace.saveCopy(to: fixture.output)
    try workspace.open(fixture.output)
    let reopened = try #require(workspace.textBoxes(page: 0).first)
    #expect(reopened.id == box.id)
    #expect(reopened.text.string == rich.string)
    let font = try #require(
      reopened.text.attribute(.font, at: bold.location, effectiveRange: nil) as? NSFont)
    #expect(font.fontName == "Helvetica-Bold" && font.pointSize == 26)
    #expect(
      (reopened.text.attribute(.underlineStyle, at: blue.location, effectiveRange: nil) as? NSNumber)?
        .intValue == 1)
    #expect(
      (reopened.text.attribute(.obliqueness, at: 13, effectiveRange: nil) as? NSNumber)?.doubleValue
        == 0.2)
    let annotation = try #require(workspace.document?.page(at: 0)?.annotations.first)
    #expect(annotation.hasAppearanceStream)
    #expect(annotation.type == "FreeText")
    var moved = reopened
    moved.bounds.origin = CGPoint(x: 90, y: 300)
    try workspace.saveTextBox(moved)
    #expect(workspace.textBoxes(page: 0).count == 1)
    #expect(workspace.textBoxes(page: 0).first?.bounds.minX == 90)
    #expect(try Data(contentsOf: fixture.source) == original)
  }

  @Test func editingMoveDeleteUndoRedoRetainsIdentityAndStyles() throws {
    let fixture = try TextFixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    var box = sample()
    try workspace.saveTextBox(box)
    box.text = NSAttributedString(
      string: "Second version",
      attributes: [
        .font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.blue, .underlineStyle: 1,
      ])
    box.bounds.origin = CGPoint(x: 120, y: 350)
    try workspace.saveTextBox(box)
    try workspace.undo()
    #expect(workspace.textBoxes(page: 0).first?.text.string == "Hello 文字")
    try workspace.redo()
    #expect(workspace.textBoxes(page: 0).first?.bounds.minY == 350)
    try workspace.removeTextBox(id: box.id, page: 0)
    #expect(workspace.textBoxes(page: 0).isEmpty)
    try workspace.undo()
    #expect(workspace.textBoxes(page: 0).first?.id == box.id)
    #expect(workspace.textBoxes(page: 0).first?.text.string == "Second version")
  }

  @Test func clampingAndGrowthOnRotatedNonzeroCrop() throws {
    let fixture = try TextFixture(rotation: 90)
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let page = try #require(workspace.document?.page(at: 0))
    let crop = page.bounds(for: .cropBox)
    var box = sample()
    box.bounds = CGRect(x: 1000, y: -1000, width: 200, height: 24)
    box.text = NSAttributedString(
      string: "One\nTwo\nThree", attributes: [.font: NSFont.systemFont(ofSize: 24)])
    try workspace.saveTextBox(box)
    let saved = try #require(workspace.textBoxes(page: 0).first)
    #expect(crop.contains(saved.bounds))
    #expect(saved.bounds.height > 24)
    #expect(page.rotation == 90)
    let placed = try workspace.textBoxBounds(
      page: 0, at: CGPoint(x: crop.maxX - 1, y: crop.minY + 1))
    #expect(crop.contains(placed))
  }

  @Test func invalidDraftDoesNotChangeDocumentOrUndo() throws {
    let fixture = try TextFixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    var box = sample()
    box.bounds.size.width = .nan
    #expect(throws: PDFEditError.invalidPosition) { try workspace.saveTextBox(box) }
    box = sample()
    box.text = NSAttributedString(string: "")
    #expect(throws: PDFEditError.emptyText) { try workspace.saveTextBox(box) }
    box.text = NSAttributedString(
      string: String(repeating: "line\n", count: 300),
      attributes: [.font: NSFont.systemFont(ofSize: 20)])
    #expect(throws: PDFEditError.textBoxOverflow) { try workspace.saveTextBox(box) }
    box.text = NSAttributedString(
      string: "too large", attributes: [.font: NSFont.systemFont(ofSize: 200)])
    #expect(throws: PDFEditError.invalidTextStyle) { try workspace.saveTextBox(box) }
    #expect(!workspace.canUndo && !workspace.isDirty && workspace.textBoxes(page: 0).isEmpty)
  }

  @Test func appearanceHasColoredTextAndTransparentBackground() throws {
    let fixture = try TextFixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let box = PDFTextBox(
      page: 0, bounds: CGRect(x: 50, y: 200, width: 380, height: 120),
      text: NSAttributedString(
        string: "RED TEXT 文字\nUnderlined",
        attributes: [
          .font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.red, .underlineStyle: 1,
        ]))
    try workspace.saveTextBox(box)
    try workspace.saveCopy(to: fixture.output)
    let reopened = try #require(PDFDocument(url: fixture.output))
    let page = try #require(reopened.page(at: 0))
    let image = page.thumbnail(of: CGSize(width: 500, height: 600), for: .cropBox)
    let data = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: data))
    var redPixels = 0
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.redComponent > 0.7,
          color.greenComponent < 0.5, color.blueComponent < 0.5
        {
          redPixels += 1
        }
      }
    }
    #expect(redPixels > 200)
    // Generate stable independent-reader evidence without making it a runtime dependency.
    let evidence = fixture.folder.deletingLastPathComponent().appendingPathComponent(
      "rich-text-evidence.pdf")
    try Data(contentsOf: fixture.output).write(to: evidence, options: .atomic)
  }

  @Test func oversizedRichAppearanceRollsBack() throws {
    let fixture = try TextFixture()
    defer { fixture.clean() }
    let baseline = try Data(contentsOf: fixture.source).count
    let workspace = PDFWorkspace(historyByteLimit: baseline + 256)
    try workspace.open(fixture.source)
    #expect(throws: PDFEditError.undoLimit) { try workspace.saveTextBox(sample()) }
    #expect(workspace.textBoxes(page: 0).isEmpty && !workspace.isDirty && !workspace.canUndo)
  }

  private func sample() -> PDFTextBox {
    PDFTextBox(
      page: 0, bounds: CGRect(x: 50, y: 120, width: 300, height: 100),
      text: NSAttributedString(
        string: "Hello 文字", attributes: [.font: NSFont.systemFont(ofSize: 18)]))
  }
}

@MainActor
private struct TextFixture {
  let folder: URL
  let source: URL
  let output: URL
  init(rotation: Int = 0) throws {
    folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
      ".build/text-fixtures/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    source = folder.appendingPathComponent("source.pdf")
    output = folder.appendingPathComponent("output.pdf")
    var media = CGRect(x: 0, y: 0, width: 500, height: 600)
    let context = try #require(CGContext(source as CFURL, mediaBox: &media, nil))
    context.beginPDFPage(nil)
    context.setFillColor(NSColor.white.cgColor)
    context.fill(media)
    context.endPDFPage()
    context.closePDF()
    if rotation != 0 {
      let doc = try #require(PDFDocument(url: source))
      let page = try #require(doc.page(at: 0))
      page.rotation = rotation
      page.setBounds(CGRect(x: 20, y: 30, width: 450, height: 530), for: .cropBox)
      #expect(doc.write(to: source))
    }
  }
  func clean() { try? FileManager.default.removeItem(at: folder) }
}
