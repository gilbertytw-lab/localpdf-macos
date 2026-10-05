import AppKit
import LocalPDFCore
import PDFKit
import Testing

@Suite("PDF editing and original preservation")
@MainActor
struct PDFWorkspaceTests {
  @Test func rotateUndoRedoRoundTrip() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let original = try Data(contentsOf: fixture.source)
    try workspace.rotate([0, 2])
    #expect(workspace.document?.page(at: 0)?.rotation == 90)
    #expect(workspace.document?.page(at: 1)?.rotation == 0)
    #expect(workspace.isDirty)
    try workspace.undo()
    #expect(workspace.document?.page(at: 0)?.rotation == 0)
    #expect(!workspace.isDirty)
    try workspace.redo()
    #expect(workspace.document?.page(at: 2)?.rotation == 90)
    try workspace.saveCopy(to: fixture.output)
    let reopened = try #require(PDFDocument(url: fixture.output))
    #expect(reopened.page(at: 0)?.rotation == 90)
    #expect(reopened.pageCount == 3)
    #expect(reopened.string?.contains("PAGE-B") == true)
    #expect(try Data(contentsOf: fixture.source) == original)
    #expect(!workspace.isDirty && !workspace.canUndo)
  }

  @Test func pageSequenceSurvivesMoveDeleteMergeAndExtract() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    try workspace.movePage(at: 2, to: 0)
    #expect(workspace.document?.page(at: 0)?.string?.contains("PAGE-C") == true)
    try workspace.delete([1])
    #expect(workspace.pageCount == 2)
    try workspace.append(fixture.source)
    #expect(workspace.pageCount == 5)
    try workspace.extract([4, 0, 4], to: fixture.output)
    let extracted = try #require(PDFDocument(url: fixture.output))
    #expect(extracted.pageCount == 2)
    #expect(extracted.page(at: 0)?.string?.contains("PAGE-C") == true)
    #expect(extracted.page(at: 1)?.string?.contains("PAGE-C") == true)
    #expect(workspace.pageCount == 5 && workspace.isDirty)
    #expect(PDFDocument(url: fixture.source)?.pageCount == 3)
  }

  @Test func selectedPagesMoveTogetherAndUndoAsOneEdit() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let original = try Data(contentsOf: fixture.source)
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    try workspace.movePages([2, 0], before: 3)
    #expect(workspace.document?.page(at: 0)?.string?.contains("PAGE-B") == true)
    #expect(workspace.document?.page(at: 1)?.string?.contains("PAGE-A") == true)
    #expect(workspace.document?.page(at: 2)?.string?.contains("PAGE-C") == true)
    try workspace.undo()
    #expect(workspace.document?.page(at: 0)?.string?.contains("PAGE-A") == true)
    #expect(!workspace.isDirty)
    try workspace.redo()
    #expect(workspace.document?.page(at: 0)?.string?.contains("PAGE-B") == true)
    let revision = workspace.revision
    try workspace.movePages([1, 2], before: 3)
    #expect(workspace.revision == revision)
    #expect(throws: PDFEditError.invalidSelection) {
      try workspace.movePages([0], before: 4)
    }
    try workspace.saveCopy(to: fixture.output)
    #expect(PDFDocument(url: fixture.output)?.page(at: 0)?.string?.contains("PAGE-B") == true)
    #expect(try Data(contentsOf: fixture.source) == original)
  }

  @Test func originalPathsAndAliasesAreRejected() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let original = try Data(contentsOf: fixture.source)
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    try workspace.rotate([0])
    #expect(throws: PDFEditError.originalPath) { try workspace.saveCopy(to: fixture.source) }
    let symlink = fixture.folder.appendingPathComponent("alias.pdf")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: fixture.source)
    #expect(throws: PDFEditError.originalPath) { try workspace.saveCopy(to: symlink) }
    let hardlink = fixture.folder.appendingPathComponent("hardlink.pdf")
    try FileManager.default.linkItem(at: fixture.source, to: hardlink)
    #expect(throws: PDFEditError.originalPath) { try workspace.extract([0], to: hardlink) }
    #expect(try Data(contentsOf: fixture.source) == original)
    #expect(workspace.isDirty && workspace.canUndo)
  }

  @Test func mergedSourceRemainsProtectedAfterUndo() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let merge = fixture.folder.appendingPathComponent("merge.pdf")
    try FileManager.default.copyItem(at: fixture.source, to: merge)
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    try workspace.append(merge)
    try workspace.undo()
    #expect(throws: PDFEditError.originalPath) { try workspace.saveCopy(to: merge) }
    #expect(workspace.pageCount == 3)
  }

  @Test func textNotesAndHighlightsPersist() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    try workspace.addText("繁體中文測試", page: 0, at: CGPoint(x: 50, y: 200))
    try workspace.addNote("Review this", page: 0, at: CGPoint(x: 500, y: 200))
    let selection = try #require(workspace.document?.findString("PAGE-A", withOptions: []).first)
    try workspace.highlight(selection)
    try workspace.saveCopy(to: fixture.output)
    let reopened = try #require(PDFDocument(url: fixture.output))
    let page = try #require(reopened.page(at: 0))
    #expect(page.annotations.contains { $0.type == "FreeText" && $0.contents == "繁體中文測試" })
    #expect(page.annotations.contains { $0.type == "Text" && $0.contents == "Review this" })
    #expect(page.annotations.contains { $0.type == "Highlight" })
    #expect(page.string?.contains("PAGE-A") == true)
  }

  @Test func imageAppearancePersistsAfterUndoAndSave() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let image = NSImage(size: CGSize(width: 100, height: 50))
    image.lockFocus()
    NSColor.red.setFill()
    CGRect(x: 0, y: 0, width: 100, height: 50).fill()
    image.unlockFocus()
    try workspace.addImage(image, page: 0, at: CGPoint(x: 100, y: 300))
    try workspace.addNote("Next edit", page: 0, at: CGPoint(x: 400, y: 300))
    try workspace.undo()
    try workspace.saveCopy(to: fixture.output)
    let evidence = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(".build/test-evidence")
    try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
    try Data(contentsOf: fixture.output).write(
      to: evidence.appendingPathComponent("image-roundtrip.pdf"))
    let reopened = try #require(PDFDocument(url: fixture.output))
    let page = try #require(reopened.page(at: 0))
    #expect(page.annotations.contains { $0.type == "Stamp" && $0.hasAppearanceStream })
    let rendered = page.thumbnail(of: CGSize(width: 595, height: 842), for: .cropBox)
    let bitmap = try #require(rendered.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    try bitmap.representation(using: .png, properties: [:])?.write(
      to: evidence.appendingPathComponent("image-native.png"))
    var redPixels = 0
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if color.redComponent > 0.7 && color.redComponent > 2 * color.greenComponent
          && color.redComponent > 2 * color.blueComponent
        {
          redPixels += 1
        }
      }
    }
    #expect(redPixels > 1000)
  }

  @Test func invalidEditsLeaveStateIntact() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    #expect(throws: PDFEditError.lastPage) { try workspace.delete([0, 1, 2]) }
    #expect(throws: PDFEditError.invalidSelection) { try workspace.rotate([-1]) }
    #expect(throws: PDFEditError.invalidSelection) { try workspace.extract([], to: fixture.output) }
    #expect(throws: PDFEditError.emptyText) { try workspace.addText("  ", page: 0, at: .zero) }
    #expect(throws: PDFEditError.invalidPosition) {
      try workspace.addNote("Outside", page: 0, at: CGPoint(x: -10, y: -10))
    }
    #expect(workspace.pageCount == 3 && !workspace.isDirty && !workspace.canUndo)
  }

  @Test func failedOpenAndSavePreserveWorkingEdits() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    try workspace.rotate([0])
    let invalid = fixture.folder.appendingPathComponent("invalid.pdf")
    try Data("invalid PDF".utf8).write(to: invalid)
    #expect(throws: PDFEditError.invalidDocument) { try workspace.open(invalid) }
    let impossible = fixture.folder.appendingPathComponent("missing-directory/output.pdf")
    #expect(throws: (any Error).self) { try workspace.saveCopy(to: impossible) }
    #expect(workspace.document?.page(at: 0)?.rotation == 90)
    #expect(workspace.isDirty && workspace.canUndo && workspace.sourceURL == fixture.source)
  }

  @Test func encryptedInputIsRejectedBeforeReplacingDocument() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let candidate = try #require(PDFDocument(url: fixture.source))
    let encrypted = fixture.folder.appendingPathComponent("encrypted.pdf")
    let data = try #require(
      candidate.dataRepresentation(options: [
        PDFDocumentWriteOption.userPasswordOption: "secret",
        PDFDocumentWriteOption.ownerPasswordOption: "owner",
      ]))
    try data.write(to: encrypted)
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    #expect(throws: PDFEditError.encrypted) { try workspace.open(encrypted) }
    #expect(workspace.sourceURL == fixture.source && workspace.pageCount == 3)
  }

  @Test func widgetDocumentsCanBeReadButNotEdited() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let document = try #require(PDFDocument(url: fixture.source))
    let widget = PDFAnnotation(
      bounds: CGRect(x: 50, y: 200, width: 150, height: 30), forType: .widget, withProperties: nil)
    widget.widgetFieldType = .text
    widget.fieldName = "Name"
    document.page(at: 0)?.addAnnotation(widget)
    let input = fixture.folder.appendingPathComponent("form.pdf")
    #expect(document.write(to: input))
    let workspace = PDFWorkspace()
    try workspace.open(input)
    #expect(workspace.editingRestriction != nil)
    #expect(throws: PDFEditError.unsupportedWidgets) { try workspace.rotate([0]) }
    #expect(throws: PDFEditError.unsupportedWidgets) { try workspace.saveCopy(to: fixture.output) }
  }

  @Test func newEditInvalidatesRedoAndHistoryIsBounded() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    try workspace.rotate([0])
    try workspace.undo()
    #expect(workspace.canRedo)
    try workspace.rotate([1])
    #expect(!workspace.canRedo)
    for _ in 0..<30 { try workspace.rotate([0]) }
    var count = 0
    while workspace.canUndo {
      try workspace.undo()
      count += 1
    }
    #expect(count == 24)
  }

  @Test func annotationsCanBeRemovedAndRecovered() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    try workspace.addText("Test annotation", page: 0, at: CGPoint(x: 50, y: 200))
    let annotation = try #require(workspace.document?.page(at: 0)?.annotations.last)
    try workspace.removeAnnotation(annotation, page: 0)
    #expect(workspace.document?.page(at: 0)?.annotations.isEmpty == true)
    try workspace.undo()
    #expect(workspace.document?.page(at: 0)?.annotations.last?.contents == "Test annotation")
  }

  @Test func oversizedSnapshotIsRejectedBeforeEditing() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace(historyByteLimit: 1)
    try workspace.open(fixture.source)
    #expect(throws: PDFEditError.undoLimit) { try workspace.rotate([0]) }
    #expect(workspace.document?.page(at: 0)?.rotation == 0)
    #expect(!workspace.isDirty && !workspace.canUndo)
  }

  @Test func editThatExceedsSnapshotLimitRollsBack() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let baseline = try #require(PDFDocument(url: fixture.source)?.dataRepresentation()).count
    let workspace = PDFWorkspace(historyByteLimit: baseline + 2048)
    try workspace.open(fixture.source)
    let text = (0..<500).map { _ in UUID().uuidString }.joined()
    #expect(throws: PDFEditError.undoLimit) {
      try workspace.addNote(text, page: 0, at: CGPoint(x: 50, y: 200))
    }
    #expect(workspace.document?.page(at: 0)?.annotations.isEmpty == true)
    #expect(!workspace.isDirty && !workspace.canUndo)
  }

  @Test func nativePresentationCannotChangeWorkspaceOrExportFlags() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    try workspace.addNote("Keep this", page: 0, at: CGPoint(x: 50, y: 200))
    let display = try workspace.displayCopy()
    let annotation = try #require(display.page(at: 0)?.annotations.first)
    #expect(((annotation.value(forAnnotationKey: .flags) as? NSNumber)?.intValue ?? 0) & 64 == 64)
    annotation.contents = "Native editor changed the presentation"
    display.removePage(at: 2)
    #expect(workspace.pageCount == 3)
    #expect(workspace.document?.page(at: 0)?.annotations.first?.contents == "Keep this")
    try workspace.saveCopy(to: fixture.output)
    let exported = try #require(PDFDocument(url: fixture.output))
    let saved = try #require(exported.page(at: 0)?.annotations.first)
    #expect(((saved.value(forAnnotationKey: .flags) as? NSNumber)?.intValue ?? 0) & 64 == 0)
    #expect(saved.contents == "Keep this")
  }

  @Test func commentsOnLaterPagesRoundTripAndUndo() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let original = try Data(contentsOf: fixture.source)
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    #expect(throws: PDFEditError.emptyText) {
      try workspace.createComment("  ", page: 2, at: CGPoint(x: 200, y: 400))
    }
    #expect(!workspace.isDirty)
    let created = try workspace.createComment(
      "第三頁待確認", page: 2,
      at: CGPoint(x: 200, y: 400))
    #expect(workspace.comments(page: 0).isEmpty)
    #expect(workspace.comments(page: 2).first?.id == created.id)
    #expect(workspace.comments(page: 2).first?.bounds.minX == 200)
    _ = try workspace.replyToComment(created.id, page: 2, text: "已確認")
    let replyID = try #require(workspace.comments(page: 2).first?.replies.first?.id)
    _ = try workspace.editCommentReply(created.id, page: 2, replyID: replyID, text: "已確認，謝謝")
    _ = try workspace.setCommentResolved(created.id, page: 2, resolved: true)
    #expect(workspace.comments(page: 2).first?.resolved == true)
    #expect(workspace.comments(page: 2).first?.replies.first?.text == "已確認，謝謝")
    try workspace.undo()
    #expect(workspace.comments(page: 2).first?.resolved == false)
    try workspace.redo()
    #expect(workspace.comments(page: 2).first?.resolved == true)
    try workspace.saveCopy(to: fixture.output)
    let reopened = PDFWorkspace()
    try reopened.open(fixture.output)
    let roundTrip = try #require(reopened.comments(page: 2).first)
    #expect(roundTrip.id == created.id)
    #expect(roundTrip.text == "第三頁待確認")
    #expect(roundTrip.replies.first?.text == "已確認，謝謝")
    #expect(roundTrip.resolved)
    #expect(reopened.document?.page(at: 2)?.annotations.first?.contents == "第三頁待確認")
    #expect(try Data(contentsOf: fixture.source) == original)
    _ = try reopened.editComment(roundTrip.id, page: 2, text: "修改後")
    #expect(reopened.comments(page: 2).first?.text == "修改後")
    _ = try reopened.deleteCommentReply(roundTrip.id, page: 2, replyID: replyID)
    #expect(reopened.comments(page: 2).first?.replies.isEmpty == true)
    try reopened.undo()
    #expect(reopened.comments(page: 2).first?.replies.count == 1)
    try reopened.deleteComment(roundTrip.id, page: 2)
    #expect(reopened.comments(page: 2).isEmpty)
    try reopened.undo()
    #expect(reopened.comments(page: 2).first?.text == "修改後")
  }

  @Test func legacyTextNotesCanBeUpgradedIntoThreads() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    try workspace.addNote("原有便條", page: 1, at: CGPoint(x: 120, y: 500))
    let legacy = try #require(workspace.comments(page: 1).first)
    #expect(legacy.id.hasPrefix("legacy:1:"))
    let id = try workspace.replyToComment(legacy.id, page: 1, text: "新回覆")
    #expect(id != legacy.id)
    #expect(workspace.comments(page: 1).first?.replies.first?.text == "新回覆")
    try workspace.saveCopy(to: fixture.output)
    let reopened = PDFWorkspace()
    try reopened.open(fixture.output)
    #expect(reopened.comments(page: 1).first?.id == id)
  }

  @Test func selectedTextCommentsPersistAsRedHighlightsOnTheirPage() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let original = try Data(contentsOf: fixture.source)
    let workspace = PDFWorkspace()
    try workspace.open(fixture.source)
    let first = CGRect(x: 50, y: 685, width: 98, height: 23)
    let second = CGRect(x: 50, y: 655, width: 110, height: 23)
    #expect(throws: PDFEditError.invalidSelection) {
      try workspace.createAnchoredComment("錯誤", page: 2, rects: [])
    }
    #expect(!workspace.isDirty)
    let comment = try workspace.createAnchoredComment(
      "這兩行需要修改", page: 2, rects: [first, second])
    #expect(comment.isTextAnchor)
    #expect(comment.anchorRects == [first, second])
    #expect(workspace.comments(page: 0).isEmpty)
    let annotation = try #require(workspace.document?.page(at: 2)?.annotations.first)
    #expect(annotation.type == "Highlight")
    #expect(annotation.contents == "這兩行需要修改")
    #expect(annotation.quadrilateralPoints?.count == 8)
    #expect(annotation.color.redComponent > 0.8)
    try workspace.undo()
    #expect(workspace.comments(page: 2).isEmpty)
    try workspace.redo()
    #expect(workspace.comments(page: 2).first?.id == comment.id)
    try workspace.saveCopy(to: fixture.output)
    let reopened = PDFWorkspace()
    try reopened.open(fixture.output)
    let saved = try #require(reopened.comments(page: 2).first)
    #expect(saved.isTextAnchor)
    #expect(saved.anchorRects == [first, second])
    #expect(saved.text == "這兩行需要修改")
    _ = try reopened.editComment(saved.id, page: 2, text: "修改後")
    #expect(reopened.comments(page: 2).first?.isTextAnchor == true)
    #expect(try Data(contentsOf: fixture.source) == original)
  }

  @Test func earlierThreadMetadataWithoutTextAnchorStillLoads() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let document = try #require(PDFDocument(url: fixture.source))
    let page = try #require(document.page(at: 1))
    let note = PDFAnnotation(
      bounds: CGRect(x: 80, y: 400, width: 24, height: 24), forType: .text,
      withProperties: nil)
    note.contents = "舊版註解"
    note.setValue(
      """
      {"version":1,"id":"earlier-thread","createdAt":0,"replies":[],"resolved":false}
      """,
      forAnnotationKey: PDFAnnotationKey(rawValue: "/LocalPDFCommentThread"))
    page.addAnnotation(note)
    guard document.write(to: fixture.output) else { throw PDFEditError.serialization }
    let workspace = PDFWorkspace()
    try workspace.open(fixture.output)
    let loaded = try #require(workspace.comments(page: 1).first)
    #expect(loaded.id == "earlier-thread")
    #expect(loaded.text == "舊版註解")
    #expect(!loaded.isTextAnchor)
    _ = try workspace.editComment(loaded.id, page: 1, text: "保留編輯能力")
    #expect(workspace.comments(page: 1).first?.text == "保留編輯能力")
  }
}

@MainActor
private struct Fixture {
  let folder: URL
  var source: URL { folder.appendingPathComponent("original.pdf") }
  var output: URL { folder.appendingPathComponent("output.pdf") }

  init() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    folder = root.appendingPathComponent(
      ".build/test-fixtures/\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let context = try #require(CGContext(source as CFURL, mediaBox: &box, nil))
    for label in ["PAGE-A", "PAGE-B", "PAGE-C"] {
      context.beginPDFPage(nil)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
      (label as NSString).draw(
        at: CGPoint(x: 50, y: 700),
        withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black])
      NSGraphicsContext.restoreGraphicsState()
      context.endPDFPage()
    }
    context.closePDF()
  }

  func clean() { try? FileManager.default.removeItem(at: folder) }
}
