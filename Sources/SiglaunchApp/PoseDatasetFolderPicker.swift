import AppKit
import SiglaunchCore

@MainActor
protocol PoseDatasetFolderSelecting {
  func selectFolder() -> PoseDatasetFolderSelectionResult
}

@MainActor
final class SystemPoseDatasetFolderPicker: PoseDatasetFolderSelecting {
  func selectFolder() -> PoseDatasetFolderSelectionResult {
    let panel = NSOpenPanel()
    panel.title = "Choose Pose Dataset"
    panel.prompt = "Choose"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.resolvesAliases = true

    guard panel.runModal() == .OK, let selectedURL = panel.url else {
      return .cancelled
    }
    return .selected(path: selectedURL.standardizedFileURL.path)
  }
}
