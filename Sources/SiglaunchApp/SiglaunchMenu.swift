import Foundation
import SiglaunchCore
import SwiftUI

struct SiglaunchMenu: View {
  let presentation: MenuPresentation?
  let recognitionDiagnostics: RecognitionDiagnostics?
  let primaryWorkflowPresentation: PrimaryWorkflowPresentation?
  let poseDatasetImportPresentation: PoseDatasetImportPresentation?
  let recognizerTrainingPresentation: RecognizerTrainingPresentation?
  let onPauseMonitoring: () -> Void
  let onResumeMonitoring: () -> Void
  let onRecognitionFrameRateChange: @Sendable (RecognitionFrameRate) -> Void
  let onImportPoseDataset: () -> Void
  let onStartRecognizerTraining: () -> Void
  let onCancelRecognizerTraining: () -> Void
  let onQuit: () -> Void

  var body: some View {
    if let content = recognizerTrainingPresentation?.content,
      recognizerTrainingPresentation?.isInProgress == true
    {
      Label(content.title, systemImage: content.symbolName)
      if let detail = content.detail {
        Text(detail)
      }
    } else if let content = presentation?.content {
      Label(content.title, systemImage: content.symbolName)
      if let detail = content.detail {
        Text(detail)
      }
    } else {
      Label("Checking Personal Recognizer", systemImage: "viewfinder.circle")
    }

    if let recognitionDiagnostics {
      Divider()
      Picker(
        "Recognition Frame Rate",
        selection: Binding(
          get: { recognitionDiagnostics.targetFrameRate },
          set: onRecognitionFrameRateChange
        )
      ) {
        Text("10 FPS").tag(RecognitionFrameRate.fps10)
        Text("15 FPS").tag(RecognitionFrameRate.fps15)
        Text("30 FPS").tag(RecognitionFrameRate.fps30)
      }
      .disabled(presentation != .activeMonitoring)
      let content = recognitionDiagnostics.content
      Label(content.title, systemImage: content.symbolName)
      if let detail = content.detail {
        Text(detail)
      }
      if let handDetail = recognitionDiagnostics.handDetail {
        Text(handDetail)
      }
    }

    if let content = primaryWorkflowPresentation?.content {
      Divider()
      Label(content.title, systemImage: content.symbolName)
      if let detail = content.detail {
        Text(detail)
      }
    }

    if recognizerTrainingPresentation?.isInProgress != true,
      let content = poseDatasetImportPresentation?.content
    {
      Divider()
      Label(content.title, systemImage: content.symbolName)
      if let detail = content.detail {
        Text(detail)
      }
    }

    if let content = recognizerTrainingPresentation?.content,
      recognizerTrainingPresentation?.isInProgress != true
    {
      Divider()
      Label(content.title, systemImage: content.symbolName)
      if let detail = content.detail {
        Text(detail)
      }
    }

    Divider()

    if recognizerTrainingPresentation?.isInProgress != true {
      switch presentation {
      case .activeMonitoring, .awaitingCameraAuthorization, .captureInterrupted,
        .cameraUnavailable:
        Button(action: onPauseMonitoring) {
          Label("Pause Monitoring", systemImage: "pause.fill")
        }
      case .pausedMonitoring:
        Button(action: onResumeMonitoring) {
          Label("Resume Monitoring", systemImage: "play.fill")
        }
      default:
        EmptyView()
      }
    }

    if canImportPoseDataset {
      Button(action: onImportPoseDataset) {
        Label("Import Pose Dataset", systemImage: "folder.badge.plus")
      }
      .disabled(
        poseDatasetImportPresentation?.isInProgress == true
          || recognizerTrainingPresentation?.isInProgress == true
      )
    }

    if hasReadyTrainingInput {
      Button(action: onStartRecognizerTraining) {
        Label("Train Personal Recognizer", systemImage: "cpu")
      }
      .disabled(recognizerTrainingPresentation?.isInProgress == true)
    }

    if recognizerTrainingPresentation?.isCancellable == true {
      Button(action: onCancelRecognizerTraining) {
        Label("Cancel Training", systemImage: "xmark.circle")
      }
    }

    Button(action: onQuit) {
      Label("Quit Siglaunch", systemImage: "power")
    }
    .keyboardShortcut("q")
  }

