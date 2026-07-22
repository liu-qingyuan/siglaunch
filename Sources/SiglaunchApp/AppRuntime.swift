import Combine
import SiglaunchCore

@MainActor
final class AppRuntime: ObservableObject {
  @Published private(set) var menuPresentation: MenuPresentation?

  private let coordinator = LaunchCoordinator()
  private lazy var effectAdapter = ProductionEffectAdapter(
    recognizerStore: PersonalRecognizerStore(),
    eventSink: { [weak self] event in self?.send(event) },
    menuSink: { [weak self] presentation in
      self?.menuPresentation = presentation
    }
  )

  var menuBarSymbol: String {
    menuPresentation?.content.symbolName ?? "viewfinder.circle"
  }

  init() {
    send(.appLaunched)
  }

  func send(_ event: AppEvent) {
    for effect in coordinator.handle(event) {
      effectAdapter.execute(effect)
    }
  }
}
