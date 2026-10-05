import AppKit
import Combine
import PDFKit

public enum PDFEditError: LocalizedError, Equatable {
  case invalidDocument, encrypted, unsupportedWidgets, permission, invalidSelection
  case lastPage, originalPath, serialization, undoLimit, emptyText, invalidPosition
  case textBoxOverflow, invalidTextStyle
  case commentTooLong

  public var errorDescription: String? {
    switch self {
    case .invalidDocument: "無法開啟 PDF，請確認檔案有效且至少有一頁。"
    case .encrypted: "這個原型暫不支援加密或密碼 PDF。請使用另外解密的工作副本。"
    case .unsupportedWidgets: "這份 PDF 有表單或簽章欄位，目前只供閱讀，暫不支援編輯。"
    case .permission: "這份 PDF 不允許此操作。"
    case .invalidSelection: "請先選擇有效的頁面或註解。"
    case .lastPage: "文件至少要保留一頁。"
    case .originalPath: "請選擇新的輸出檔名，保留開啟及合併的所有原檔。"
    case .serialization: "無法驗證輸出的 PDF，變更尚未儲存。"
    case .undoLimit: "文件超過 64 MiB 復原快照限制，此原型暫時無法安全編輯。"
    case .emptyText: "請先輸入文字。"
    case .invalidPosition: "請在 PDF 頁面內放置內容。"
    case .textBoxOverflow: "文字超出文字框或頁面範圍。請加大文字框、減小字級或縮短內容。"
    case .invalidTextStyle: "請使用 6–144 pt 的文字；文字框不支援貼入附件。"
    case .commentTooLong: "註解討論太長，請縮短內容後再試。"
    }
  }
}

@MainActor
public final class PDFWorkspace: ObservableObject {
  @Published public private(set) var document: PDFDocument?
  @Published public private(set) var sourceURL: URL?
  @Published public private(set) var isDirty = false
  @Published public private(set) var revision = 0
  @Published public private(set) var canUndo = false
  @Published public private(set) var canRedo = false

  private struct Snapshot {
    let data: Data
    let dirty: Bool
  }

  private struct InputIdentity {
    let path: String
    let inode: String?

    init(_ url: URL) {
      path = url.standardizedFileURL.resolvingSymlinksInPath().path
      let attrs = try? FileManager.default.attributesOfItem(atPath: path)
      if let device = attrs?[.systemNumber], let number = attrs?[.systemFileNumber] {
        inode = "\(device):\(number)"
      } else {
        inode = nil
      }
    }

    func matches(_ other: InputIdentity) -> Bool {
      path == other.path || (inode != nil && inode == other.inode)
    }
  }

  private var inputs: [InputIdentity] = []
  // Keep the original/candidate streams intact until a PDFKit operation changes them.
  // Repeated PDFKit serialization can flatten forms and change object identity.
  private var contentData: Data?
  private var undoStack: [Snapshot] = []
  private var redoStack: [Snapshot] = []
  private let historyLimit: Int

  public init(historyByteLimit: Int = 64 * 1024 * 1024) {
    historyLimit = max(1, historyByteLimit)
  }

  public var pageCount: Int { document?.pageCount ?? 0 }

  public func contentItems(page: Int) throws -> [PDFContentItem] {
    guard let document, (0..<document.pageCount).contains(page),
      let data = contentData ?? document.dataRepresentation()
    else { throw PDFEditError.invalidSelection }
    return try PDFContentEditor.items(data, page: page, revision: revision)
  }

  public func replaceContentText(
    _ item: PDFContentItem, with text: String, font: PDFContentFont = .original
  ) throws {
    try editContent(item, replacingText: true) { data, document in
      guard let page = document.page(at: item.page) else { throw PDFEditError.invalidSelection }
      return try PDFContentEditor.replaceText(
        data, item: item, text: text, font: font, cropBox: page.bounds(for: .cropBox))
    }
  }

  public func replaceContentImage(_ item: PDFContentItem, with image: NSImage) throws {
    try editContent(item) { data, _ in
      try PDFContentEditor.replaceImage(data, item: item, image: image)
    }
  }

