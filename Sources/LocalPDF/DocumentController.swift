import AppKit
import Darwin
import LocalPDFCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum EditorTool: String, CaseIterable, Identifiable {
  case select = "閱讀與選取"
  case text = "新增文字"
  case note = "新增註解"
  case image = "新增圖片"
  case content = "編輯原有內容"

  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .select: "cursorarrow"
    case .text: "textformat"
    case .note: "text.bubble"
    case .image: "photo"
    case .content: "square.and.pencil"
    }
  }
}

@MainActor
final class DocumentController: NSObject, ObservableObject, NSWindowDelegate {
  let workspace = PDFWorkspace()
  @Published var pageManagerOpen = false
  @Published var selectedPages: Set<Int> = [0]
  @Published var currentPage = 0 {
    didSet {
      guard currentPage != oldValue, tool == .content, !revertingPageChange else { return }
      do {
        try finishContentEditing()
        loadContent()
      } catch {
        self.error = error.localizedDescription
        revertingPageChange = true
        currentPage = oldValue
        revertingPageChange = false
      }
    }
  }
  @Published var tool = EditorTool.select {
    didSet {
      if changingTool { return }
      if tool != oldValue {
        if oldValue == .note, hasUnpostedCommentChanges {
          changingTool = true
          tool = oldValue
          changingTool = false
          error = "請先確認或取消目前的註解草稿。"
          return
        }
        do {
          try finishContentEditing()
          try finishTextEditing()
        } catch {
          changingTool = true
          tool = oldValue
          changingTool = false
          self.error = error.localizedDescription
          return
        }
      }
      if tool == .content { loadContent() } else { selectedContent = nil }
    }
  }
  @Published var contentItems: [PDFContentItem] = []
  @Published var selectedContent: PDFContentItem?
  @Published var replacementFont = PDFContentFont.original
  @Published var hasContentDraft = false
  @Published var commentDraft = ""
  @Published var replyDraft = ""
  @Published var commentEditing = false
  @Published var editingReplyID: String?
  @Published var editingReplyDraft = ""
  @Published var selectedCommentID: String?
  @Published var selectedCommentPage: Int?
  @Published var pendingCommentRects: [CGRect] = []
  @Published var pendingCommentPage: Int?
  @Published var textFormat = TextBoxFormat()
  @Published var editingText = false
  @Published var hasTextDraft = false
  weak var textEditor: TextBoxEditor?
  weak var contentEditor: InlineContentEditor?
  private var changingTool = false
  private var revertingPageChange = false
  @Published var pendingImage: NSImage?
  @Published var imageName: String?
  @Published var searchText = ""
  @Published var searchResults: [PDFSelection] = []
  @Published var searchIndex = 0
  @Published var error: String?
  @Published var status = "所有文件處理都在這台 Mac 上完成"
  weak var pdfView: PDFView?
  weak var window: NSWindow?
  private var fixtureStarted = false

