import SiglaunchCore
import SwiftUI

struct SiglaunchMenu: View {
  let presentation: MenuPresentation?
  let primaryWorkflowPresentation: PrimaryWorkflowPresentation?
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

    Divider()

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
    case .ghosttyReady:
      MenuStatusContent(
        title: "Herdr Session Ready",
        symbolName: "terminal",
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
      "Herdr is unavailable or did not attach to its default Session."
    }
  }
}

extension MenuPresentation {
  var content: MenuStatusContent {
    switch self {
    case .personalRecognizerReady:
      MenuStatusContent(
        title: "Personal Recognizer Ready",
        symbolName: "checkmark.circle",
        detail: nil
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