  public func removeContent(_ item: PDFContentItem) throws {
    try editContent(item) { data, _ in try PDFContentEditor.remove(data, item: item) }
  }

  private func editContent(
    _ item: PDFContentItem, replacingText: Bool = false,
    operation: (Data, PDFDocument) throws -> Data
  ) throws {
    let original = try editableDocument()
    guard original.allowsDocumentChanges else { throw PDFEditError.permission }
    guard item.revision == revision else { throw PDFContentError.staleSelection }
    let before = try snapshot()
    let data = try operation(before.data, original)
    guard data.count <= historyLimit else { throw PDFEditError.undoLimit }
    let candidate = try parse(data)
    guard candidate.pageCount == original.pageCount else { throw PDFEditError.serialization }
    var allowed = item.bounds
    if replacingText,
      let updated = try PDFContentEditor.items(data, page: item.page, revision: revision)
        .first(where: { $0.object == item.object && $0.kind == .text })
    {
      allowed = allowed.union(updated.bounds)
    }
    try PDFContentAppearance.validate(
      before: before.data, after: data, page: item.page, allowed: allowed)
    try mutate(candidateData: data) { document = candidate }
  }

  public func displayCopy() throws -> PDFDocument {
    guard let data = contentData ?? document?.dataRepresentation() else {
      throw PDFEditError.serialization
    }
    let copy = try parse(data)
    for index in 0..<copy.pageCount {
      for annotation in copy.page(at: index)?.annotations ?? [] {
        let flags = (annotation.value(forAnnotationKey: .flags) as? NSNumber)?.intValue ?? 0
        annotation.setValue(flags | 64, forAnnotationKey: .flags)
        if annotation.type == "Widget" { annotation.isReadOnly = true }
      }
    }
    return copy
  }

  public var editingRestriction: String? {
    guard let document else { return "請先開啟 PDF。" }
    if document.isEncrypted { return PDFEditError.encrypted.localizedDescription }
    if containsWidgets(document) { return PDFEditError.unsupportedWidgets.localizedDescription }
    if !document.allowsCommenting || !document.allowsDocumentAssembly {
      return PDFEditError.permission.localizedDescription
    }
    return nil
  }

  public func open(_ url: URL) throws {
    let data = try Data(contentsOf: url)
    let candidate = try parse(data)
    document = candidate
    contentData = data
    sourceURL = url
    inputs = [InputIdentity(url)]
    isDirty = false
    undoStack = []
    redoStack = []
    refresh()
  }

  private func parse(_ data: Data) throws -> PDFDocument {
    guard let candidate = PDFDocument(data: data) else { throw PDFEditError.invalidDocument }
    guard !candidate.isEncrypted else { throw PDFEditError.encrypted }
    guard candidate.pageCount > 0 else { throw PDFEditError.invalidDocument }
    return candidate
  }

  private func containsWidgets(_ document: PDFDocument) -> Bool {
    (0..<document.pageCount).contains { index in
      document.page(at: index)?.annotations.contains { $0.type == "Widget" } ?? false
    }
  }

  private func editableDocument() throws -> PDFDocument {
    guard let document else { throw PDFEditError.invalidDocument }
    guard !document.isEncrypted else { throw PDFEditError.encrypted }
    guard !containsWidgets(document) else { throw PDFEditError.unsupportedWidgets }
    return document
  }

  private func pages(_ indices: [Int], in document: PDFDocument) throws -> [Int] {
    let unique = Array(Set(indices)).sorted()
    guard !unique.isEmpty, unique.allSatisfy({ (0..<document.pageCount).contains($0) }) else {
      throw PDFEditError.invalidSelection
    }
    return unique
  }

  private func snapshot() throws -> Snapshot {
    guard let document, let data = contentData ?? document.dataRepresentation() else {
      throw PDFEditError.serialization
    }
    guard data.count <= historyLimit else { throw PDFEditError.undoLimit }
    return Snapshot(data: data, dirty: isDirty)
  }

