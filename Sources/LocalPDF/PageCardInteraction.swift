import AppKit
import SwiftUI

@MainActor
final class PageDragState: ObservableObject {
  @Published var hoveredTarget: Int?
  var draggedPages: [Int] = []
  private var views: [Int: WeakPageSurface] = [:]
  private weak var previewView: PageDragPreviewSurface?
  private var previewImage: NSImage?
  private var previewPoint: NSPoint?

  func attachPreview(_ view: PageDragPreviewSurface) {
    previewView = view
    if let previewImage, let previewPoint {
      view.show(image: previewImage, count: draggedPages.count, at: previewPoint)
    }
  }

  func detachPreview(_ view: PageDragPreviewSurface) {
    if previewView === view { previewView = nil }
  }

  func register(_ view: PageCardSurface) { views[view.index] = WeakPageSurface(view) }

  func unregister(_ view: PageCardSurface) {
    if views[view.index]?.view === view { views[view.index] = nil }
  }

  func target(at windowPoint: NSPoint) -> Int? {
    views.keys.sorted().first { index in
      guard let view = views[index]?.view, !draggedPages.contains(index) else { return false }
      return view.bounds.contains(view.convert(windowPoint, from: nil))
    }
  }

  func start(pages: [Int], image: NSImage, at windowPoint: NSPoint) {
    draggedPages = pages
    previewImage = image
    previewPoint = windowPoint
    previewView?.show(image: image, count: pages.count, at: windowPoint)
  }

  func move(to windowPoint: NSPoint) {
    previewPoint = windowPoint
    previewView?.move(to: windowPoint)
    let nextTarget = target(at: windowPoint)
    if hoveredTarget != nextTarget { hoveredTarget = nextTarget }
  }

  func clear() {
    draggedPages = []
    hoveredTarget = nil
    previewImage = nil
    previewPoint = nil
    previewView?.hide()
  }
}

@MainActor
private final class WeakPageSurface {
  weak var view: PageCardSurface?
  init(_ view: PageCardSurface) { self.view = view }
}

struct PageCardInteraction: NSViewRepresentable {
  let index: Int
  let selected: Bool
  let previewImage: NSImage
  let controller: DocumentController
  let dragState: PageDragState
  let onSelect: (Int, NSEvent.ModifierFlags) -> Void

  func makeNSView(context: Context) -> PageCardSurface {
    let view = PageCardSurface()
    configure(view)
    return view
  }

  func updateNSView(_ view: PageCardSurface, context: Context) { configure(view) }

  private func configure(_ view: PageCardSurface) {
    view.index = index
    view.selected = selected
    view.previewImage = previewImage
    view.controller = controller
    view.dragState = dragState
    view.onSelect = onSelect
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.button)
    view.setAccessibilityLabel("第 \(index + 1) 頁\(selected ? "，已選取" : "")")
    if view.window != nil { dragState.register(view) }
  }

  static func dismantleNSView(_ view: PageCardSurface, coordinator: ()) {
    view.dragState?.unregister(view)
  }
}

@MainActor
final class PageCardSurface: NSView {
  var index = 0
  var selected = false
  var previewImage: NSImage?
  weak var controller: DocumentController?
  weak var dragState: PageDragState?
  var onSelect: ((Int, NSEvent.ModifierFlags) -> Void)?
  private var mouseDownPoint: NSPoint?
  private var dragging = false

  override var acceptsFirstResponder: Bool { true }

  override func accessibilityPerformPress() -> Bool {
    onSelect?(index, [])
    return true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil { dragState?.unregister(self) } else { dragState?.register(self) }
  }