  private var canImportPoseDataset: Bool {
    switch presentation {
    case .activeMonitoring, .pausedMonitoring, .setupRequired:
      true
    default:
      false
    }
  }

  private var hasReadyTrainingInput: Bool {
    if case .ready = poseDatasetImportPresentation {
      return true
    }
    return false
  }
}

struct MenuStatusContent {
  let title: String
  let symbolName: String
  let detail: String?
}

extension DomainExpansionCandidateProgress {
  var symbolName: String {
    switch poseMatchCount {
    case 1:
      "1.circle.fill"
    case 2:
      "2.circle.fill"
    default:
      "viewfinder.circle"
    }
  }
}

extension RecognitionDiagnostics {
  var content: MenuStatusContent {
    MenuStatusContent(
      title: "Recognition Diagnostics",
      symbolName: diagnosticGesture?.isOpenPalm == true
        ? "hand.raised.fill"
        : "speedometer",
      detail: [
        "Target: \(targetFrameRate.rawValue) FPS",
        "Capture: \(captureFramesPerSecond.map(formatFPS) ?? "pending")",
        "Completed: \(formatFPS(completedRecognitionFramesPerSecond))",
      ].joined(separator: " | ")
    )
  }

  var handDetail: String? {
    guard let diagnosticGesture else { return nil }
    return [
      "Hand: \(diagnosticGesture.handDetection.menuDescription)",
      "Joints: \(diagnosticGesture.recognizedJointCount)",
      "Extended: \(diagnosticGesture.extendedFingerCount)",
      "Open palm: \(diagnosticGesture.isOpenPalm ? "yes" : "no")",
    ].joined(separator: " | ")
  }

  private func formatFPS(_ value: Double) -> String {
    let rounded = value.rounded()
    if abs(value - rounded) < 0.05 {
      return "\(Int(rounded)) FPS"
    }
    return String(format: "%.1f FPS", value)
  }
}

extension DiagnosticHandDetection {
  fileprivate var menuDescription: String {
    switch self {
    case .detected:
      "detected"
    case .notDetected:
      "not detected"
    case .analysisFailed:
      "analysis failed"
    }
  }
}

private struct RecognizerTrainingMenuDescriptor {
  let content: MenuStatusContent
  let isInProgress: Bool
  let isCancellable: Bool

  init(
    title: String,
    symbolName: String,
    detail: String? = nil,
    isInProgress: Bool,
    isCancellable: Bool = false
  ) {
    content = MenuStatusContent(
      title: title,
      symbolName: symbolName,
      detail: detail
    )
    self.isInProgress = isInProgress
    self.isCancellable = isCancellable
  }
}

extension RecognizerTrainingPresentation {
  var isInProgress: Bool { menuDescriptor.isInProgress }

  var isCancellable: Bool { menuDescriptor.isCancellable }

  var content: MenuStatusContent { menuDescriptor.content }