  private func mutate(candidateData: Data? = nil, _ operation: () -> Void) throws {
    let before = try snapshot()
    operation()
    contentData = candidateData
    do {
      // The resulting document must also fit: undo needs to retain it for redo.
      contentData = try snapshot().data
    } catch {
      document = try parse(before.data)
      contentData = before.data
      refresh()
      throw error
    }
    undoStack.append(before)
    redoStack = []
    isDirty = true
    trimHistory()
    refresh()
  }

  private func trimHistory() {
    while undoStack.count > 24 { undoStack.removeFirst() }
    while redoStack.count > 24 { redoStack.removeFirst() }
    while undoStack.reduce(0, { $0 + $1.data.count })
      + redoStack.reduce(0, { $0 + $1.data.count }) > historyLimit
    {
      if !undoStack.isEmpty {
        undoStack.removeFirst()
      } else if !redoStack.isEmpty {
        redoStack.removeFirst()
      }
    }
  }

  private func refresh() {
    canUndo = !undoStack.isEmpty
    canRedo = !redoStack.isEmpty
    revision += 1
  }

  public func undo() throws {
    guard let target = undoStack.last else { return }
    let current = try snapshot()
    let restored = try parse(target.data)
    undoStack.removeLast()
    redoStack.append(current)
    document = restored
    contentData = target.data
    isDirty = target.dirty
    trimHistory()
    refresh()
  }

  public func redo() throws {
    guard let target = redoStack.last else { return }
    let current = try snapshot()
    let restored = try parse(target.data)
    redoStack.removeLast()
    undoStack.append(current)
    document = restored
    contentData = target.data
    isDirty = target.dirty
    trimHistory()
    refresh()
  }

  public func rotate(_ indices: [Int], clockwise: Bool = true) throws {
    let document = try editableDocument()
    guard document.allowsDocumentAssembly else { throw PDFEditError.permission }
    let indices = try pages(indices, in: document)
    try mutate {
      for index in indices {
        guard let page = document.page(at: index) else { continue }
        page.rotation = (page.rotation + (clockwise ? 90 : 270)) % 360
      }
    }
  }

  public func delete(_ indices: [Int]) throws {
    let document = try editableDocument()
    guard document.allowsDocumentAssembly else { throw PDFEditError.permission }
    let indices = try pages(indices, in: document)
    guard indices.count < document.pageCount else { throw PDFEditError.lastPage }
    try mutate {
      for index in indices.reversed() { document.removePage(at: index) }
    }
  }

  public func movePage(at index: Int, to destination: Int) throws {
    let document = try editableDocument()
    guard document.allowsDocumentAssembly else { throw PDFEditError.permission }
    _ = try pages([index, destination], in: document)
    guard index != destination, let page = document.page(at: index) else { return }
    try mutate {
      document.removePage(at: index)
      document.insert(page, at: destination)
    }
  }

  /// Inserts the selected pages before `destination` in the original page order.
  public func movePages(_ indices: [Int], before destination: Int) throws {
    let document = try editableDocument()
    guard document.allowsDocumentAssembly else { throw PDFEditError.permission }
    let indices = try pages(indices, in: document)
    guard (0...document.pageCount).contains(destination) else {
      throw PDFEditError.invalidSelection
    }
    let selected = Set(indices)
    let remaining = (0..<document.pageCount).filter { !selected.contains($0) }
    let insertion = destination - indices.filter { $0 < destination }.count
    let reordered =
      Array(remaining.prefix(insertion)) + indices + Array(remaining.dropFirst(insertion))
    guard reordered != Array(0..<document.pageCount) else { return }
    let moving = indices.compactMap { document.page(at: $0) }
    guard moving.count == indices.count else { throw PDFEditError.serialization }
    try mutate {
      for index in indices.reversed() { document.removePage(at: index) }
      for (offset, page) in moving.enumerated() { document.insert(page, at: insertion + offset) }
    }
  }

