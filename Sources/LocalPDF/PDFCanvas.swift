import AppKit
import LocalPDFCore
import PDFKit
import SwiftUI

struct PDFCanvas: NSViewRepresentable {
  @ObservedObject var controller: DocumentController
  let document: PDFDocument
  let revision: Int

  func makeNSView(context: Context) -> InteractivePDFView {
    let view = InteractivePDFView()
    view.controller = controller
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
    view.backgroundColor = NSColor(red: 0.89, green: 0.91, blue: 0.92, alpha: 1)
    view.autoScales = true
    controller.pdfView = view
    return view
  }

  func updateNSView(_ view: InteractivePDFView, context: Context) {
    view.synchronizing = true
    defer { view.synchronizing = false }
    let documentChanged = view.displayedRevision != revision
    if documentChanged {
      view.hideHoverComment()
      let scale = view.scaleFactor
      let fit = view.autoScales
      do {
        // The PDFKit editor never receives the mutable workspace document.
        view.document = try controller.workspace.displayCopy()
        view.displayedRevision = revision
        view.autoScales = fit
        if !fit { view.scaleFactor = scale }
      } catch {
        view.document = nil
        Task { @MainActor in controller.error = error.localizedDescription }
        return
      }
    }
    view.setNeedsDisplay(view.bounds)
    view.layoutDocumentView()
    if let page = view.document?.page(at: controller.currentPage),
      documentChanged || view.currentPage !== page
    {
      view.go(to: page)
    }
    view.showContentSelection()
    view.positionContentEditor()
    view.positionTextEditor()
    view.showCommentPresentation()
  }

  static func dismantleNSView(_ view: InteractivePDFView, coordinator: ()) { view.stopObserving() }
}

@MainActor
final class InteractivePDFView: PDFView {
  var displayedRevision = -1
  var synchronizing = false
  weak var controller: DocumentController?
  private var monitor: Any?
  private var hoverMonitor: Any?
  private var observer: NSObjectProtocol?
  private var selectionOutline: PDFAnnotation?
  private var outlinedID: String?
  private var textEditor: TextBoxEditor?
  private var contentEditor: InlineContentEditor?
  private var hiddenTextAnnotation: PDFAnnotation?
  private var geometryObservers: [NSObjectProtocol] = []
  private var commentCallout: CommentCalloutView?
  private var commentDraftHighlight: PDFAnnotation?
  private var presentedDraftKey: String?
  private var hoveredCommentID: String?
  private var trackingAreaForComments: NSTrackingArea?

  var commentDraftText: String? {
    guard controller?.pendingCommentPage != nil else { return nil }
    return commentCallout?.draftText
  }

  var isCommentBubbleVisible: Bool { commentCallout != nil }

