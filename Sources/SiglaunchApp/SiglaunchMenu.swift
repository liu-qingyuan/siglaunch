import SiglaunchCore
import SwiftUI

struct SiglaunchMenu: View {
  let presentation: MenuPresentation?
  let primaryWorkflowPresentation: PrimaryWorkflowPresentation?
  let poseDatasetImportPresentation: PoseDatasetImportPresentation?
  let onPauseMonitoring: () -> Void
  let onResumeMonitoring: () -> Void
  let onImportPoseDataset: () -> Void
  let onQuit: () -> Void

  var body: some View {
    if let content = presentation?.content {
      Label(content.title, systemImage: content.symbolName)
      if let detail = content.detail {
        Text(detail)
      }
    } else {
      Label("Checking Personal Recognizer", systemImage: "viewfinder.circle")
    }

    if let content = primaryWorkflowPresentation?.content {
      Divider()
      Label(content.title, systemImage: content.symbolName)
      if let detail = content.detail {
        Text(detail)
      }
    }

    if let content = poseDatasetImportPresentation?.content {
      Divider()
      Label(content.title, systemImage: content.symbolName)
      if let detail = content.detail {
        Text(detail)
      }
    }

    Divider()

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

    if presentation == .setupRequired {
      Button(action: onImportPoseDataset) {
        Label("Import Pose Dataset", systemImage: "folder.badge.plus")
      }
      .disabled(poseDatasetImportPresentation?.isInProgress == true)
    }

    Button(action: onQuit) {
      Label("Quit Siglaunch", systemImage: "power")
    }
    .keyboardShortcut("q")
  }
}

struct MenuStatusContent {
  let title: String
  let symbolName: String
  let detail: String?
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
    case .noMatchingPiAgent:
      MenuStatusContent(
        title: "No Matching Pi Agent",
        symbolName: "terminal",
        detail: "No Pi Agent is running in the configured Workspace."
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