  public func append(_ url: URL) throws {
    let document = try editableDocument()
    guard document.allowsDocumentAssembly else { throw PDFEditError.permission }
    let incoming = try parse(Data(contentsOf: url))
    guard incoming.allowsCopying else { throw PDFEditError.permission }
    guard !containsWidgets(incoming) else { throw PDFEditError.unsupportedWidgets }
    let copies = try (0..<incoming.pageCount).map { index -> PDFPage in
      guard let page = incoming.page(at: index)?.copy() as? PDFPage else {
        throw PDFEditError.serialization
      }
      return page
    }
    try mutate {
      for page in copies { document.insert(page, at: document.pageCount) }
    }
    inputs.append(InputIdentity(url))
  }

  private func pageForAnnotation(_ index: Int) throws -> PDFPage {
    let document = try editableDocument()
    guard document.allowsCommenting else { throw PDFEditError.permission }
    _ = try pages([index], in: document)
    guard let page = document.page(at: index) else { throw PDFEditError.invalidSelection }
    return page
  }

  private func placement(_ point: CGPoint, size: CGSize, on page: PDFPage) throws -> CGRect {
    let box = page.bounds(for: .cropBox)
    guard point.x.isFinite, point.y.isFinite, box.contains(point),
      box.width > 0, box.height > 0
    else { throw PDFEditError.invalidPosition }
    let width = min(size.width, box.width)
    let height = min(size.height, box.height)
    return CGRect(
      x: max(box.minX, min(point.x, box.maxX - width)),
      y: max(box.minY, min(point.y - height, box.maxY - height)),
      width: width, height: height
    )
  }

  public func textBoxes(page index: Int) -> [PDFTextBox] {
    document?.page(at: index)?.annotations.compactMap { PDFTextBox.decode($0, page: index) } ?? []
  }

  public func textBoxBounds(page index: Int, at point: CGPoint) throws -> CGRect {
    let page = try pageForAnnotation(index)
    return try placement(point, size: CGSize(width: 280, height: 100), on: page)
  }

  /// Create or replace a box in one undo step. Bounds are clamped to the page, never clipped silently.
  public func saveTextBox(_ box: PDFTextBox) throws {
    let page = try pageForAnnotation(box.page)
    let crop = page.bounds(for: .cropBox)
    let values = [box.bounds.minX, box.bounds.minY, box.bounds.width, box.bounds.height]
    guard values.allSatisfy({ $0.isFinite }), box.bounds.width >= 24, box.bounds.height >= 24,
      box.bounds.width <= crop.width, box.bounds.height <= crop.height
    else { throw PDFEditError.invalidPosition }
    let text = try PDFTextBox.normalized(box.text)
    let required = PDFTextBox.requiredHeight(for: text, width: box.bounds.width)
    let height = max(box.bounds.height, required)
    guard height <= crop.height else { throw PDFEditError.textBoxOverflow }
    // Keep the top edge when growing a box; then fit it into the CropBox.
    let bounds = CGRect(
      x: max(crop.minX, min(box.bounds.minX, crop.maxX - box.bounds.width)),
      y: max(crop.minY, min(box.bounds.maxY - height, crop.maxY - height)),
      width: box.bounds.width, height: height)
    let clean = PDFTextBox(id: box.id, page: box.page, bounds: bounds, text: text)
    let rtf = try text.data(
      from: NSRange(location: 0, length: text.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    guard rtf.count <= 1024 * 1024 else { throw PDFEditError.textBoxOverflow }
    let annotation = RichTextAnnotation(clean, rtf: rtf)
    let old = page.annotations.first { PDFTextBox.decode($0, page: box.page)?.id == box.id }
    try mutate {
      if let old { page.removeAnnotation(old) }
      page.addAnnotation(annotation)
    }
  }

  public func removeTextBox(id: String, page index: Int) throws {
    let page = try pageForAnnotation(index)
    guard
      let annotation = page.annotations.first(where: {
        PDFTextBox.decode($0, page: index)?.id == id
      })
    else {
      throw PDFEditError.invalidSelection
    }
    try mutate { page.removeAnnotation(annotation) }
  }

  public func addText(_ text: String, page index: Int, at point: CGPoint, fontSize: CGFloat = 18)
    throws
  {
    let rich = NSAttributedString(
      string: text,
      attributes: [
        .font: NSFont.systemFont(ofSize: min(144, max(6, fontSize))),
        .foregroundColor: NSColor.black,
      ])
    let page = try pageForAnnotation(index)
    let width = min(300, page.bounds(for: .cropBox).width)
    let bounds = try placement(
      point,
      size: CGSize(
        width: width, height: max(24, PDFTextBox.requiredHeight(for: rich, width: width))), on: page
    )
    try saveTextBox(PDFTextBox(page: index, bounds: bounds, text: rich))
  }

  public func addNote(_ text: String, page index: Int, at point: CGPoint) throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PDFEditError.emptyText
    }
    let page = try pageForAnnotation(index)
    let bounds = try placement(point, size: CGSize(width: 24, height: 24), on: page)
    let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
    annotation.contents = text
    annotation.color = .systemYellow
    annotation.iconType = .note
    try mutate { page.addAnnotation(annotation) }
  }