  private var menuDescriptor: RecognizerTrainingMenuDescriptor {
    switch self {
    case .preparing:
      RecognizerTrainingMenuDescriptor(
        title: "Preparing Recognizer Training",
        symbolName: "video.slash",
        detail: "Releasing the camera.",
        isInProgress: true,
        isCancellable: true
      )
    case .training(let progress):
      RecognizerTrainingMenuDescriptor(
        title: "Training Personal Recognizer",
        symbolName: "cpu",
        detail: progress.map {
          "\(Int(($0.fractionCompleted * 100).rounded()))% complete"
        },
        isInProgress: true,
        isCancellable: true
      )
    case .cancelling:
      RecognizerTrainingMenuDescriptor(
        title: "Cancelling Recognizer Training",
        symbolName: "xmark.circle",
        isInProgress: true
      )
    case .saving:
      RecognizerTrainingMenuDescriptor(
        title: "Saving Personal Recognizer",
        symbolName: "square.and.arrow.down",
        isInProgress: true
      )
    case .replacing:
      RecognizerTrainingMenuDescriptor(
        title: "Enabling Personal Recognizer",
        symbolName: "arrow.triangle.2.circlepath",
        isInProgress: true
      )
    case .succeeded:
      RecognizerTrainingMenuDescriptor(
        title: "Personal Recognizer Ready",
        symbolName: "checkmark.circle",
        isInProgress: false
      )
    case .cancelled:
      RecognizerTrainingMenuDescriptor(
        title: "Recognizer Training Cancelled",
        symbolName: "xmark.circle",
        isInProgress: false
      )
    case .failed(let failure):
      RecognizerTrainingMenuDescriptor(
        title: "Recognizer Training Failed",
        symbolName: "exclamationmark.triangle",
        detail: failure.detail,
        isInProgress: false
      )
    }
  }
}

extension RecognizerTrainingFailure {
  fileprivate var detail: String {
    switch self {
    case .training(.invalidTrainingInput):
      "Validated training input is unavailable."
    case .training(.trainingFailed):
      "Create ML training failed."
    case .training(.outputUnavailable):
      "The trained model artifact could not be saved locally."
    case .candidateSave(.artifactUnavailable):
      "The trained model artifact is unavailable."
    case .candidateSave(.storageUnavailable):
      "Personal Recognizer storage is unavailable."
    case .candidateSave(.compilationFailed):
      "The Personal Recognizer could not be compiled."
    case .candidateSave(.modelValidationFailed):
      "The compiled Personal Recognizer could not be loaded."
    case .modelReplacement(.candidateUnavailable):
      "The saved Personal Recognizer candidate is unavailable."
    case .modelReplacement(.replacementFailed):
      "The active Personal Recognizer could not be replaced."
    }
  }
}

extension PrimaryWorkflowPresentation {
  var content: MenuStatusContent {
    switch self {
    case .leadingPiAgentFocused:
      MenuStatusContent(
        title: "Leading Pi Agent Focused",
        symbolName: "terminal.fill",
        detail: nil
      )
    case .piAgentStarted:
      MenuStatusContent(
        title: "Pi Agent Started",
        symbolName: "terminal.fill",
        detail: nil
      )
    case .failed(let failure):
      MenuStatusContent(
        title: "Workflow Failed",
        symbolName: "exclamationmark.octagon",
        detail: failure.detail
      )
    }
  }
}

extension PrimaryWorkflowFailure {
  fileprivate var detail: String {
    switch self {
    case .configuration(.unavailable):
      "Workflow configuration is unavailable."
    case .configuration(.malformed):
      "Workflow configuration contains malformed JSON."
    case .configuration(.invalidStructure):
      "Workflow configuration must contain only workspace.path and pi.command."
    case .configuration(.emptyWorkspacePath):
      "workspace.path cannot be empty."
    case .configuration(.emptyPiCommand):
      "pi.command must contain at least one argument."
    case .ghosttyNotInstalled:
      "Ghostty is not installed."
    case .ghosttyVersionUnavailable:
      "Ghostty version is unavailable."
    case .ghosttyVersionInvalid(let version):
      "Ghostty version is invalid: \(version)"
    case .ghosttyVersionUnsupported(let found, let minimum):
      "Ghostty \(minimum)+ is required; found \(found)."
    case .ghosttyLaunchFailed:
      "Ghostty could not be launched."
    case .ghosttyAutomationDenied:
      "Ghostty Automation permission was denied."
    case .ghosttyAutomationUnavailable:
      "Ghostty Automation is unavailable."
    case .herdrUnavailable:
      "Herdr is unavailable or could not complete the requested command."
    case .malformedHerdrOutput:
      "Herdr returned malformed Agent JSON."
    case .piStartFailed:
      "Herdr could not start or confirm the configured Pi Agent."
    }
  }
}

