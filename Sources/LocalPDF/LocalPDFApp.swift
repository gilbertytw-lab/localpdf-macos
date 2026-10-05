import SwiftUI

@main
struct LocalPDFApp: App {
  @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
  @StateObject private var controller = DocumentController()

  var body: some Scene {
    Window("LocalPDF", id: "main") {
      EditorView(controller: controller, workspace: controller.workspace)
        .frame(minWidth: 1080, minHeight: 700)
        .preferredColorScheme(.light)
        .onAppear {
          applicationDelegate.controller = controller
          controller.startUIFixtureIfRequested()
        }
    }
    .defaultSize(width: 1280, height: 820)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("開啟 PDF…") { controller.openPanel() }.keyboardShortcut("o")
        Button("另存副本…") { controller.savePanel() }.keyboardShortcut("s")
          .disabled(controller.workspace.document == nil)
      }
      CommandGroup(replacing: .undoRedo) {
        Button("復原") { controller.undo() }
          .keyboardShortcut("z").disabled(!controller.canUndo)
        Button("重做") { controller.redo() }
          .keyboardShortcut("z", modifiers: [.command, .shift])
          .disabled(!controller.canRedo)
      }
    }
  }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
  weak var controller: DocumentController?

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    controller?.confirmDiscard() == false ? .terminateCancel : .terminateNow
  }
}
