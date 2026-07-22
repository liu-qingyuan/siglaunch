import SiglaunchCore
import SwiftUI

struct SiglaunchMenu: View {
  let presentation: MenuPresentation?
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