  func perform(allowCommentDraft: Bool = false, _ action: () throws -> Void) {
    do {
      if !allowCommentDraft, hasUnpostedCommentChanges {
        error = "請先確認或取消目前的註解草稿。"
        return
      }
      try finishContentEditing()
      try finishTextEditing()
      let previousRevision = workspace.revision
      try action()
      selectedPages = Set(selectedPages.filter { $0 < workspace.pageCount })
      currentPage = min(currentPage, max(0, workspace.pageCount - 1))
      if selectedPages.isEmpty, workspace.pageCount > 0 { selectedPages = [currentPage] }
      searchResults = []
      if workspace.revision != previousRevision {
        selectedContent = nil
        if tool == .content {
          let resultStatus = status
          loadContent()
          status = resultStatus
        }
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func openPanel() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.pdf]
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url, confirmDiscard() else { return }
    open(url)
  }

  func open(_ url: URL) {
    perform {
      try workspace.open(url)
      pageManagerOpen = false
      clearCommentSelection()
      selectedPages = [0]
      currentPage = 0
      tool = .select
      searchText = ""
      status = "已開啟 \(url.lastPathComponent) · 原檔保留"
    }
  }

  @discardableResult
  func savePanel(extract: Bool = false) -> Bool {
    guard workspace.document != nil else { return false }
    if hasUnpostedCommentChanges {
      error = "請先確認或取消註解草稿。"
      return false
    }
    do {
      try finishContentEditing()
      try finishTextEditing()
    } catch {
      self.error = error.localizedDescription
      return false
    }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pdf]
    let name = workspace.sourceURL?.deletingPathExtension().lastPathComponent ?? "文件"
    panel.nameFieldStringValue = "\(name)-\(extract ? "選取頁面" : "編輯副本").pdf"
    guard panel.runModal() == .OK, let url = panel.url else { return false }
    do {
      if extract {
        try workspace.extract(Array(selectedPages), to: url)
      } else {
        try workspace.saveCopy(to: url)
      }
      status = "已儲存 \(url.lastPathComponent)"
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }

  func mergePanel() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.pdf]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    perform {
      try workspace.append(url)
      status = "已合併 \(url.lastPathComponent)"
    }
  }

  func imagePanel() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .tiff]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let image = NSImage(contentsOf: url) else {
      error = "無法讀取這張圖片。"
      return
    }
    pendingImage = image
    imageName = url.lastPathComponent
    tool = .image
  }

  func confirmDiscard() -> Bool {
    guard
      workspace.isDirty || hasTextDraft || hasContentDraft || pendingCommentPage != nil
        || hasUnpostedCommentChanges
    else {
      cancelTextEditing()
      cancelContentEditing()
      return true
    }
    let alert = NSAlert()
    alert.messageText = "保留這次編輯嗎？"
    alert.informativeText = "工作文件有未儲存的變更。原始 PDF 保持不變。"
    alert.addButton(withTitle: "另存副本")
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: "放棄變更")
    switch alert.runModal() {
    case .alertFirstButtonReturn: return savePanel()
    case .alertThirdButtonReturn:
      cancelTextEditing()
      cancelContentEditing()
      clearCommentSelection()
      return true
    default: return false
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool { confirmDiscard() }

  func go(to index: Int) {
    guard (0..<workspace.pageCount).contains(index) else { return }
    do {
      try finishContentEditing()
      try finishTextEditing()
    } catch {
      self.error = error.localizedDescription
      return
    }
    currentPage = index
    if let page = pdfView?.document?.page(at: index) { pdfView?.go(to: page) }
  }

  func openPageManager() {
    guard workspace.document != nil else { return }
    guard !hasUnpostedCommentChanges else {
      error = "請先確認或取消目前的註解草稿。"
      return
    }
    do {
      try finishContentEditing()
      try finishTextEditing()
      selectedPages = [currentPage]
      pageManagerOpen = true
      status = "選取頁面後可批次操作，拖曳縮圖可調整順序"
    } catch { self.error = error.localizedDescription }
  }

  func closePageManager() {
    currentPage = selectedPages.min() ?? min(currentPage, max(0, workspace.pageCount - 1))
    pageManagerOpen = false
    status = "已返回文件編輯"
  }

  func rotateSelectedPages() {
    guard !selectedPages.isEmpty else { return }
    let count = selectedPages.count
    perform {
      try workspace.rotate(Array(selectedPages))
      status = "已旋轉 \(count) 頁 · 可以復原"
    }
  }

  func moveManagedPages(_ indices: [Int], onto target: Int) {
    let indices = Array(Set(indices)).sorted()
    guard !indices.isEmpty, !indices.contains(target),
      (0..<workspace.pageCount).contains(target)
    else { return }
    let destination = indices[0] < target ? target + 1 : target
    let insertion = destination - indices.filter { $0 < destination }.count
    let revision = workspace.revision
    perform {
      try workspace.movePages(indices, before: destination)
      status = "已移動 \(indices.count) 頁 · 可以復原"
    }
    guard workspace.revision != revision else { return }
    selectedPages = Set(insertion..<(insertion + indices.count))
    currentPage = insertion
  }

  func deleteSelectedPages() {
    guard !selectedPages.isEmpty else { return }
    guard selectedPages.count < workspace.pageCount else {
      error = PDFEditError.lastPage.localizedDescription
      return
    }
    let count = selectedPages.count
    let nextPage = selectedPages.min() ?? 0
    let alert = NSAlert()
    alert.messageText = "刪除選取的 \(count) 頁？"
    alert.informativeText = "可以使用復原還原頁面。"
    alert.addButton(withTitle: "刪除頁面")
    alert.addButton(withTitle: "取消")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let revision = workspace.revision
    perform { try workspace.delete(Array(selectedPages)) }
    guard workspace.revision != revision else { return }
    currentPage = min(nextPage, workspace.pageCount - 1)
    selectedPages = [currentPage]
    status = "已刪除 \(count) 頁 · 可以復原"
  }

  func place(on page: PDFPage, at point: CGPoint) {
    guard let document = pdfView?.document else { return }
    let index = document.index(for: page)
    if tool == .text {
      do {
        try finishTextEditing()
        currentPage = index
        let box = PDFTextBox(
          page: index, bounds: try workspace.textBoxBounds(page: index, at: point),
          text: NSAttributedString(string: ""))
        beginTextEditing(box, original: nil)
      } catch { self.error = error.localizedDescription }
      return
    }
    if tool == .content {
      currentPage = index
      selectContent(at: point)
      return
    }
    if tool == .note { return }
    perform {
      switch tool {
      case .select, .content, .text: return
      case .note: return
      case .image:
        guard let pendingImage else {
          error = "請先選擇圖片。"
          return
        }
        try workspace.addImage(pendingImage, page: index, at: point)
      }
      currentPage = index
      selectedPages = [index]
      status = "已新增內容 · 可以復原"
    }
  }

  var selectedComment: PDFComment? {
    guard let page = selectedCommentPage, let id = selectedCommentID else { return nil }
    return workspace.comments(page: page).first { $0.id == id }
  }

  var hasUnpostedCommentChanges: Bool {
    (pendingCommentPage != nil
      && !commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      || commentEditing || editingReplyID != nil
      || !replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func clearCommentSelection() {
    selectedCommentID = nil
    selectedCommentPage = nil
    pendingCommentRects = []
    pendingCommentPage = nil
    commentDraft = ""
    replyDraft = ""
    commentEditing = false
    editingReplyID = nil
    editingReplyDraft = ""
  }

  func beginCommentFromSelection() {
    if hasUnpostedCommentChanges {
      error = "請先確認或取消目前的註解草稿。"
      return
    }
    guard let view = pdfView, let displayed = view.document,
      let selection = view.currentSelection,
      let selectedText = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
      !selectedText.isEmpty
    else {
      error = "請先在 PDF 中選取要加註解的文字。"
      return
    }
    let lines = selection.selectionsByLine()
    let pageIndices = Set(lines.flatMap { $0.pages.map { displayed.index(for: $0) } })
    guard pageIndices.count == 1, let index = pageIndices.first,
      (0..<workspace.pageCount).contains(index), let page = displayed.page(at: index)
    else {
      error = "一次只能註解同一頁的文字。"
      return
    }
    let rects = lines.map { $0.bounds(for: page) }.filter { !$0.isEmpty }
    guard !rects.isEmpty else {
      error = "請選取可辨識的 PDF 文字。"
      return
    }
    clearCommentSelection()
    tool = .select
    currentPage = index
    selectedPages = [index]
    pendingCommentPage = index
    pendingCommentRects = rects
    view.clearSelection()
    (view as? InteractivePDFView)?.showCommentPresentation()
    status = "輸入註解後按 Enter 或點方塊外確認"
  }

  func selectComment(_ comment: PDFComment) {
    if hasUnpostedCommentChanges {
      error = "請先確認或取消目前的註解草稿。"
      return
    }
    clearCommentSelection()
    tool = comment.isTextAnchor ? .select : .note
    selectedCommentID = comment.id
    selectedCommentPage = comment.page
    selectedPages = [comment.page]
    go(to: comment.page)
    if let page = pdfView?.document?.page(at: comment.page) {
      pdfView?.go(to: comment.bounds.insetBy(dx: -24, dy: -24), on: page)
    }
    status = comment.resolved ? "已解決的註解" : "已選取註解"
  }

  func publishComment() {
    guard let page = pendingCommentPage, !pendingCommentRects.isEmpty else { return }
    let body = (pdfView as? InteractivePDFView)?.commentDraftText ?? commentDraft
    if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      clearCommentSelection()
      (pdfView as? InteractivePDFView)?.showCommentPresentation()
      status = "已取消空白註解"
      return
    }
    perform(allowCommentDraft: true) {
      let comment = try workspace.createAnchoredComment(
        body, page: page, rects: pendingCommentRects)
      clearCommentSelection()
      selectedCommentID = comment.id
      selectedCommentPage = page
      currentPage = page
      status = "註解已發布 · 可以復原"
    }
    if pendingCommentPage == nil { (pdfView as? InteractivePDFView)?.showCommentPresentation() }
  }

  func saveCommentEdit() {
    guard let comment = selectedComment else { return }
    perform(allowCommentDraft: true) {
      selectedCommentID = try workspace.editComment(
        comment.id, page: comment.page,
        text: commentDraft)
      commentDraft = ""
      commentEditing = false
      status = "註解已更新 · 可以復原"
    }
  }

  func replyToComment() {
    guard let comment = selectedComment else { return }
    perform(allowCommentDraft: true) {
      selectedCommentID = try workspace.replyToComment(
        comment.id, page: comment.page,
        text: replyDraft)
      replyDraft = ""
      status = "回覆已發布 · 可以復原"
    }
  }

  func saveReplyEdit() {
    guard let comment = selectedComment, let replyID = editingReplyID else { return }
    perform(allowCommentDraft: true) {
      selectedCommentID = try workspace.editCommentReply(
        comment.id, page: comment.page, replyID: replyID, text: editingReplyDraft)
      editingReplyID = nil
      editingReplyDraft = ""
      status = "回覆已更新 · 可以復原"
    }
  }

  func deleteReply(_ replyID: String) {
    guard let comment = selectedComment else { return }
    perform {
      selectedCommentID = try workspace.deleteCommentReply(
        comment.id, page: comment.page, replyID: replyID)
      editingReplyID = nil
      editingReplyDraft = ""
      status = "回覆已刪除 · 可以復原"
    }
  }

  func toggleCommentResolved() {
    guard let comment = selectedComment else { return }
    perform {
      selectedCommentID = try workspace.setCommentResolved(
        comment.id, page: comment.page,
        resolved: !comment.resolved)
      status = comment.resolved ? "註解已重新開啟" : "註解已標記為解決"
    }
  }

  func deleteSelectedComment() {
    guard let comment = selectedComment else { return }
    perform {
      try workspace.deleteComment(comment.id, page: comment.page)
      clearCommentSelection()
      status = "註解已刪除 · 可以復原"
    }
  }

  func editTextBox(id: String, page: Int) {
    do {
      try finishTextEditing()
      guard let box = workspace.textBoxes(page: page).first(where: { $0.id == id }) else { return }
      tool = .text
      currentPage = page
      beginTextEditing(box, original: box)
    } catch { self.error = error.localizedDescription }
  }

  private func beginTextEditing(_ box: PDFTextBox, original: PDFTextBox?) {
    guard let view = pdfView as? InteractivePDFView else { return }
    let editor = TextBoxEditor(box: box, original: original, controller: self)
    textEditor = editor
    editingText = true
    hasTextDraft = false
    if let page = view.document?.page(at: box.page) {
      view.go(to: box.bounds.insetBy(dx: -12, dy: -28), on: page)
    }
    view.installTextEditor(editor)
    status = "直接輸入文字；拖曳上方把手移動，右下角調整大小"
  }

  func textDraftChanged() {
    hasTextDraft = textEditor?.changed ?? false
  }

  func finishTextEditing() throws {
    guard let editor = textEditor else { return }
    // Finalize marked IME text before taking the attributed snapshot.
    editor.textView.unmarkText()
    let draft = editor.snapshot()
    if editor.changed {
      if draft.text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if workspace.textBoxes(page: draft.page).contains(where: { $0.id == draft.id }) {
          try workspace.removeTextBox(id: draft.id, page: draft.page)
        }
      } else {
        try workspace.saveTextBox(draft)
      }
    }
    cancelTextEditing()
    status = "文字框已完成 · 點選可再編輯 · 可以復原"
  }

  func completeTextEditing() {
    do { try finishTextEditing() } catch { self.error = error.localizedDescription }
  }

  func cancelTextEditing() {
    (pdfView as? InteractivePDFView)?.removeTextEditor()
    textEditor = nil
    editingText = false
    hasTextDraft = false
  }

  func deleteTextBox() {
    guard let box = textEditor?.snapshot() else { return }
    cancelTextEditing()
    if workspace.textBoxes(page: box.page).contains(where: { $0.id == box.id }) {
      perform { try workspace.removeTextBox(id: box.id, page: box.page) }
    }
  }

  func deleteAnnotation(_ annotation: PDFAnnotation, page: Int) {
    let textID =
      (annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/LocalPDFID")) as? String)
      .flatMap { $0.hasPrefix("LocalPDFText:") ? String($0.dropFirst("LocalPDFText:".count)) : nil }
    if let textID {
      if textEditor?.box.id == textID { cancelTextEditing() }
      perform { try workspace.removeTextBox(id: textID, page: page) }
    } else {
      perform { try workspace.removeAnnotation(annotation, page: page) }
    }
  }

  func applyTextFormat(_ field: TextFormatField, _ change: (inout TextBoxFormat) -> Void) {
    var format = textFormat
    change(&format)
    textFormat = format
    textEditor?.apply(field, format: format)
  }

  var canUndo: Bool {
    contentEditor?.textUndoManager?.canUndo == true
      || textEditor?.textView.undoManager?.canUndo == true || workspace.canUndo
  }
  var canRedo: Bool {
    contentEditor?.textUndoManager?.canRedo == true
      || textEditor?.textView.undoManager?.canRedo == true || workspace.canRedo
  }
  func undo() {
    if let undo = contentEditor?.textUndoManager, undo.canUndo {
      undo.undo()
      contentDraftChanged()
    } else if let undo = textEditor?.textView.undoManager, undo.canUndo {
      undo.undo()
      textDraftChanged()
    } else {
      let revision = workspace.revision
      perform { try workspace.undo() }
      if workspace.revision != revision { status = "已復原 · 可以重做" }
    }
  }
  func redo() {
    if let undo = contentEditor?.textUndoManager, undo.canRedo {
      undo.redo()
      contentDraftChanged()
    } else if let undo = textEditor?.textView.undoManager, undo.canRedo {
      undo.redo()
      textDraftChanged()
    } else {
      let revision = workspace.revision
      perform { try workspace.redo() }
      if workspace.revision != revision { status = "已重做 · 可以復原" }
    }
  }

  func loadContent() {
    selectedContent = nil
    contentItems = []
    guard workspace.document != nil else { return }
    do {
      contentItems = try workspace.contentItems(page: currentPage)
      status = "點選原有文字或圖片，或從右側清單選取"
    } catch {
      self.error = error.localizedDescription
    }
  }

  func selectContent(at point: CGPoint) {
    do { try finishContentEditing() } catch {
      self.error = error.localizedDescription
      return
    }
    // Later objects paint over earlier objects, so hit test in reverse order.
    guard
      let item = contentItems.reversed().first(where: {
        $0.bounds.insetBy(dx: -3, dy: -3).contains(point)
      })
    else {
      selectedContent = nil
      status = "這個位置沒有可辨識的文字或圖片物件"
      return
    }
    selectContent(item)
  }

  func selectContent(_ item: PDFContentItem) {
    do { try finishContentEditing() } catch {
      self.error = error.localizedDescription
      return
    }
    let item =
      contentItems.first(where: {
        $0.revision == workspace.revision && $0.object == item.object && $0.kind == item.kind
      })
      ?? item
    selectedContent = item
    replacementFont = .original
    if let page = pdfView?.document?.page(at: item.page) {
      pdfView?.go(to: item.bounds.insetBy(dx: -12, dy: -12), on: page)
    }
    status = item.restriction ?? "已選取原有\(item.kind == .text ? "文字" : "圖片")"
    if item.kind == .text, item.restriction == nil,
      let view = pdfView as? InteractivePDFView
    {
      let editor = InlineContentEditor(item: item, controller: self)
      contentEditor = editor
      view.installContentEditor(editor)
      status = "直接在頁面修改文字 · Enter 套用 · Esc 取消"
    }
  }

  func contentDraftChanged() { hasContentDraft = contentEditor?.changed ?? false }

  func finishContentEditing() throws {
    guard let editor = contentEditor else { return }
    if editor.changed {
      try workspace.replaceContentText(editor.item, with: editor.text, font: replacementFont)
    }
    let changed = editor.changed
    cancelContentEditing()
    loadContent()
    status = changed ? "已修改原有文字 · 可以復原" : "未修改原有文字"
  }

  func completeContentEditing() {
    do { try finishContentEditing() } catch { self.error = error.localizedDescription }
  }

  func cancelContentEditing() {
    (pdfView as? InteractivePDFView)?.removeContentEditor()
    contentEditor = nil
    hasContentDraft = false
    selectedContent = nil
    (pdfView as? InteractivePDFView)?.showContentSelection()
    status = "已取消原有文字修改"
  }

  func replaceContentImagePanel() {
    guard let selectedContent else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .tiff]
    guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else {
      return
    }
    perform {
      try workspace.replaceContentImage(selectedContent, with: image)
      status = "已替換原有圖片 · 可以復原"
    }
  }

  func deleteContent() {
    guard let selectedContent else { return }
    cancelContentEditing()
    perform {
      try workspace.removeContent(selectedContent)
      status = "已刪除選取內容 · 可以復原"
    }
  }

  func highlightSelection() {
    guard let selection = pdfView?.currentSelection, let document = workspace.document,
      let displayed = pdfView?.document
    else {
      error = "請先在 PDF 中拖曳選取文字，再按螢光標記。"
      return
    }
    let mapped = PDFSelection(document: document)
    for line in selection.selectionsByLine() {
      for page in line.pages {
        let index = displayed.index(for: page)
        if let original = document.page(at: index)?.selection(for: line.bounds(for: page)) {
          mapped.add(original)
        }
      }
    }
    perform { try workspace.highlight(mapped) }
    pdfView?.clearSelection()
  }

  func search() {
    guard let document = pdfView?.document else { return }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    searchResults = query.isEmpty ? [] : document.findString(query, withOptions: [.caseInsensitive])
    searchIndex = 0
    showSearchResult()
  }

  func nextSearch() {
    guard !searchResults.isEmpty else { return }
    searchIndex = (searchIndex + 1) % searchResults.count
    showSearchResult()
  }

  private func showSearchResult() {
    guard !searchResults.isEmpty else {
      status = searchText.isEmpty ? "輸入文字搜尋 PDF" : "找不到符合的文字"
      pdfView?.clearSelection()
      return
    }
    let selection = searchResults[searchIndex]
    pdfView?.setCurrentSelection(selection, animate: true)
    pdfView?.go(to: selection)
    status = "搜尋結果 \(searchIndex + 1)／\(searchResults.count)"
  }

  func startUIFixtureIfRequested() {
    guard !fixtureStarted else { return }
    fixtureStarted = true
    let args = ProcessInfo.processInfo.arguments
    guard let index = args.firstIndex(of: "--ui-check"), args.indices.contains(index + 1) else {
      return
    }
    let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
    Task { @MainActor in
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await Task.sleep(for: .seconds(1))
        try captureWindow(to: folder.appendingPathComponent("welcome.png"))
        let fixture = folder.appendingPathComponent("sample.pdf")
        try UIFixture.write(to: fixture)
        try workspace.open(fixture)
        guard
          let title = try workspace.contentItems(page: 0).first(where: {
            $0.kind == .text && $0.text.contains("A simpler")
          })
        else { throw PDFEditError.invalidSelection }
        tool = .content
        try await Task.sleep(for: .milliseconds(250))
        guard let displayedPage = pdfView?.document?.page(at: 0) else {
          throw PDFEditError.invalidSelection
        }
        place(on: displayedPage, at: CGPoint(x: title.bounds.midX, y: title.bounds.midY))
        guard selectedContent?.object == title.object, let inline = contentEditor else {
          throw PDFEditError.invalidSelection
        }
        inline.setText("你好")
        tool = .text
        guard tool == .content, contentEditor === inline, selectedContent?.object == title.object,
          inline.text == "你好", error != nil
        else { throw PDFEditError.serialization }
        error = nil
        replacementFont = .helvetica
        inline.setText("Edit your original PDF.")
        try captureWindow(to: folder.appendingPathComponent("inline-content-editing.png"))
        let contentRevision = workspace.revision
        try finishContentEditing()
        guard workspace.revision == contentRevision + 1,
          try workspace.contentItems(page: 0).contains(where: {
            $0.kind == .text && $0.text == "Edit your original PDF."
          })
        else { throw PDFEditError.serialization }
        try workspace.undo()
        guard
          try workspace.contentItems(page: 0).contains(where: {
            $0.kind == .text && $0.text.contains("A simpler")
          })
        else { throw PDFEditError.serialization }
        try workspace.redo()
        guard let image = try workspace.contentItems(page: 0).first(where: { $0.kind == .image })
        else {
          throw PDFEditError.invalidSelection
        }
        let replacement = NSImage(size: NSSize(width: 180, height: 90), flipped: false) { rect in
          NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.85, alpha: 1).setFill()
          rect.fill()
          return true
        }
        try workspace.replaceContentImage(image, with: replacement)
        try workspace.addText("Reviewed locally", page: 0, at: CGPoint(x: 64, y: 280))
        tool = .text
        try await Task.sleep(for: .milliseconds(250))
        guard let page = pdfView?.document?.page(at: 0) else { throw PDFEditError.invalidSelection }
        place(on: page, at: CGPoint(x: 260, y: 310))
        guard let editor = textEditor else { throw PDFEditError.invalidSelection }
        editor.textView.insertText(
          "自由編輯文字框\nBold / italic / underline", replacementRange: NSRange(location: 0, length: 0))
        editor.textView.setSelectedRange((editor.textView.string as NSString).range(of: "Bold"))
        applyTextFormat(.bold) { $0.bold = true }
        applyTextFormat(.color) { $0.color = .systemBlue }
        editor.textView.setSelectedRange((editor.textView.string as NSString).range(of: "italic"))
        applyTextFormat(.italic) { $0.italic = true }
        editor.textView.setSelectedRange(
          (editor.textView.string as NSString).range(of: "underline"))
        applyTextFormat(.underline) { $0.underline = true }
        try captureWindow(to: folder.appendingPathComponent("text-box-editing.png"))
        let boxID = editor.box.id
        try finishTextEditing()
        try workspace.undo()
        guard !workspace.textBoxes(page: 0).contains(where: { $0.id == boxID }) else {
          throw PDFEditError.serialization
        }
        try workspace.redo()
        editTextBox(id: boxID, page: 0)
        guard textEditor?.textView.string.contains("自由編輯") == true else {
          throw PDFEditError.serialization
        }
        try finishTextEditing()
        // Check the native overlay basis at every quarter-turn, including zoom changes.
        for _ in 0..<4 {
          try workspace.rotate([0])
          try await Task.sleep(for: .milliseconds(150))
          editTextBox(id: boxID, page: 0)
          guard let editor = textEditor, let view = pdfView, let page = view.document?.page(at: 0)
          else { throw PDFEditError.serialization }
          for local in [
            CGPoint.zero, CGPoint(x: editor.box.bounds.width, y: editor.box.bounds.height),
          ] {
            let actual = editor.convert(local, to: view)
            let expected = view.convert(
              CGPoint(x: editor.box.bounds.minX + local.x, y: editor.box.bounds.minY + local.y),
              from: page)
            guard hypot(actual.x - expected.x, actual.y - expected.y) < 0.5 else {
              print(
                "OVERLAY_GEOMETRY_FAILED rotation=\(page.rotation) actual=\(actual) expected=\(expected)"
              )
              throw PDFEditError.invalidPosition
            }
          }
          cancelTextEditing()
          tool = .content
          guard
            let title = try workspace.contentItems(page: 0).first(where: {
              $0.kind == .text && $0.text == "Edit your original PDF."
            })
          else { throw PDFEditError.invalidSelection }
          loadContent()
          selectContent(title)
          guard let inline = contentEditor else { throw PDFEditError.invalidSelection }
          let frame = inline.pageFrame(in: page)
          for local in [CGPoint.zero, CGPoint(x: frame.width, y: frame.height)] {
            let actual = inline.convert(local, to: view)
            let expected = view.convert(
              CGPoint(x: frame.minX + local.x, y: frame.minY + local.y), from: page)
            guard hypot(actual.x - expected.x, actual.y - expected.y) < 0.5 else {
              throw PDFEditError.invalidPosition
            }
          }
          cancelContentEditing()
          tool = .text
        }
        go(to: 2)
        try await Task.sleep(for: .milliseconds(250))
        guard let view = pdfView as? InteractivePDFView,
          let displayed = view.document,
          let selection = displayed.findString(
            "Every edit starts with a recoverable snapshot.", withOptions: []
          ).first(where: { $0.pages.contains { displayed.index(for: $0) == 2 } })
        else {
          throw PDFEditError.invalidSelection
        }
        let beforeComment = workspace.revision
        view.setCurrentSelection(selection, animate: false)
        beginCommentFromSelection()
        guard workspace.revision == beforeComment, pendingCommentPage == 2,
          view.isCommentBubbleVisible
        else {
          throw PDFEditError.serialization
        }
        view.setCommentDraftText("第三頁：請確認這段內容")
        try captureWindow(to: folder.appendingPathComponent("comment-draft.png"))
        publishComment()
        try await Task.sleep(for: .milliseconds(500))
        guard let comment = workspace.comments(page: 2).first,
          comment.isTextAnchor, currentPage == 2, let visible = view.currentPage,
          view.document?.index(for: visible) == 2
        else {
          print(
            "COMMENT_PAGE_FAILED controller=\(currentPage) visible=\(String(describing: pdfView?.currentPage))"
          )
          throw PDFEditError.invalidSelection
        }
        replyDraft = "已確認，謝謝"
        replyToComment()
        toggleCommentResolved()
        try await Task.sleep(for: .milliseconds(300))
        guard currentPage == 2, workspace.comments(page: 2).first?.resolved == true else {
          throw PDFEditError.invalidSelection
        }
        guard let savedComment = workspace.comments(page: 2).first else {
          throw PDFEditError.invalidSelection
        }
        view.showHoverComment(savedComment)
        guard view.isCommentBubbleVisible else { throw PDFEditError.serialization }
        try captureWindow(to: folder.appendingPathComponent("comment-hover.png"))
        view.hideHoverComment()
        guard !view.isCommentBubbleVisible else { throw PDFEditError.serialization }
        try captureWindow(to: folder.appendingPathComponent("comment-hidden.png"))
        tool = .text
        openPageManager()
        guard pageManagerOpen else { throw PDFEditError.serialization }
        selectedPages = [0, 2]
        try await Task.sleep(for: .milliseconds(250))
        try captureWindow(to: folder.appendingPathComponent("page-management.png"))
        try capturePageDragPreview(
          to: folder.appendingPathComponent("page-drag-single.png"), count: 1)
        try capturePageDragPreview(
          to: folder.appendingPathComponent("page-drag-preview.png"), count: 2)
        moveManagedPages([0, 2], onto: 1)
        guard workspace.document?.page(at: 0)?.string?.contains("Keep your ideas") == true,
          selectedPages == Set([1, 2])
        else { throw PDFEditError.serialization }
        try workspace.undo()
        guard workspace.document?.page(at: 0)?.string?.contains("Edit your original") == true
        else { throw PDFEditError.serialization }
        try workspace.redo()
        guard workspace.document?.page(at: 0)?.string?.contains("Keep your ideas") == true
        else { throw PDFEditError.serialization }
        try workspace.undo()
        selectedPages = [0, 2]
        rotateSelectedPages()
        guard workspace.document?.page(at: 0)?.rotation == 90,
          workspace.document?.page(at: 2)?.rotation == 90
        else { throw PDFEditError.serialization }
        try workspace.undo()
        closePageManager()
        status = "合成驗收文件 · 原檔保留 · 離線編輯"
        try await Task.sleep(for: .seconds(1))
        try captureWindow(to: folder.appendingPathComponent("editor-chrome.png"))
        try workspace.saveCopy(to: folder.appendingPathComponent("edited.pdf"))
        print(
          "UI_CHECK_OK: welcome.png, inline-content-editing.png, text-box-editing.png, comment-draft.png, comment-hover.png, comment-hidden.png, page-management.png, page-drag-single.png, page-drag-preview.png, editor-chrome.png, edited.pdf"
        )
      } catch {
        print("UI_CHECK_FAILED: \(error)")
        exit(EXIT_FAILURE)
      }
      NSApplication.shared.terminate(nil)
    }
  }

  private func captureWindow(to url: URL) throws {
    guard let content = window?.contentView,
      let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)
    else { throw PDFEditError.serialization }
    content.cacheDisplay(in: content.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw PDFEditError.serialization
    }
    try data.write(to: url, options: .atomic)
  }

  private func capturePageDragPreview(to url: URL, count: Int) throws {
    guard let content = window?.contentView, let page = workspace.document?.page(at: 0) else {
      throw PDFEditError.serialization
    }
    let preview = PageDragPreviewSurface(frame: content.bounds)
    preview.autoresizingMask = [.width, .height]
    content.addSubview(preview)
    defer { preview.removeFromSuperview() }
    let point = content.convert(
      NSPoint(x: content.bounds.midX * 0.8, y: content.bounds.midY), to: nil)
    preview.show(
      image: page.thumbnail(of: CGSize(width: 270, height: 350), for: .cropBox), count: count,
      at: point)
    try captureWindow(to: url)
  }
}