  public func comments(page index: Int) -> [PDFComment] {
    guard let page = document?.page(at: index) else { return [] }
    return page.annotations.enumerated().compactMap { offset, annotation in
      let thread = PDFCommentThread.decode(annotation)
      guard
        annotation.type == "Text"
          || (annotation.type == "Highlight" && thread?.anchorRects?.isEmpty == false)
      else { return nil }
      return PDFComment(
        id: thread?.id ?? "legacy:\(index):\(offset)", page: index, bounds: annotation.bounds,
        author: annotation.userName?.isEmpty == false ? annotation.userName! : "未署名",
        createdAt: thread?.createdAt ?? annotation.modificationDate ?? .distantPast,
        text: annotation.contents ?? "", replies: thread?.replies ?? [],
        resolved: thread?.resolved ?? false, anchorRects: thread?.anchorRects ?? [])
    }
  }

  @discardableResult
  public func createComment(_ text: String, page index: Int, at point: CGPoint) throws -> PDFComment
  {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { throw PDFEditError.emptyText }
    let page = try pageForAnnotation(index)
    let bounds = try placement(point, size: CGSize(width: 24, height: 24), on: page)
    let now = Date()
    let thread = PDFCommentThread(
      version: 1, id: UUID().uuidString, createdAt: now,
      replies: [], resolved: false)
    let raw = try thread.encoded()
    let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
    annotation.contents = body
    annotation.userName = "我"
    annotation.modificationDate = now
    annotation.color = .systemYellow
    annotation.iconType = .comment
    annotation.setValue(raw, forAnnotationKey: PDFCommentThread.key)
    try mutate { page.addAnnotation(annotation) }
    return PDFComment(
      id: thread.id, page: index, bounds: bounds, author: "我", createdAt: now,
      text: body)
  }

