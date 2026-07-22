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
        recognitionDiagnostics: runtime.recognitionDiagnostics,
        primaryWorkflowPresentation: runtime.primaryWorkflowPresentation,
        poseDatasetImportPresentation: runtime.poseDatasetImportPresentation,
        recognizerTrainingPresentation: runtime.recognizerTrainingPresentation,
        onPauseMonitoring: runtime.pauseMonitoring,
        onResumeMonitoring: runtime.resumeMonitoring,
        onRecognitionFrameRateChange: { frameRate in
          Task { @MainActor in
            runtime.selectRecognitionFrameRate(frameRate)
          }
        },
        onImportPoseDataset: runtime.importPoseDataset,
        onStartRecognizerTraining: runtime.startRecognizerTraining,
        onCancelRecognizerTraining: runtime.cancelRecognizerTraining,
        onQuit: { runtime.send(.quitRequested) }
      )
    } label: {
      Label("Siglaunch", systemImage: runtime.menuBarSymbol)
    }
    .menuBarExtraStyle(.menu)
  }
}
