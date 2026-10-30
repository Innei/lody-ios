import AppKit
import ChatKitCore
import Quartz

extension MacSessionController: @preconcurrency QLPreviewPanelDataSource {
  func preview(_ media: CKMediaRef) {
    guard let provider = transcriptMedia else { return }
    Task { [weak self] in
      do {
        let url = try await provider.fileURL(for: media)
        guard let self else { return }
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
          panel.reloadData()
        } else {
          panel.makeKeyAndOrderFront(nil)
        }
      } catch {
        MacToast.show(error.localizedDescription, kind: "error", in: self?.view.window)
      }
    }
  }

  override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
    MainActor.assumeIsolated { previewURL != nil }
  }

  override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated { panel.dataSource = self }
  }

  override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated { panel.dataSource = nil }
  }

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
    previewURL as NSURL?
  }
}
