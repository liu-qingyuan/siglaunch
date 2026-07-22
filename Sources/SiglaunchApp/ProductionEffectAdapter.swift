import AppKit
import SiglaunchCore

@MainActor
final class ProductionEffectAdapter {
  private let recognizerStore: PersonalRecognizerStore
  private let eventSink: (AppEvent) -> Void
  private let menuSink: (MenuPresentation) -> Void

  init(
    recognizerStore: PersonalRecognizerStore,
    eventSink: @escaping (AppEvent) -> Void,
    menuSink: @escaping (MenuPresentation) -> Void
  ) {
    self.recognizerStore = recognizerStore
    self.eventSink = eventSink
    self.menuSink = menuSink
  }

  func execute(_ effect: AppEffect) {
    switch effect {
    case .configureMenuBarApplication:
      let result: MenuBarApplicationConfigurationResult =
        NSApplication.shared.setActivationPolicy(.accessory) ? .succeeded : .failed
      eventSink(.menuBarApplicationConfigurationCompleted(result))
    case .checkPersonalRecognizer:
      eventSink(.personalRecognizerChecked(recognizerStore.availability))
    case .presentMenu(let presentation):
      menuSink(presentation)
      eventSink(.menuPresented(presentation))
    case .terminateApplication:
      NSApplication.shared.terminate(nil)
    }
  }
}