extension PoseDatasetImportPresentation {
  var isInProgress: Bool {
    switch self {
    case .choosingFolder, .validating:
      true
    case .failed, .ready:
      false
    }
  }

  var content: MenuStatusContent {
    switch self {
    case .choosingFolder:
      MenuStatusContent(
        title: "Choosing Pose Dataset",
        symbolName: "folder",
        detail: nil
      )
    case .validating(let progress):
      MenuStatusContent(
        title: "Validating Pose Dataset",
        symbolName: "hand.raised",
        detail: progress.map {
          "\($0.processedImageCount) of \($0.totalImageCount) images processed"
        }
      )
    case .failed(let failure):
      MenuStatusContent(
        title: "Pose Dataset Invalid",
        symbolName: "exclamationmark.triangle",
        detail: failure.detail
      )
    case .ready(let input):
      MenuStatusContent(
        title: "Pose Dataset Ready",
        symbolName: "checkmark.circle",
        detail: input.summary.detail
      )
    }
  }
}

extension PoseDatasetImportFailure {
  fileprivate var detail: String {
    switch self {
    case .rootDirectoryUnavailable(let reason):
      "Selected root \(reason.detail)."
    case .labelDirectoryUnavailable(let label, let reason):
      "\(label.rawValue)/ \(reason.detail)."
    case .insufficientValidImages(let summary, let minimumPerLabel):
      "\(summary.detail); minimum \(minimumPerLabel) valid images per label"
    case .preparationFailed(let summary):
      "Vision preparation failed; \(summary.detail)"
    case .outputUnavailable:
      "Normalized images could not be saved locally."
    }
  }
}

extension PoseDatasetDirectoryFailure {
  fileprivate var detail: String {
    switch self {
    case .missing:
      "is missing"
    case .notDirectory:
      "is not a directory"
    case .unreadable:
      "cannot be read"
    }
  }
}

extension PoseDatasetSummary {
  fileprivate var detail: String {
    [
      domainExpansion.detail(label: PoseDatasetLabel.domainExpansion.rawValue),
      other.detail(label: PoseDatasetLabel.other.rawValue),
    ].joined(separator: "; ")
  }
}

extension PoseDatasetLabelSummary {
  fileprivate func detail(label: String) -> String {
    "\(label): \(validImageCount) valid, \(handlessImageCount) handless, \(unreadableImageCount) unreadable"
  }
}

extension CameraUnavailableReason {
  fileprivate var detail: String {
    switch self {
    case .authorizationDenied:
      "Camera permission was denied."
    case .authorizationRestricted:
      "Camera access is restricted."
    case .capture(.builtInCameraUnavailable):
      "The MacBook built-in camera is unavailable."
    case .capture(.configurationFailed):
      "The camera could not be configured."
    case .capture(.startFailed):
      "Camera capture could not start."
    }
  }
}

extension MenuPresentation {
  var content: MenuStatusContent {
    switch self {
    case .awaitingCameraAuthorization:
      MenuStatusContent(
        title: "Camera Authorization",
        symbolName: "video.badge.ellipsis",
        detail: "Waiting for camera permission."
      )
    case .activeMonitoring:
      MenuStatusContent(
        title: "Active Monitoring",
        symbolName: "viewfinder.circle",
        detail: "MacBook built-in camera is active."
      )
    case .pausedMonitoring:
      MenuStatusContent(
        title: "Paused Monitoring",
        symbolName: "pause.circle",
        detail: "Camera is released."
      )
    case .captureInterrupted:
      MenuStatusContent(
        title: "Camera Interrupted",
        symbolName: "video.slash",
        detail: "Monitoring will resume when the camera is available."
      )
    case .cameraUnavailable(let reason):
      MenuStatusContent(
        title: "Camera Unavailable",
        symbolName: "video.slash",
        detail: reason.detail
      )
    case .setupRequired:
      MenuStatusContent(
        title: "Setup Required",
        symbolName: "exclamationmark.triangle",
        detail: "A Personal Recognizer is required."
      )
    }
  }
}
