import SiglaunchCore
import SwiftUI

@main
@MainActor
struct SiglaunchApplication: App {
  @StateObject private var runtime = AppRuntime()

  var body: some Scene {
    MenuBarExtra {
      SiglaunchMenu(
        presentation: runtime.menuPresentation,
        primaryWorkflowPresentation: runtime.primaryWorkflowPresentation,
        poseDatasetImportPresentation: runtime.poseDatasetImportPresentation,
        onPauseMonitoring: runtime.pauseMonitoring,
        onResumeMonitoring: runtime.resumeMonitoring,
        onImportPoseDataset: runtime.importPoseDataset,
        onQuit: { runtime.send(.quitRequested) }
      )
    } label: {
      Label("Siglaunch", systemImage: runtime.menuBarSymbol)
    }
    .menuBarExtraStyle(.menu)
  }
}