  override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    mouseDownPoint = event.locationInWindow
    dragging = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard let mouseDownPoint, let dragState, let controller else { return }
    if !dragging {
      guard
        hypot(
          event.locationInWindow.x - mouseDownPoint.x,
          event.locationInWindow.y - mouseDownPoint.y) > 5
      else { return }
      dragging = true
      guard let previewImage else { return }
      dragState.start(
        pages: selected ? controller.selectedPages.sorted() : [index],
        image: previewImage, at: event.locationInWindow)
      if !selected { controller.selectedPages = [index] }
    }
    dragState.move(to: event.locationInWindow)
  }

  override func mouseUp(with event: NSEvent) {
    guard mouseDownPoint != nil else { return }
    defer {
      mouseDownPoint = nil
      dragging = false
      dragState?.clear()
    }
    if dragging, let dragState, let target = dragState.target(at: event.locationInWindow) {
      controller?.moveManagedPages(dragState.draggedPages, onto: target)
    } else if !dragging {
      onSelect?(index, event.modifierFlags)
    }
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53, dragging {
      mouseDownPoint = nil
      dragging = false
      dragState?.clear()
    } else if event.keyCode == 36 || event.keyCode == 49 {
      onSelect?(index, event.modifierFlags)
    } else {
      super.keyDown(with: event)
    }
  }
}

struct PageDragPreviewHost: NSViewRepresentable {
  let dragState: PageDragState

  func makeNSView(context: Context) -> PageDragPreviewSurface {
    let view = PageDragPreviewSurface()
    dragState.attachPreview(view)
    return view
  }

  func updateNSView(_ view: PageDragPreviewSurface, context: Context) {
    dragState.attachPreview(view)
  }

  static func dismantleNSView(_ view: PageDragPreviewSurface, coordinator: ()) {
    view.hide()
  }
}

@MainActor
final class PageDragPreviewSurface: NSView {
  private let backing = NSView()
  private let front = NSView()
  private let thumbnail = NSImageView()
  private let countLabel = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    for page in [backing, front] {
      page.wantsLayer = true
      page.layer?.backgroundColor = NSColor.white.cgColor
      page.layer?.cornerRadius = 8
      page.layer?.shadowColor = NSColor.black.cgColor
      page.layer?.shadowOpacity = 0.20
      page.layer?.shadowRadius = 8
      page.layer?.shadowOffset = CGSize(width: 0, height: -4)
      page.isHidden = true
      addSubview(page)
    }
    thumbnail.imageScaling = .scaleProportionallyUpOrDown
    front.addSubview(thumbnail)
    countLabel.font = .boldSystemFont(ofSize: 14)
    countLabel.textColor = .systemRed
    countLabel.alignment = .center
    countLabel.wantsLayer = true
    countLabel.layer?.backgroundColor = NSColor.white.cgColor
    countLabel.layer?.cornerRadius = 8
    countLabel.layer?.shadowColor = NSColor.black.cgColor
    countLabel.layer?.shadowOpacity = 0.12
    countLabel.layer?.shadowRadius = 4
    countLabel.layer?.shadowOffset = CGSize(width: 0, height: -2)
    countLabel.isHidden = true
    addSubview(countLabel)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func show(image: NSImage, count: Int, at windowPoint: NSPoint) {
    thumbnail.image = image
    countLabel.stringValue = "\(count) 頁"
    backing.isHidden = count < 2
    front.isHidden = false
    countLabel.isHidden = count < 2
    move(to: windowPoint)
  }

  func move(to windowPoint: NSPoint) {
    let point = convert(windowPoint, from: nil)
    let x = min(max(8, point.x + 14), max(8, bounds.maxX - 122))
    let y = min(max(8, point.y - 144), max(8, bounds.maxY - 160))
    front.frame = NSRect(x: x, y: y, width: 108, height: 148)
    thumbnail.frame = front.bounds.insetBy(dx: 5, dy: 5)
    backing.frame = front.frame.offsetBy(dx: 7, dy: -7)
    countLabel.frame = NSRect(
      x: min(max(8, point.x + 24), max(8, bounds.maxX - 64)),
      y: min(max(8, point.y + 14), max(8, bounds.maxY - 30)), width: 56, height: 24)
  }

  func hide() {
    thumbnail.image = nil
    backing.isHidden = true
    front.isHidden = true
    countLabel.isHidden = true
  }
}