  func setCommentDraftText(_ text: String) { commentCallout?.setDraftText(text) }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.acceptsMouseMovedEvents = true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingAreaForComments { removeTrackingArea(trackingAreaForComments) }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
      owner: self, userInfo: nil)
    addTrackingArea(area)
    trackingAreaForComments = area
  }

  func showCommentPresentation() {
    guard let controller else { return }
    if let index = controller.pendingCommentPage, !controller.pendingCommentRects.isEmpty,
      let page = document?.page(at: index)
    {
      hoveredCommentID = nil
      let key = "\(displayedRevision):\(index):\(controller.pendingCommentRects)"
      if presentedDraftKey != key {
        if let old = commentDraftHighlight { old.page?.removeAnnotation(old) }
        let rects = controller.pendingCommentRects
        let bounds = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        let highlight = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        highlight.color = NSColor(calibratedRed: 0.96, green: 0.15, blue: 0.18, alpha: 0.48)
        highlight.quadrilateralPoints = rects.flatMap { rect in
          [
            NSValue(point: CGPoint(x: rect.minX - bounds.minX, y: rect.maxY - bounds.minY)),
            NSValue(point: CGPoint(x: rect.maxX - bounds.minX, y: rect.maxY - bounds.minY)),
            NSValue(point: CGPoint(x: rect.minX - bounds.minX, y: rect.minY - bounds.minY)),
            NSValue(point: CGPoint(x: rect.maxX - bounds.minX, y: rect.minY - bounds.minY)),
          ]
        }
        page.addAnnotation(highlight)
        commentDraftHighlight = highlight
        presentedDraftKey = key
        commentCallout?.removeFromSuperview()
        let bubble = CommentCalloutView(
          text: controller.commentDraft, draft: true,
          onCommit: { [weak controller] text in
            controller?.commentDraft = text
            controller?.publishComment()
          },
          onChange: { [weak controller] text in controller?.commentDraft = text })
        commentCallout = bubble
        addSubview(bubble)
        positionCommentCallout()
        bubble.focus()
      } else {
        positionCommentCallout()
      }
      return
    }
    if let old = commentDraftHighlight { old.page?.removeAnnotation(old) }
    commentDraftHighlight = nil
    presentedDraftKey = nil
    if hoveredCommentID == nil {
      commentCallout?.removeFromSuperview()
      commentCallout = nil
    }
    positionCommentCallout()
  }

  func positionCommentCallout() {
    guard let controller, let bubble = commentCallout else { return }
    if let index = controller.pendingCommentPage,
      let rect = controller.pendingCommentRects.last,
      let page = document?.page(at: index)
    {
      bubble.position(in: self, page: page, anchor: rect)
    } else if let id = hoveredCommentID,
      let comment = (0..<controller.workspace.pageCount).lazy
        .flatMap({ controller.workspace.comments(page: $0) }).first(where: { $0.id == id }),
      let page = document?.page(at: comment.page), let rect = comment.anchorRects.last
    {
      bubble.position(in: self, page: page, anchor: rect)
    }
  }

  func hideHoverComment() {
    guard controller?.pendingCommentPage == nil else { return }
    hoveredCommentID = nil
    commentCallout?.removeFromSuperview()
    commentCallout = nil
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    updateHoveredComment(for: event)
  }

  private func updateHoveredComment(for event: NSEvent) {
    guard let controller, controller.pendingCommentPage == nil else { return }
    let point = convert(event.locationInWindow, from: nil)
    guard let page = page(for: point, nearest: false), let index = document?.index(for: page)
    else {
      hideHoverComment()
      return
    }
    let pagePoint = convert(point, to: page)
    guard
      let comment = controller.workspace.comments(page: index).reversed().first(where: {
        $0.isTextAnchor && $0.anchorRects.contains(where: { $0.contains(pagePoint) })
      })
    else {
      hideHoverComment()
      return
    }
    showHoverComment(comment)
  }

  func showHoverComment(_ comment: PDFComment) {
    guard comment.isTextAnchor, controller?.pendingCommentPage == nil else { return }
    if hoveredCommentID == comment.id { return }
    hideHoverComment()
    hoveredCommentID = comment.id
    let bubble = CommentCalloutView(text: comment.text, draft: false)
    commentCallout = bubble
    addSubview(bubble)
    positionCommentCallout()
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    hideHoverComment()
  }

  func installTextEditor(_ editor: TextBoxEditor) {
    removeTextEditor()
    textEditor = editor
    addSubview(editor)
    hideEditedAnnotation()
    positionTextEditor()
    editor.focus()
  }

  func installContentEditor(_ editor: InlineContentEditor) {
    removeContentEditor()
    contentEditor = editor
    addSubview(editor)
    showContentSelection()
    positionContentEditor()
    editor.focus()
  }

  func removeContentEditor() {
    if let contentEditor {
      window?.makeFirstResponder(self)
      contentEditor.removeFromSuperview()
    }
    contentEditor = nil
  }

  func positionContentEditor() { contentEditor?.position(in: self) }

  private func hideEditedAnnotation() {
    guard let editor = textEditor, let page = document?.page(at: editor.box.page) else { return }
    if let annotation = page.annotations.first(where: {
      ($0.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/LocalPDFID")) as? String)
        == "LocalPDFText:" + editor.box.id
    }) {
      hiddenTextAnnotation = annotation
      annotation.shouldDisplay = false
    }
  }

  func removeTextEditor() {
    hiddenTextAnnotation?.shouldDisplay = true
    hiddenTextAnnotation = nil
    if let textEditor {
      window?.makeFirstResponder(self)
      textEditor.removeFromSuperview()
    }
    textEditor = nil
    setNeedsDisplay(bounds)
  }

  func positionTextEditor() { textEditor?.position(in: self) }
  override func layout() {
    super.layout()
    positionContentEditor()
    positionTextEditor()
    positionCommentCallout()
  }

  func showContentSelection() {
    let selected = contentEditor == nil ? controller?.selectedContent : nil
    let identity = selected.map { "\(displayedRevision):\($0.id)" }
    guard identity != outlinedID else { return }
    if let selectionOutline { selectionOutline.page?.removeAnnotation(selectionOutline) }
    selectionOutline = nil
    outlinedID = identity
    guard let selected, let page = document?.page(at: selected.page) else { return }
    // Outline exists only in the isolated display copy, never in saved content.
    let outline = PDFAnnotation(
      bounds: selected.bounds.insetBy(dx: -3, dy: -3), forType: .square,
      withProperties: nil)
    outline.color = NSColor(calibratedRed: 0.05, green: 0.55, blue: 0.47, alpha: 1)
    let border = PDFBorder()
    border.lineWidth = 1.5
    outline.border = border
    outline.setValue(64, forAnnotationKey: .flags)
    page.addAnnotation(outline)
    selectionOutline = outline
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    hoverMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
      MainActor.assumeIsolated {
        if let self, event.window === self.window { self.updateHoveredComment(for: event) }
      }
      return event
    }
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] event in
      let consumed = MainActor.assumeIsolated {
        guard let self, event.window === self.window, let controller = self.controller else {
          return false
        }
        let point = self.convert(event.locationInWindow, from: nil)
        if let bubble = self.commentCallout, controller.pendingCommentPage != nil {
          if bubble.frame.contains(point) { return false }
          controller.publishComment()
          return self.bounds.contains(point)
        }
        guard self.bounds.contains(point), let page = self.page(for: point, nearest: false) else {
          return false
        }
        if let editor = self.textEditor, editor.hitTest(point) != nil {
          return false
        }
        if let editor = self.contentEditor {
          if editor.hitTest(point) != nil { return false }
          if self.bounds.contains(point) {
            do { try controller.finishContentEditing() } catch {
              controller.error = error.localizedDescription
              return true
            }
          }
        }
        if event.type == .rightMouseDown { return true }
        let pagePoint = self.convert(point, to: page)
        if let index = self.document?.index(for: page),
          controller.tool == .select || controller.tool == .note,
          let comment = controller.workspace.comments(page: index).reversed().first(where: {
            !$0.isTextAnchor && $0.bounds.insetBy(dx: -4, dy: -4).contains(pagePoint)
          })
        {
          controller.selectComment(comment)
          return true
        }
        if controller.workspace.editingRestriction == nil,
          let index = self.document?.index(for: page),
          let box = controller.workspace.textBoxes(page: index).reversed().first(where: {
            $0.bounds.contains(pagePoint)
          }),
          controller.tool == .select || controller.tool == .text
        {
          controller.editTextBox(id: box.id, page: index)
          return true
        }
        do { try controller.finishTextEditing() } catch {
          controller.error = error.localizedDescription
          return true
        }
        if controller.tool != .select {
          controller.place(on: page, at: pagePoint)
          return true
        }
        if let annotation = page.annotation(at: pagePoint), annotation.type != "Link" {
          if annotation.type == "Highlight",
            annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/LocalPDFCommentThread"))
              != nil
          {
            return false
          }
          controller.currentPage = self.document?.index(for: page) ?? 0
          controller.status = annotation.contents ?? "請使用右側註解清單操作"
          return true
        }
        return false
      }
      return consumed ? nil : event
    }
    observer = NotificationCenter.default.addObserver(
      forName: .PDFViewPageChanged, object: self, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, !self.synchronizing, let page = self.currentPage,
          let document = self.document
        else { return }
        if self.textEditor == nil { self.controller?.currentPage = document.index(for: page) }
      }
    }
    for name in [
      Notification.Name.PDFViewScaleChanged, NSView.boundsDidChangeNotification,
      NSView.frameDidChangeNotification,
    ] {
      geometryObservers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] notification in
          let scaleChanged = notification.name == .PDFViewScaleChanged
          let clipID = (notification.object as? NSClipView).map { ObjectIdentifier($0) }
          MainActor.assumeIsolated {
            guard let self else { return }
            let documentClipID = self.documentView?.enclosingScrollView.map {
              ObjectIdentifier($0.contentView)
            }
            if scaleChanged || (clipID != nil && clipID == documentClipID) {
              self.positionTextEditor()
              self.positionContentEditor()
              self.positionCommentCallout()
            }
          }
        })
    }
  }

  required init?(coder: NSCoder) { nil }

  override func menu(for event: NSEvent) -> NSMenu? { nil }

  override func perform(_ action: PDFAction) {
    if action is PDFActionGoTo || action is PDFActionNamed {
      super.perform(action)
    } else if let action = action as? PDFActionURL, let url = action.url,
      ["https", "http"].contains(url.scheme?.lowercased() ?? "")
    {
      let alert = NSAlert()
      alert.messageText = "在瀏覽器開啟連結？"
      alert.informativeText = url.absoluteString
      alert.addButton(withTitle: "開啟")
      alert.addButton(withTitle: "取消")
      if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
    }
  }

  func stopObserving() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
    if let observer { NotificationCenter.default.removeObserver(observer) }
    for observer in geometryObservers { NotificationCenter.default.removeObserver(observer) }
    geometryObservers = []
    if let trackingAreaForComments { removeTrackingArea(trackingAreaForComments) }
    trackingAreaForComments = nil
    commentCallout?.removeFromSuperview()
    commentCallout = nil
    removeTextEditor()
    removeContentEditor()
    monitor = nil
    observer = nil
  }
}

struct WindowBinding: NSViewRepresentable {
  let controller: DocumentController

  func makeNSView(context: Context) -> NSView { NSView() }

  func updateNSView(_ view: NSView, context: Context) {
    Task { @MainActor [weak view] in
      guard let window = view?.window else { return }
      window.delegate = controller
      controller.window = window
    }
  }
}
