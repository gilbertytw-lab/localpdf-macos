import AppKit
import LocalPDFCore
import PDFKit
import SwiftUI

private let pageInk = Color(red: 0.10, green: 0.18, blue: 0.20)
private let pageTeal = Color(red: 0.05, green: 0.43, blue: 0.39)

struct PageManagementView: View {
  @ObservedObject var controller: DocumentController
  @ObservedObject var workspace: PDFWorkspace
  let document: PDFDocument

  @State private var selectionAnchor: Int?
  @StateObject private var dragState = PageDragState()

  var body: some View {
    VStack(spacing: 0) {
      controls
      Divider()
      GeometryReader { geometry in
        ScrollView {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190, maximum: 235), spacing: 22)],
            spacing: 26
          ) {
            ForEach(0..<document.pageCount, id: \.self) { index in
              if let page = document.page(at: index) { pageCard(page, index: index) }
            }
          }
          .padding(.horizontal, 34).padding(.vertical, 28)
          .frame(minWidth: geometry.size.width)
        }
      }
    }
    .background(Color(red: 0.96, green: 0.97, blue: 0.97))
    .overlay { PageDragPreviewHost(dragState: dragState).allowsHitTesting(false) }
    .onChange(of: workspace.revision) { _, _ in selectionAnchor = nil }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text("頁面管理").font(.system(size: 24, weight: .semibold)).foregroundStyle(pageInk)
          Text("\(workspace.pageCount) 頁 · 已選 \(controller.selectedPages.count) 頁")
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Spacer()
        Button("全選") {
          controller.selectedPages = Set(0..<workspace.pageCount)
          selectionAnchor = nil
        }
        Button("取消選取") {
          controller.selectedPages = []
          selectionAnchor = nil
        }
        .disabled(controller.selectedPages.isEmpty)
      }
      HStack(spacing: 10) {
        Button {
          controller.rotateSelectedPages()
        } label: {
          Label("旋轉", systemImage: "rotate.right")
        }
        .disabled(controller.selectedPages.isEmpty)
        Button {
          controller.savePanel(extract: true)
        } label: {
          Label("抽取", systemImage: "square.and.arrow.up")
        }
        .disabled(controller.selectedPages.isEmpty)
        Button {
          controller.mergePanel()
        } label: {
          Label("合併 PDF…", systemImage: "plus.rectangle.on.rectangle")
        }
        Spacer()
        Text("⌘ 點選多頁 · Shift 選取範圍 · 拖曳調整順序")
          .font(.system(size: 11)).foregroundStyle(.secondary)
        Button(role: .destructive) {
          controller.deleteSelectedPages()
        } label: {
          Label("刪除選取頁面", systemImage: "trash")
        }
        .disabled(
          controller.selectedPages.isEmpty || controller.selectedPages.count >= workspace.pageCount)
      }
      .buttonStyle(.bordered)
      .disabled(workspace.editingRestriction != nil)
    }
    .padding(.horizontal, 34).padding(.vertical, 22)
    .background(.white)
  }

  private func pageCard(_ page: PDFPage, index: Int) -> some View {
    let selected = controller.selectedPages.contains(index)
    let targeted = dragState.hoveredTarget == index
    let movingForward = (dragState.draggedPages.first ?? index) < index
    let thumbnail = page.thumbnail(of: CGSize(width: 270, height: 350), for: .cropBox)
    return VStack(spacing: 12) {
      Image(nsImage: thumbnail)
        .resizable().scaledToFit()
        .frame(maxWidth: .infinity).frame(height: 215)
        .shadow(color: .black.opacity(0.13), radius: 5, y: 3)
      HStack {
        Text("第 \(index + 1) 頁")
          .font(.system(size: 13, weight: selected ? .semibold : .medium))
        Spacer()
        if page.rotation != 0 {
          Text("\(page.rotation)°").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(pageTeal) }
      }
      .foregroundStyle(pageInk)
    }
    .padding(14)
    .background(.white, in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          targeted || selected ? pageTeal : Color.black.opacity(0.08),
          lineWidth: targeted ? 3 : selected ? 2 : 1)
    }
    .overlay(alignment: movingForward ? .trailing : .leading) {
      if targeted { Capsule().fill(pageTeal).frame(width: 5).padding(.vertical, 6) }
    }
    .contentShape(RoundedRectangle(cornerRadius: 12))
    .overlay {
      PageCardInteraction(
        index: index, selected: selected, previewImage: thumbnail, controller: controller,
        dragState: dragState,
        onSelect: select)
    }
  }

  private func select(_ index: Int, modifiers: NSEvent.ModifierFlags) {
    if modifiers.contains(.shift), let selectionAnchor {
      controller.selectedPages = Set(min(selectionAnchor, index)...max(selectionAnchor, index))
    } else if modifiers.contains(.command) {
      if controller.selectedPages.contains(index) {
        controller.selectedPages.remove(index)
      } else {
        controller.selectedPages.insert(index)
      }
      selectionAnchor = index
    } else {
      controller.selectedPages = [index]
      selectionAnchor = index
    }
  }
}
