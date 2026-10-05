import AppKit
import LocalPDFCore
import PDFKit
import Testing

@Suite("Existing PDF text and image objects")
@MainActor
struct PDFContentTests {
  @Test func textReplacementPersistsWithUndoAndOriginalProtection() throws {
    let fixture = try ContentFixture()
    defer { fixture.clean() }
    let original = try Data(contentsOf: fixture.source)
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    try workspace.addNote("Preserve annotation", page: 0, at: CGPoint(x: 50, y: 200))
    try workspace.addText("Editable box", page: 0, at: CGPoint(x: 220, y: 260))
    let textBoxID = try #require(workspace.textBoxes(page: 0).first?.id)
    let item = try #require(workspace.contentItems(page: 0).first { $0.kind == .text })
    #expect(item.text == "Original text" && item.restriction == nil)
    try workspace.replaceContentText(item, with: "Edited text", font: .helvetica)
    #expect(workspace.document?.page(at: 0)?.string?.contains("Edited text") == true)
    #expect(workspace.document?.string?.contains("Original text") == false)
    #expect(workspace.document?.page(at: 1)?.string?.contains("Second page") == true)
    #expect(workspace.document?.page(at: 0)?.annotations.first?.contents == "Preserve annotation")
    #expect(workspace.textBoxes(page: 0).first?.id == textBoxID)
    #expect(workspace.textBoxes(page: 0).first?.text.string == "Editable box")
    try workspace.undo()
    #expect(workspace.document?.string?.contains("Original text") == true)
    try workspace.redo()
    try workspace.saveCopy(to: fixture.output)
    let reopened = try #require(PDFDocument(url: fixture.output))
    #expect(reopened.string?.contains("Edited text") == true)
    #expect(reopened.string?.contains("Original text") == false)
    #expect(reopened.page(at: 0)?.annotations.first?.contents == "Preserve annotation")
    #expect(try Data(contentsOf: fixture.source) == original)
    try fixture.evidence(workspace, name: "content-text")
  }

  @Test func originalFontReusesExistingGlyphsAndRejectsMissingOnes() throws {
    let fixture = try ContentFixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let item = try #require(workspace.contentItems(page: 0).first { $0.kind == .text })
    let revision = workspace.revision
    #expect(throws: (any Error).self) { try workspace.replaceContentText(item, with: "新文字") }
    #expect(workspace.revision == revision && !workspace.isDirty && !workspace.canUndo)
    try workspace.replaceContentText(item, with: "text Original")
    #expect(workspace.document?.string?.contains("text Original") == true)
    try workspace.undo()
    #expect(!workspace.isDirty)
  }

  @Test func sharedImageReplacementOnlyChangesSelectedOccurrence() throws {
    let fixture = try ContentFixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let images = try workspace.contentItems(page: 0).filter { $0.kind == .image }
    #expect(images.count == 2)
    let target = try #require(images.first)
    try workspace.replaceContentImage(target, with: ContentFixture.blueImage())
    let changed = try #require(workspace.document)
    #expect(try ContentFixture.colorCounts(changed, page: 0).blue > 5000)
    #expect(try ContentFixture.colorCounts(changed, page: 0).red > 5000)
    #expect(try ContentFixture.colorCounts(changed, page: 1).blue == 0)
    #expect(try ContentFixture.colorCounts(changed, page: 1).red > 5000)
    let after = try workspace.contentItems(page: 0).filter { $0.kind == .image }
    #expect(after.count == 2 && after[0].bounds == target.bounds)
    try workspace.undo()
    #expect(try ContentFixture.colorCounts(#require(workspace.document), page: 0).blue == 0)
    try workspace.redo()
    try workspace.saveCopy(to: fixture.output)
    let reopened = try #require(PDFDocument(url: fixture.output))
    #expect(try ContentFixture.colorCounts(reopened, page: 0).blue > 5000)
    try fixture.evidence(workspace, name: "content-image")
  }