  @discardableResult
  public func createAnchoredComment(_ text: String, page index: Int, rects: [CGRect]) throws
    -> PDFComment
  {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { throw PDFEditError.emptyText }
    let page = try pageForAnnotation(index)
    let crop = page.bounds(for: .cropBox)
    guard !rects.isEmpty,
      rects.allSatisfy({ rect in
        [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
          && rect.width > 0 && rect.height > 0 && crop.contains(rect)
      })
    else { throw PDFEditError.invalidSelection }
    let bounds = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
    let now = Date()
    let thread = PDFCommentThread(
      version: 1, id: UUID().uuidString, createdAt: now, replies: [], resolved: false,
      anchorRects: rects)
    let raw = try thread.encoded()
    let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
    annotation.contents = body
    annotation.userName = "我"
    annotation.modificationDate = now
    annotation.color = NSColor(calibratedRed: 0.96, green: 0.15, blue: 0.18, alpha: 0.48)
    annotation.quadrilateralPoints = rects.flatMap { rect in
      [
        NSValue(point: CGPoint(x: rect.minX - bounds.minX, y: rect.maxY - bounds.minY)),
        NSValue(point: CGPoint(x: rect.maxX - bounds.minX, y: rect.maxY - bounds.minY)),
        NSValue(point: CGPoint(x: rect.minX - bounds.minX, y: rect.minY - bounds.minY)),
        NSValue(point: CGPoint(x: rect.maxX - bounds.minX, y: rect.minY - bounds.minY)),
      ]
    }
    annotation.setValue(raw, forAnnotationKey: PDFCommentThread.key)
    try mutate { page.addAnnotation(annotation) }
    return PDFComment(
      id: thread.id, page: index, bounds: bounds, author: "我", createdAt: now, text: body,
      anchorRects: rects)
  }

  @discardableResult
  public func editComment(_ id: String, page index: Int, text: String) throws -> String {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { throw PDFEditError.emptyText }
    return try updateComment(id, page: index) { annotation, _ in annotation.contents = body }
  }

  @discardableResult
  public func replyToComment(_ id: String, page index: Int, text: String) throws -> String {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { throw PDFEditError.emptyText }
    return try updateComment(id, page: index) { _, thread in
      thread.replies.append(PDFCommentReply(text: body))
    }
  }

  @discardableResult
  public func editCommentReply(_ id: String, page index: Int, replyID: String, text: String)
    throws -> String
  {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { throw PDFEditError.emptyText }
    guard
      comments(page: index).first(where: { $0.id == id })?.replies.contains(where: {
        $0.id == replyID
      }) == true
    else { throw PDFEditError.invalidSelection }
    return try updateComment(id, page: index) { _, thread in
      if let offset = thread.replies.firstIndex(where: { $0.id == replyID }) {
        thread.replies[offset].text = body
      }
    }
  }

  @discardableResult
  public func deleteCommentReply(_ id: String, page index: Int, replyID: String) throws -> String {
    guard
      comments(page: index).first(where: { $0.id == id })?.replies.contains(where: {
        $0.id == replyID
      }) == true
    else { throw PDFEditError.invalidSelection }
    return try updateComment(id, page: index) { _, thread in
      thread.replies.removeAll { $0.id == replyID }
    }
  }

  @discardableResult
  public func setCommentResolved(_ id: String, page index: Int, resolved: Bool) throws -> String {
    try updateComment(id, page: index) { _, thread in thread.resolved = resolved }
  }

  public func deleteComment(_ id: String, page index: Int) throws {
    let (page, annotation, _) = try commentAnnotation(id, page: index)
    try mutate { page.removeAnnotation(annotation) }
  }

  private func commentAnnotation(_ id: String, page index: Int)
    throws -> (PDFPage, PDFAnnotation, PDFCommentThread?)
  {
    let page = try pageForAnnotation(index)
    let annotation: PDFAnnotation?
    if id.hasPrefix("legacy:\(index):"),
      let offset = Int(id.dropFirst("legacy:\(index):".count)),
      page.annotations.indices.contains(offset), page.annotations[offset].type == "Text",
      PDFCommentThread.decode(page.annotations[offset]) == nil
    {
      annotation = page.annotations[offset]
    } else {
      annotation = page.annotations.first {
        ($0.type == "Text" || $0.type == "Highlight") && PDFCommentThread.decode($0)?.id == id
      }
    }
    guard let annotation else { throw PDFEditError.invalidSelection }
    return (page, annotation, PDFCommentThread.decode(annotation))
  }

  private func updateComment(
    _ id: String, page index: Int,
    _ change: (PDFAnnotation, inout PDFCommentThread) -> Void
  ) throws -> String {
    let (page, annotation, existing) = try commentAnnotation(id, page: index)
    var thread =
      existing
      ?? PDFCommentThread(
        version: 1, id: UUID().uuidString, createdAt: annotation.modificationDate ?? .now,
        replies: [], resolved: false)
    // Compute the changed annotation on a detached copy so serialization failures cannot
    // leave the working document mutated outside the undo transaction.
    guard let replacement = annotation.copy() as? PDFAnnotation else {
      throw PDFEditError.serialization
    }
    change(replacement, &thread)
    let raw = try thread.encoded()
    replacement.setValue(raw, forAnnotationKey: PDFCommentThread.key)
    replacement.modificationDate = .now
    try mutate {
      page.removeAnnotation(annotation)
      page.addAnnotation(replacement)
    }
    return thread.id
  }

  public func addImage(_ image: NSImage, page index: Int, at point: CGPoint, width: CGFloat = 180)
    throws
  {
    guard image.size.width > 0, image.size.height > 0, width.isFinite, width > 0 else {
      throw PDFEditError.invalidPosition
    }
    let page = try pageForAnnotation(index)
    let box = page.bounds(for: .cropBox)
    let scale = min(
      width / image.size.width, box.width / image.size.width, box.height / image.size.height)
    let bounds = try placement(
      point, size: CGSize(width: image.size.width * scale, height: image.size.height * scale),
      on: page
    )
    let annotation = ImageStamp(image: image, bounds: bounds)
    try mutate { page.addAnnotation(annotation) }
  }

  public func highlight(_ selection: PDFSelection) throws {
    let document = try editableDocument()
    guard document.allowsCommenting else { throw PDFEditError.permission }
    var annotations: [(PDFPage, PDFAnnotation)] = []
    for line in selection.selectionsByLine() {
      for page in line.pages {
        guard document.index(for: page) != NSNotFound else { throw PDFEditError.invalidSelection }
        let bounds = line.bounds(for: page)
        guard !bounds.isEmpty else { continue }
        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        annotation.color = NSColor.systemYellow.withAlphaComponent(0.45)
        annotation.quadrilateralPoints = [
          NSValue(point: CGPoint(x: 0, y: bounds.height)),
          NSValue(point: CGPoint(x: bounds.width, y: bounds.height)),
          NSValue(point: .zero),
          NSValue(point: CGPoint(x: bounds.width, y: 0)),
        ]
        annotations.append((page, annotation))
      }
    }
    guard !annotations.isEmpty else { throw PDFEditError.invalidSelection }
    try mutate {
      for (page, annotation) in annotations { page.addAnnotation(annotation) }
    }
  }

  public func removeAnnotation(_ annotation: PDFAnnotation, page index: Int) throws {
    let page = try pageForAnnotation(index)
    guard page.annotations.contains(where: { $0 === annotation }) else {
      throw PDFEditError.invalidSelection
    }
    try mutate { page.removeAnnotation(annotation) }
  }

  public func saveCopy(to url: URL) throws {
    let document = try editableDocument()
    guard let data = contentData ?? document.dataRepresentation(),
      let reopened = PDFDocument(data: data), reopened.pageCount == document.pageCount
    else { throw PDFEditError.serialization }
    try write(data, to: url)
    isDirty = false
    undoStack = []
    redoStack = []
    refresh()
  }

  public func extract(_ indices: [Int], to url: URL) throws {
    let document = try editableDocument()
    guard document.allowsCopying else { throw PDFEditError.permission }
    let indices = try pages(indices, in: document)
    let result = PDFDocument()
    for index in indices {
      guard let page = document.page(at: index)?.copy() as? PDFPage else {
        throw PDFEditError.serialization
      }
      result.insert(page, at: result.pageCount)
    }
    guard let data = result.dataRepresentation(),
      PDFDocument(data: data)?.pageCount == indices.count
    else { throw PDFEditError.serialization }
    try write(data, to: url)
  }

  private func write(_ data: Data, to url: URL) throws {
    let destination = InputIdentity(url)
    guard !inputs.contains(where: { $0.matches(destination) }) else {
      throw PDFEditError.originalPath
    }
    try data.write(to: url, options: .atomic)
  }
}

private final class ImageStamp: PDFAnnotation {
  private let image: NSImage

  init(image: NSImage, bounds: CGRect) {
    self.image = image
    super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    contents = "新增圖片"
    stampName = "LocalPDFImage"
    color = .clear
  }

  required init?(coder: NSCoder) { nil }

  override func draw(with box: PDFDisplayBox, in context: CGContext) {
    context.saveGState()
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    context.restoreGState()
  }
}
