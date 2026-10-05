import AppKit
import LocalPDFCore
import PDFKit
import SwiftUI

private let ink = Color(red: 0.10, green: 0.18, blue: 0.20)
private let teal = Color(red: 0.05, green: 0.43, blue: 0.39)

struct EditorView: View {
  @ObservedObject var controller: DocumentController
  @ObservedObject var workspace: PDFWorkspace

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      if let document = workspace.document {
        if controller.pageManagerOpen {
          PageManagementView(controller: controller, workspace: workspace, document: document)
        } else {
          HStack(spacing: 0) {
            pageSidebar(document)
            PDFCanvas(controller: controller, document: document, revision: workspace.revision)
            inspector(document)
          }
        }
      } else {
        welcome
      }
      Divider()
      footer
    }
    .background(Color.white)
    .tint(teal)
    .background(WindowBinding(controller: controller))
    .alert(
      "無法完成操作",
      isPresented: Binding(
        get: { controller.error != nil }, set: { if !$0 { controller.error = nil } }
      )
    ) {
      Button("知道了", role: .cancel) { controller.error = nil }
    } message: {
      Text(controller.error ?? "")
    }
  }

  private var header: some View {
    HStack(spacing: 16) {
      HStack(spacing: 10) {
        Image(systemName: "doc.richtext").font(.system(size: 22, weight: .medium)).foregroundStyle(
          teal)
        VStack(alignment: .leading, spacing: 2) {
          Text("LocalPDF").font(.system(size: 17, weight: .semibold)).foregroundStyle(ink)
          Text(workspace.sourceURL?.lastPathComponent ?? "你的本地 PDF 工作台")
            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      Spacer()
      if workspace.document != nil {
        if controller.pageManagerOpen {
          Button {
            controller.closePageManager()
          } label: {
            Label("返回編輯", systemImage: "chevron.left")
          }.buttonStyle(.bordered)
        } else {
          HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜尋文件", text: $controller.searchText).textFieldStyle(.plain)
              .frame(width: 145).onSubmit { controller.search() }
            if !controller.searchResults.isEmpty {
              Button {
                controller.nextSearch()
              } label: {
                Image(systemName: "chevron.down")
              }
              .buttonStyle(.plain).help("下一個搜尋結果")
            }
          }.padding(9).background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
          Button {
            controller.openPageManager()
          } label: {
            Label("頁面管理", systemImage: "square.grid.2x2")
          }.buttonStyle(.bordered)
        }
        Button {
          controller.undo()
        } label: {
          Image(systemName: "arrow.uturn.backward")
        }
        .disabled(!controller.canUndo).help("復原 ⌘Z")
        Button {
          controller.redo()
        } label: {
          Image(systemName: "arrow.uturn.forward")
        }
        .disabled(!controller.canRedo).help("重做 ⇧⌘Z")
      }
      Button("開啟 PDF") { controller.openPanel() }.buttonStyle(.bordered)
      if workspace.document != nil {
        Button {
          controller.savePanel()
        } label: {
          Label("另存副本", systemImage: "square.and.arrow.down")
        }.buttonStyle(.borderedProminent).disabled(workspace.editingRestriction != nil)
      }
    }.padding(.horizontal, 22).padding(.vertical, 14)
  }

  private var welcome: some View {
    HStack(spacing: 60) {
      VStack(alignment: .leading, spacing: 24) {
        Label("MAC 上的離線文件工具", systemImage: "lock.shield")
          .font(.system(size: 11, weight: .semibold)).foregroundStyle(teal)
          .padding(.horizontal, 12).padding(.vertical, 8)
          .background(teal.opacity(0.08), in: Capsule())
        Text("讓 PDF 工作\n簡單一點。")
          .font(.system(size: 46, weight: .semibold, design: .rounded)).foregroundStyle(ink)
          .lineSpacing(8)
        Text("整理頁面、加上文字與註解。\n在你的 Mac 上完成，保留每份原檔。")
          .font(.system(size: 16)).lineSpacing(7).foregroundStyle(.secondary)
        Button {
          controller.openPanel()
        } label: {
          Label("開啟 PDF 開始編輯", systemImage: "folder")
            .font(.system(size: 14, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
        }.buttonStyle(.borderedProminent)
        Text("LocalPDF 0.5 · 開發原型").font(.caption).foregroundStyle(.tertiary)
      }.frame(maxWidth: 430, alignment: .leading)
      VStack(spacing: 16) {
        feature("square.stack.3d.up", "整理文件", "合併、抽取、排序與旋轉頁面")
        feature("textformat", "留下想法", "新增文字、選字註解、圖片與螢光標記")
        feature("arrow.uturn.backward", "安心修改", "復原與另存副本，原始文件保持完整")
      }.frame(width: 330)
    }.padding(50).frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(red: 0.97, green: 0.98, blue: 0.97))
  }

  private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(teal)
        .frame(width: 42, height: 42).background(
          teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 7) {
        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
        Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(.white, in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.05)))
  }

  private func pageSidebar(_ document: PDFDocument) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("頁面").font(.system(size: 13, weight: .semibold))
        Spacer()
        Text("\(workspace.pageCount)").font(.caption).foregroundStyle(.secondary)
      }.padding(16)
      List(selection: $controller.selectedPages) {
        ForEach(0..<document.pageCount, id: \.self) { index in
          VStack(spacing: 7) {
            if let page = document.page(at: index) {
              Image(nsImage: page.thumbnail(of: CGSize(width: 115, height: 152), for: .cropBox))
                .resizable().scaledToFit().frame(width: 115, height: 152)
                .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
            }
            Text("\(index + 1)").font(.system(size: 11, weight: .medium))
          }.padding(.vertical, 9).frame(maxWidth: .infinity).tag(index)
        }
      }.listStyle(.sidebar)
        .onChange(of: controller.selectedPages) { _, selection in
          if let index = selection.sorted().first { controller.go(to: index) }
        }
      Divider()
      Text("批次操作請開啟頁面管理").font(.system(size: 10)).foregroundStyle(.secondary).padding(14)
    }.frame(width: 170).background(Color(red: 0.97, green: 0.98, blue: 0.98))
  }

  private func inspector(_ document: PDFDocument) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("編輯工具").font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
        if let restriction = workspace.editingRestriction {
          Label(restriction, systemImage: "info.circle")
            .font(.caption).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 10) {
          sectionLabel("註解與內容")
          ForEach(EditorTool.allCases) { tool in
            Button {
              if tool == .note {
                controller.beginCommentFromSelection()
              } else {
                controller.tool = tool
              }
              if tool == .image, controller.pendingImage == nil { controller.imagePanel() }
            } label: {
              HStack(spacing: 12) {
                Image(systemName: tool.symbol).frame(width: 18)
                Text(tool.rawValue).font(.system(size: 12, weight: .medium))
                Spacer()
                if controller.tool == tool { Image(systemName: "checkmark").font(.caption) }
              }.padding(11).contentShape(Rectangle())
                .background(
                  controller.tool == tool ? teal.opacity(0.10) : Color.clear,
                  in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
              .foregroundStyle(controller.tool == tool ? teal : ink)
              .disabled(tool != .select && workspace.editingRestriction != nil)
          }
          Button {
            controller.highlightSelection()
          } label: {
            Label("螢光標記選取文字", systemImage: "highlighter").frame(
              maxWidth: .infinity, alignment: .leading)
          }.font(.system(size: 12)).buttonStyle(.bordered).disabled(
            workspace.editingRestriction != nil)
        }
        if controller.tool == .text { textBoxInspector }
        if controller.tool == .note, controller.selectedComment?.isTextAnchor == false {
          commentPanel
        }
        if controller.tool == .image {
          VStack(alignment: .leading, spacing: 8) {
            Button("選擇圖片…") { controller.imagePanel() }
            if let imageName = controller.imageName { Text(imageName).font(.caption).lineLimit(1) }
            Text("在頁面上點一下，放置圖片。")
              .font(.system(size: 11)).foregroundStyle(teal)
          }
        }
        if controller.tool == .content {
          contentInspector
        }
        Divider()
        annotationList(document)
      }.padding(18)
    }.frame(width: 270).background(.white)
  }

  private var commentPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionLabel("註解")
      if let comment = controller.selectedComment {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Label("第 \(comment.page + 1) 頁", systemImage: "mappin")
            Spacer()
            if comment.resolved { Label("已解決", systemImage: "checkmark.circle.fill") }
          }.font(.system(size: 11, weight: .medium)).foregroundStyle(teal)
          HStack {
            Text(comment.author).fontWeight(.semibold)
            Spacer()
            Text(
              comment.createdAt == .distantPast
                ? "" : comment.createdAt.formatted(date: .abbreviated, time: .shortened)
            )
            .foregroundStyle(.secondary)
          }.font(.system(size: 10))
          if controller.commentEditing {
            commentEditor($controller.commentDraft, placeholder: "修改註解…")
            HStack {
              Button("取消") {
                controller.commentEditing = false
                controller.commentDraft = ""
              }
              Spacer()
              Button("儲存修改") { controller.saveCommentEdit() }
                .disabled(
                  controller.commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.font(.system(size: 11))
          } else {
            Text(comment.text).font(.system(size: 12)).textSelection(.enabled)
            Button("編輯") {
              controller.commentDraft = comment.text
              controller.commentEditing = true
            }.font(.system(size: 11))
          }
          ForEach(comment.replies) { reply in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(reply.author).fontWeight(.semibold)
                Spacer()
                Text(reply.createdAt.formatted(date: .abbreviated, time: .shortened))
                  .foregroundStyle(.secondary)
              }.font(.system(size: 10))
              if controller.editingReplyID == reply.id {
                commentEditor($controller.editingReplyDraft, placeholder: "修改回覆…")
                HStack {
                  Button("取消") {
                    controller.editingReplyID = nil
                    controller.editingReplyDraft = ""
                  }
                  Spacer()
                  Button("儲存") { controller.saveReplyEdit() }
                    .disabled(
                      controller.editingReplyDraft.trimmingCharacters(
                        in: .whitespacesAndNewlines
                      ).isEmpty)
                }.font(.system(size: 10))
              } else {
                Text(reply.text).font(.system(size: 12)).textSelection(.enabled)
                HStack {
                  Button("編輯") {
                    controller.editingReplyID = reply.id
                    controller.editingReplyDraft = reply.text
                  }
                  Spacer()
                  Button("刪除", role: .destructive) { controller.deleteReply(reply.id) }
                }.font(.system(size: 10))
              }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
          }
          if !comment.resolved {
            commentEditor($controller.replyDraft, placeholder: "撰寫回覆…")
            Button("發布回覆") { controller.replyToComment() }
              .disabled(
                controller.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          Divider()
          HStack {
            Button(comment.resolved ? "重新開啟" : "標記為解決") {
              controller.toggleCommentResolved()
            }
            Spacer()
            Button("刪除", role: .destructive) { controller.deleteSelectedComment() }
          }.font(.system(size: 11))
        }.padding(11).background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
      } else {
        Text("先選取 PDF 文字，再按「新增註解」。")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      let comments = (0..<workspace.pageCount).flatMap { workspace.comments(page: $0) }
      if !comments.isEmpty {
        Divider()
        sectionLabel("所有註解 · \(comments.count)")
        ForEach(comments) { comment in
          Button {
            controller.selectComment(comment)
          } label: {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: comment.resolved ? "checkmark.circle" : "text.bubble")
                .foregroundStyle(teal)
              VStack(alignment: .leading, spacing: 3) {
                Text("第 \(comment.page + 1) 頁 · \(comment.author)")
                  .font(.system(size: 10, weight: .semibold))
                Text(comment.text).font(.system(size: 11)).lineLimit(2)
              }
              Spacer(minLength: 0)
            }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
              .background(
                controller.selectedCommentID == comment.id
                  ? teal.opacity(0.10) : Color.gray.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 7))
          }.buttonStyle(.plain)
        }
      }
    }.disabled(workspace.editingRestriction != nil)
  }

  private func commentEditor(_ text: Binding<String>, placeholder: String) -> some View {
    ZStack(alignment: .topLeading) {
      if text.wrappedValue.isEmpty {
        Text(placeholder).font(.system(size: 12)).foregroundStyle(.tertiary)
          .padding(.leading, 9).padding(.top, 8)
      }
      TextEditor(text: text).font(.system(size: 12)).frame(height: 72)
        .scrollContentBackground(.hidden)
    }.padding(2).background(Color.white, in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.25)))
  }

  private func annotationList(_ document: PDFDocument) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionLabel("第 \(controller.currentPage + 1) 頁其他註解")
      let annotations =
        document.page(at: controller.currentPage)?.annotations.filter {
          $0.type != "Text" && $0.type != "Popup"
            && !($0.type == "Highlight"
              && $0.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/LocalPDFCommentThread"))
                != nil)
        } ?? []
      if annotations.isEmpty {
        Text("這一頁沒有其他註解。")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      ForEach(annotations, id: \.self) { annotation in
        HStack(alignment: .top, spacing: 6) {
          Text(annotation.contents ?? annotation.type ?? "註解")
            .font(.system(size: 11)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
          Button {
            controller.deleteAnnotation(annotation, page: controller.currentPage)
          } label: {
            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
          }
          .buttonStyle(.plain).help("刪除此註解").disabled(workspace.editingRestriction != nil)
        }.padding(10).background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
      }
    }
  }

  private var textBoxInspector: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionLabel("文字框格式")
      Picker(
        "字體",
        selection: Binding(
          get: { controller.textFormat.family },
          set: { value in controller.applyTextFormat(.family) { $0.family = value } })
      ) {
        ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in
          Text(family).tag(family)
        }
      }.font(.caption)
      HStack {
        Text("字級").font(.caption)
        TextField(
          "pt",
          value: Binding(
            get: { controller.textFormat.size },
            set: { value in controller.applyTextFormat(.size) { $0.size = min(144, max(6, value)) }
            }), format: .number.precision(.fractionLength(0...1))
        )
        .textFieldStyle(.roundedBorder).frame(width: 60).accessibilityLabel("文字大小")
        Text("pt").font(.caption).foregroundStyle(.secondary)
        Stepper(
          "",
          value: Binding(
            get: { controller.textFormat.size },
            set: { value in controller.applyTextFormat(.size) { $0.size = value } }), in: 6...144
        ).labelsHidden()
      }
      ColorPicker(
        "文字顏色",
        selection: Binding(
          get: { Color(nsColor: controller.textFormat.color) },
          set: { value in controller.applyTextFormat(.color) { $0.color = NSColor(value) } }),
        supportsOpacity: false
      ).font(.caption)
      HStack(spacing: 8) {
        let colors: [(String, NSColor)] = [
          ("黑色", .black), ("紅色", .systemRed), ("橙色", .systemOrange), ("綠色", .systemGreen),
          ("藍色", .systemBlue), ("紫色", .systemPurple), ("灰色", .gray),
        ]
        ForEach(Array(colors.enumerated()), id: \.offset) { _, choice in
          Button {
            controller.applyTextFormat(.color) { $0.color = choice.1 }
          } label: {
            Circle().fill(Color(nsColor: choice.1)).frame(width: 18, height: 18)
              .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
          }.buttonStyle(.plain).help(choice.0).accessibilityLabel(choice.0)
        }
      }
      HStack(spacing: 8) {
        formatButton("bold", "粗體", active: controller.textFormat.bold) {
          controller.applyTextFormat(.bold) { $0.bold.toggle() }
        }
        formatButton("italic", "斜體", active: controller.textFormat.italic) {
          controller.applyTextFormat(.italic) { $0.italic.toggle() }
        }
        formatButton("underline", "底線", active: controller.textFormat.underline) {
          controller.applyTextFormat(.underline) { $0.underline.toggle() }
        }
        Spacer()
      }
      HStack(spacing: 8) {
        formatButton("text.alignleft", "靠左對齊", active: controller.textFormat.alignment == .left) {
          controller.applyTextFormat(.alignment) { $0.alignment = .left }
        }
        formatButton("text.aligncenter", "置中", active: controller.textFormat.alignment == .center) {
          controller.applyTextFormat(.alignment) { $0.alignment = .center }
        }
        formatButton("text.alignright", "靠右對齊", active: controller.textFormat.alignment == .right) {
          controller.applyTextFormat(.alignment) { $0.alignment = .right }
        }
      }
      Text("在頁面點一下開始輸入。選字後調整格式；沒有選字時套用整框。")
        .font(.system(size: 11)).foregroundStyle(.secondary)
      if controller.editingText {
        Text("拖曳上方把手移動，右下角調整大小。")
          .font(.system(size: 11)).foregroundStyle(teal)
        HStack {
          Button("完成") { controller.completeTextEditing() }.buttonStyle(.borderedProminent)
          Button("取消") { controller.cancelTextEditing() }
          Button {
            controller.deleteTextBox()
          } label: {
            Image(systemName: "trash")
          }.help("刪除文字框")
        }.buttonStyle(.bordered)
      }
    }
  }

  private func formatButton(
    _ symbol: String, _ label: String, active: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) { Image(systemName: symbol).frame(width: 25, height: 25) }
      .buttonStyle(.plain).background(
        active ? teal.opacity(0.15) : Color.gray.opacity(0.07),
        in: RoundedRectangle(cornerRadius: 5)
      )
      .foregroundStyle(active ? teal : ink).help(label).accessibilityLabel(label)
      .accessibilityAddTraits(active ? .isSelected : [])
  }

  private var contentInspector: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionLabel("第 \(controller.currentPage + 1) 頁原有內容")
      Text("點選頁面文字直接編輯，或從清單選取。每次修改一個 PDF 物件。")
        .font(.system(size: 11)).foregroundStyle(.secondary)
      Text("編輯此頁會將文字與線條色彩轉為 RGB，原有印刷色彩描述不會保留。")
        .font(.system(size: 10)).foregroundStyle(.secondary)
      if let item = controller.selectedContent {
        if let restriction = item.restriction {
          Text(restriction).font(.caption).foregroundStyle(.secondary)
        } else {
          if item.kind == .text {
            Text("文字已在頁面原位置開啟。按 Enter 套用、Esc 取消，或點選頁面其他位置套用。")
              .font(.system(size: 11)).foregroundStyle(.secondary)
            Picker("字型", selection: $controller.replacementFont) {
              ForEach(PDFContentFont.allCases) { font in
                Text(font.rawValue).tag(font)
              }
            }.font(.caption)
            Text(
              controller.replacementFont == .original
                ? "保留原字型可使用這段原文已有的字元。"
                : "可輸入英文、數字與基本標點；使用 Helvetica 字型。"
            )
            .font(.system(size: 10)).foregroundStyle(.secondary)
            if controller.contentEditor != nil {
              HStack {
                Button("完成") { controller.completeContentEditing() }
                Button("取消") { controller.cancelContentEditing() }
              }
            }
          } else if item.kind == .image {
            Text("替換後沿用原圖的位置與大小。")
              .font(.system(size: 11)).foregroundStyle(.secondary)
            Button("替換原有圖片…") { controller.replaceContentImagePanel() }
          }
          Button("刪除此內容", role: .destructive) { controller.deleteContent() }
        }
      }
      DisclosureGroup("物件清單（\(controller.contentItems.count)）") {
        if controller.contentItems.isEmpty {
          Text("沒有可辨識的頂層文字或圖片。掃描頁面可能只有一張圖片。")
            .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(Array(controller.contentItems.prefix(200))) { item in
          Button {
            controller.selectContent(item)
          } label: {
            HStack(alignment: .top, spacing: 7) {
              Image(
                systemName: item.kind == .text
                  ? "textformat" : item.kind == .image ? "photo" : "square.stack")
              Text(
                item.kind == .text
                  ? item.text
                  : item.kind == .image ? "圖片 \(item.object + 1)" : "群組 \(item.object + 1)"
              )
              .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
              if item.restriction != nil { Image(systemName: "lock") }
            }.font(.system(size: 11)).padding(7)
              .background(
                controller.selectedContent?.id == item.id
                  ? teal.opacity(0.1) : Color.gray.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 5))
          }.buttonStyle(.plain)
        }
        if controller.contentItems.count > 200 {
          Text("清單顯示前 200 個物件；其他物件可在頁面點選。")
            .font(.caption).foregroundStyle(.secondary)
        }
      }.font(.system(size: 11))
    }.buttonStyle(.bordered)
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Circle().fill(
        (workspace.isDirty || controller.hasTextDraft || controller.hasContentDraft)
          ? Color.orange : teal
      ).frame(
        width: 5, height: 5)
      Text(
        (workspace.isDirty || controller.hasTextDraft || controller.hasContentDraft)
          ? "有未儲存變更" : "本地工作台"
      ).font(
        .system(size: 10, weight: .medium))
      Text("· \(controller.status)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(
        1)
      Spacer()
      if workspace.document != nil {
        if controller.pageManagerOpen {
          Text("\(workspace.pageCount) 頁 · 已選 \(controller.selectedPages.count) 頁")
            .font(.system(size: 10)).foregroundStyle(.secondary)
        } else {
          Text("第 \(controller.currentPage + 1)／\(workspace.pageCount) 頁")
            .font(.system(size: 10)).foregroundStyle(.secondary)
          Button {
            controller.pdfView?.zoomOut(nil)
          } label: {
            Image(systemName: "minus.magnifyingglass")
          }
          Button("符合視窗") { controller.pdfView?.autoScales = true }
          Button {
            controller.pdfView?.zoomIn(nil)
          } label: {
            Image(systemName: "plus.magnifyingglass")
          }
        }
      }
    }.buttonStyle(.plain).padding(.horizontal, 18).frame(height: 32)
  }
}