  @Test func deleteContentRemovesObjectsWithoutDeletingSharedImageElsewhere() throws {
    let fixture = try ContentFixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let image = try #require(workspace.contentItems(page: 0).first { $0.kind == .image })
    try workspace.removeContent(image)
    #expect(try workspace.contentItems(page: 0).filter { $0.kind == .image }.count == 1)
    #expect(try workspace.contentItems(page: 1).filter { $0.kind == .image }.count == 1)
    let text = try #require(workspace.contentItems(page: 0).first { $0.kind == .text })
    try workspace.removeContent(text)
    #expect(workspace.document?.string?.contains("Original text") == false)
    try workspace.undo()
    try workspace.undo()
    #expect(!workspace.isDirty)
    #expect(try workspace.contentItems(page: 0).filter { $0.kind == .image }.count == 2)
    try workspace.redo()
    try workspace.redo()
    try fixture.evidence(workspace, name: "content-delete")
  }

  @Test func staleSelectionAndUnsupportedTextLeaveWorkspaceUntouched() throws {
    let fixture = try ContentFixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let item = try #require(workspace.contentItems(page: 0).first { $0.kind == .text })
    for invalid in ["", "first\nsecond", "繁中", String(repeating: "W", count: 500)] {
      #expect(throws: (any Error).self) {
        try workspace.replaceContentText(item, with: invalid, font: .helvetica)
      }
    }
    #expect(!workspace.isDirty && !workspace.canUndo)
    try workspace.rotate([0])
    let document = try #require(workspace.document)
    let revision = workspace.revision
    #expect(throws: (any Error).self) { try workspace.removeContent(item) }
    #expect(workspace.document === document && workspace.revision == revision)
  }

  @Test func rotatedCroppedPageRetainsRawObjectCoordinates() throws {
    let fixture = try ContentFixture(cropped: true)
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    try workspace.rotate([0])
    let image = try #require(workspace.contentItems(page: 0).first { $0.kind == .image })
    #expect(image.bounds == CGRect(x: 50, y: 400, width: 120, height: 60))
    try workspace.replaceContentImage(image, with: ContentFixture.blueImage())
    #expect(workspace.document?.page(at: 0)?.rotation == 90)
    #expect(
      workspace.document?.page(at: 0)?.bounds(for: .cropBox)
        == CGRect(x: 20, y: 30, width: 555, height: 782))
    try fixture.evidence(workspace, name: "content-rotated")
  }

  @Test func clippingAndFormsAreVisibleButRejected() throws {
    let fixture = try ContentFixture(complex: true)
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let items = try workspace.contentItems(page: 0)
    let form = try #require(items.first { $0.kind == .form })
    let clipped = try #require(items.first { $0.kind == .text })
    #expect(form.restriction != nil && clipped.restriction != nil)
    #expect(throws: (any Error).self) { try workspace.removeContent(clipped) }
    #expect(throws: (any Error).self) { try workspace.removeContent(form) }
    #expect(!workspace.isDirty && !workspace.canUndo)
  }

  @Test func iccBackgroundAndPathColorsSurviveContentRegeneration() throws {
    let fixture = try ContentFixture()
    defer { fixture.clean() }
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let context = try #require(CGContext(fixture.source as CFURL, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSColor.white.setFill()
    box.fill()
    NSColor(calibratedRed: 0.06, green: 0.42, blue: 0.38, alpha: 1).setFill()
    CGRect(x: 50, y: 500, width: 150, height: 40).fill()
    ("Original text" as NSString).draw(
      at: CGPoint(x: 50, y: 700),
      withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black])
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let before = try #require(workspace.document)
    let green = try ContentFixture.sample(before, x: 75, y: 520)
    let text = try #require(workspace.contentItems(page: 0).first { $0.kind == .text })
    try workspace.replaceContentText(text, with: "Edited text", font: .helvetica)
    let after = try #require(workspace.document)
    let white = try ContentFixture.sample(after, x: 20, y: 800)
    let newGreen = try ContentFixture.sample(after, x: 75, y: 520)
    #expect(white.redComponent > 0.98 && white.greenComponent > 0.98 && white.blueComponent > 0.98)
    #expect(abs(green.greenComponent - newGreen.greenComponent) < 0.05)
    #expect(abs(green.blueComponent - newGreen.blueComponent) < 0.05)
    #expect(newGreen.greenComponent > newGreen.redComponent * 2)
    try fixture.evidence(workspace, name: "content-icc")
  }

  @Test func asymmetricImageRetainsOrientationAndTransparentPixels() throws {
    let fixture = try ContentFixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let target = try #require(workspace.contentItems(page: 0).first { $0.kind == .image })
    let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { _ in
      NSColor.blue.setFill()
      CGRect(x: 0, y: 10, width: 20, height: 10).fill()
      NSColor.green.setFill()
      CGRect(x: 0, y: 0, width: 20, height: 10).fill()
      return true
    }
    try workspace.replaceContentImage(target, with: image)
    let document = try #require(workspace.document)
    let top = try ContentFixture.sample(document, x: 65, y: 450)
    let bottom = try ContentFixture.sample(document, x: 65, y: 410)
    let transparent = try ContentFixture.sample(document, x: 150, y: 430)
    #expect(top.blueComponent > 0.8 && top.redComponent < 0.2)
    #expect(
      bottom.greenComponent > 0.8 && bottom.greenComponent > bottom.blueComponent + 0.3
        && bottom.greenComponent > bottom.redComponent + 0.3)
    #expect(transparent.redComponent > 0.98 && transparent.blueComponent > 0.98)
    try fixture.evidence(workspace, name: "content-alpha")
  }

  @Test(arguments: [true, false])
  func shadingAndPatternPagesRejectRegeneration(shading: Bool) throws {
    let fixture = try ContentFixture(shading: shading, pattern: !shading)
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let text = try #require(workspace.contentItems(page: 0).first { $0.kind == .text })
    #expect(text.restriction != nil)
    let revision = workspace.revision
    #expect(throws: (any Error).self) {
      try workspace.replaceContentText(text, with: "Edited text", font: .helvetica)
    }
    #expect(workspace.revision == revision && !workspace.isDirty && !workspace.canUndo)
  }

  @Test func unrelatedTrackingChangesRejectCandidateBeforeWorkspaceMutation() throws {
    let fixture = try ContentFixture()
    defer { fixture.clean() }
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let context = try #require(CGContext(fixture.source as CFURL, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let font = try #require(NSFont(name: "Helvetica", size: 24))
    ("Original text" as NSString).draw(
      at: CGPoint(x: 50, y: 700),
      withAttributes: [.font: font, .foregroundColor: NSColor.black, .kern: 0])
    ("Unselected text" as NSString).draw(
      at: CGPoint(x: 50, y: 500),
      withAttributes: [.font: font, .foregroundColor: NSColor.black, .kern: 6])
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let document = try #require(workspace.document)
    let item = try #require(workspace.contentItems(page: 0).first { $0.text.contains("Original") })
    let revision = workspace.revision
    #expect(throws: (any Error).self) {
      try workspace.replaceContentText(item, with: "Edited text", font: .helvetica)
    }
    #expect(workspace.document === document && workspace.revision == revision)
    #expect(!workspace.isDirty && !workspace.canUndo)
  }
}

