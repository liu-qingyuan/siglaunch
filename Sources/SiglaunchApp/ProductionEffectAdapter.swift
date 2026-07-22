import AppKit
import SiglaunchCore

enum PrimaryWorkflowPresentation: Equatable {
  case leadingPiAgentFocused
  case noMatchingPiAgent
  case failed(PrimaryWorkflowFailure)
}

@MainActor
final class ProductionEffectAdapter {
  private let recognizerStore: PersonalRecognizerStore
  private let workflowConfigurationStore: any WorkflowConfigurationLoading
  private let ghosttyPlatformAdapter: any GhosttyPlatformAdapting
  private let herdrAgentAdapter: any HerdrAgentAdapting
  private let eventSink: (AppEvent) -> Void
  private let menuSink: (MenuPresentation) -> Void
  private let workflowSink: (PrimaryWorkflowPresentation?) -> Void

  init(
    recognizerStore: PersonalRecognizerStore,
    workflowConfigurationStore: any WorkflowConfigurationLoading = WorkflowConfigurationStore(),
    ghosttyPlatformAdapter: any GhosttyPlatformAdapting = GhosttyPlatformAdapter(),
    herdrAgentAdapter: any HerdrAgentAdapting = HerdrAgentAdapter(),
    eventSink: @escaping (AppEvent) -> Void,
    menuSink: @escaping (MenuPresentation) -> Void,
    workflowSink: @escaping (PrimaryWorkflowPresentation?) -> Void
  ) {
    self.recognizerStore = recognizerStore
    self.workflowConfigurationStore = workflowConfigurationStore
    self.ghosttyPlatformAdapter = ghosttyPlatformAdapter
    self.herdrAgentAdapter = herdrAgentAdapter
    self.eventSink = eventSink
    self.menuSink = menuSink
    self.workflowSink = workflowSink
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
    case .loadWorkflowConfiguration:
      workflowSink(nil)
      eventSink(
        .workflowConfigurationLoadCompleted(workflowConfigurationStore.load())
      )
    case .resolveGhostty:
      eventSink(.ghosttyResolutionCompleted(ghosttyPlatformAdapter.resolve()))
    case .launchGhostty(let path):
      ghosttyPlatformAdapter.launch(at: path) { [weak self] result in
        self?.eventSink(.ghosttyLaunchCompleted(result))
      }
    case .ensureDefaultHerdrSession:
      ghosttyPlatformAdapter.ensureDefaultHerdrSession { [weak self] result in
        self?.eventSink(.defaultHerdrSessionEnsureCompleted(result))
      }
    case .queryHerdrAgents:
      herdrAgentAdapter.queryAgents { [weak self] result in
        self?.eventSink(.herdrAgentQueryCompleted(result))
      }
    case .focusHerdrAgent(let paneID):
      herdrAgentAdapter.focusAgent(paneID: paneID) { [weak self] result in
        self?.eventSink(.herdrAgentFocusCompleted(result))
      }
    case .primaryWorkflowNoMatchingAgent:
      workflowSink(.noMatchingPiAgent)
    case .primaryWorkflowLeadingPiAgentFocused:
      workflowSink(.leadingPiAgentFocused)
    case .primaryWorkflowFailed(let failure):
      workflowSink(.failed(failure))
    case .terminateApplication:
      NSApplication.shared.terminate(nil)
    }
  }
}