@MainActor
private struct ContentFixture {
  let folder: URL
  var source: URL { folder.appendingPathComponent("original.pdf") }
  var output: URL { folder.appendingPathComponent("output.pdf") }

  init(cropped: Bool = false, complex: Bool = false, shading: Bool = false, pattern: Bool = false)
    throws
  {
    folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(".build/test-fixtures/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let crop = cropped ? " /CropBox [20 30 575 812]" : ""
    let clip = complex ? "q 50 700 30 30 re W n " : ""
    let unclip = complex ? " Q q /Fm1 Do Q" : ""
    let extraResource =
      shading ? "/Shading << /Sh1 10 0 R >>" : pattern ? "/Pattern << /P1 10 0 R >>" : ""
    let extraPaint = shading ? " /Sh1 sh" : ""
    let first =
      "\(clip)BT /F1 24 Tf 1 0 0 1 50 700 Tm (Original text) Tj ET\(unclip) q 120 0 0 60 50 400 cm /Im1 Do Q q 120 0 0 60 220 400 cm /Im1 Do Q\(extraPaint)"
    let second =
      "BT /F1 24 Tf 1 0 0 1 50 700 Tm (Second page) Tj ET q 120 0 0 60 50 400 cm /Im1 Do Q"
    var objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842]\(crop) /Resources << \(extraResource) /Font << /F1 5 0 R >> /XObject << /Im1 6 0 R /Fm1 9 0 R >> >> /Contents 7 0 R >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> /XObject << /Im1 6 0 R >> >> /Contents 8 0 R >>",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      Self.stream(
        "FF0000FF0000FF0000FF0000>",
        dictionary:
          "/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode"
      ),
      Self.stream(first), Self.stream(second),
      Self.stream(
        "0 1 0 rg 20 20 20 20 re f",
        dictionary: "/Type /XObject /Subtype /Form /BBox [0 0 50 50] /Resources << >>"),
    ]
    if shading {
      objects.append(
        "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 200 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0 0 1] /C1 [1 0 0] /N 1 >> /Extend [true true] >>"
      )
    } else if pattern {
      objects.append(
        Self.stream(
          "0 0 1 rg 0 0 5 5 re f",
          dictionary:
            "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << >>"
        ))
    }
    var data = Data("%PDF-1.7\n".utf8)
    var offsets = [0]
    for (index, object) in objects.enumerated() {
      offsets.append(data.count)
      data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = data.count
    data.append(Data("xref\n0 \(offsets.count)\n0000000000 65535 f \n".utf8))
    for offset in offsets.dropFirst() {
      data.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    data.append(
      Data("trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    try data.write(to: source)
  }

  private static func stream(_ value: String, dictionary: String = "") -> String {
    "<< \(dictionary) /Length \(value.utf8.count) >>\nstream\n\(value)\nendstream"
  }

  static func blueImage() -> NSImage {
    NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
      NSColor.blue.setFill()
      rect.fill()
      return true
    }
  }

  static func colorCounts(_ document: PDFDocument, page: Int) throws -> (red: Int, blue: Int) {
    let image = try #require(
      document.page(at: page)?.thumbnail(of: NSSize(width: 595, height: 842), for: .mediaBox))
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    var red = 0
    var blue = 0
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if color.redComponent > 0.7 && color.redComponent > color.blueComponent * 2
          && color.redComponent > color.greenComponent * 2
        {
          red += 1
        }
        if color.blueComponent > 0.7 && color.blueComponent > color.redComponent * 2
          && color.blueComponent > color.greenComponent * 2
        {
          blue += 1
        }
      }
    }
    return (red, blue)
  }

  static func sample(_ document: PDFDocument, x: Int, y: Int) throws -> NSColor {
    let image = try #require(
      document.page(at: 0)?.thumbnail(of: NSSize(width: 595, height: 842), for: .mediaBox))
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    return try #require(bitmap.colorAt(x: x, y: 841 - y)?.usingColorSpace(.sRGB))
  }

  func evidence(_ workspace: PDFWorkspace, name: String) throws {
    let root = folder.deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("test-evidence")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try workspace.saveCopy(to: root.appendingPathComponent("\(name).pdf"))
    try Data(contentsOf: source).write(to: root.appendingPathComponent("content-source.pdf"))
  }

  func clean() { try? FileManager.default.removeItem(at: folder) }
}
