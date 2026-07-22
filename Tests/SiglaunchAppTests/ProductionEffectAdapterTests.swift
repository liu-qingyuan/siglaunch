import SiglaunchCore
import XCTest

@testable import SiglaunchApp

@MainActor
final class ProductionEffectAdapterTests: XCTestCase {
  func testFakeAdaptersDrivePrimaryWorkflowThroughCoordinatorLoop() {
    let configuration = WorkflowConfiguration(
      workspacePath: "/Users/developer/work/siglaunch",
      piCommand: ["pi", "--model", "gpt-5"]
    )
    let configurationLoader = FakeWorkflowConfigurationLoader(
      result: .loaded(configuration)
    )
    let ghosttyAdapter = FakeGhosttyPlatformAdapter(
      resolution: .found(
        GhosttyApplication(
          path: "/Applications/Ghostty.app",
          version: "1.3.0",
          isRunning: false
        )
      ),
      launchResult: .succeeded,
      sessionResult: .ready(.started)
    )
    let leadingAgent = HerdrAgent(
      paneID: "pane-leading-pi",
      agent: "pi",
      cwd: configuration.workspacePath,
      foregroundCwd: configuration.workspacePath
    )
    let herdrAdapter = FakeHerdrAgentAdapter(
      queryResult: .agents([leadingAgent]),
      focusResult: .succeeded
    )
    let coordinator = makeWorkflowReadyCoordinator()

    var observedEffects: [AppEffect] = []
    var workflowPresentations: [PrimaryWorkflowPresentation?] = []
    var sendEvent: ((AppEvent) -> Void)!
    var effectAdapter: ProductionEffectAdapter!
    effectAdapter = ProductionEffectAdapter(
      recognizerStore: PersonalRecognizerStore(),
      workflowConfigurationStore: configurationLoader,
      ghosttyPlatformAdapter: ghosttyAdapter,
      herdrAgentAdapter: herdrAdapter,
      eventSink: { event in sendEvent(event) },
      menuSink: { _ in },
      workflowSink: { workflowPresentations.append($0) }
    )
    sendEvent = { event in
      let effects = coordinator.handle(event)
      observedEffects.append(contentsOf: effects)
      for effect in effects {
        effectAdapter.execute(effect)
      }
    }

    sendEvent(.primaryWorkflowRequested)

    XCTAssertEqual(
      observedEffects,
      [
        .loadWorkflowConfiguration,
        .resolveGhostty,
        .launchGhostty(at: "/Applications/Ghostty.app"),
        .ensureDefaultHerdrSession,
        .queryHerdrAgents,
        .focusHerdrAgent(paneID: leadingAgent.paneID),
        .primaryWorkflowLeadingPiAgentFocused(
          LeadingPiAgentContext(
            workflow: PrimaryWorkflowContext(
              configuration: configuration,
              defaultHerdrSession: .started
            ),
            agent: leadingAgent
          )
        ),
      ]
    )
    XCTAssertEqual(ghosttyAdapter.launchedPaths, ["/Applications/Ghostty.app"])
    XCTAssertEqual(herdrAdapter.queryCount, 1)
    XCTAssertEqual(herdrAdapter.focusedPaneIDs, [leadingAgent.paneID])
    XCTAssertEqual(workflowPresentations, [nil, .leadingPiAgentFocused])
  }

  private func makeWorkflowReadyCoordinator() -> LaunchCoordinator {
    let coordinator = LaunchCoordinator()
    for event in [
      AppEvent.appLaunched,
      .menuBarApplicationConfigurationCompleted(.succeeded),
      .personalRecognizerChecked(.available),
      .menuPresented(.personalRecognizerReady),
    ] {
      _ = coordinator.handle(event)
    }
    return coordinator
  }
}

private final class FakeWorkflowConfigurationLoader: WorkflowConfigurationLoading {
  let result: WorkflowConfigurationLoadResult

  init(result: WorkflowConfigurationLoadResult) {
    self.result = result
  }

  func load() -> WorkflowConfigurationLoadResult {
    result
  }
}

@MainActor
private final class FakeGhosttyPlatformAdapter: GhosttyPlatformAdapting {
  let resolution: GhosttyResolutionResult
  let launchResult: GhosttyLaunchResult
  let sessionResult: DefaultHerdrSessionEnsureResult
  private(set) var launchedPaths: [String] = []

  init(
    resolution: GhosttyResolutionResult,
    launchResult: GhosttyLaunchResult,
    sessionResult: DefaultHerdrSessionEnsureResult
  ) {
    self.resolution = resolution
    self.launchResult = launchResult
    self.sessionResult = sessionResult
  }

  func resolve() -> GhosttyResolutionResult {
    resolution
  }

  func launch(
    at path: String,
    completion: @escaping @MainActor @Sendable (GhosttyLaunchResult) -> Void
  ) {
    launchedPaths.append(path)
    completion(launchResult)
  }

  func ensureDefaultHerdrSession(
    completion: @escaping @MainActor @Sendable (DefaultHerdrSessionEnsureResult) -> Void
  ) {
    completion(sessionResult)
  }
}

@MainActor
private final class FakeHerdrAgentAdapter: HerdrAgentAdapting {
  let queryResult: HerdrAgentQueryResult
  let focusResult: HerdrAgentFocusResult
  private(set) var queryCount = 0
  private(set) var focusedPaneIDs: [String] = []

  init(
    queryResult: HerdrAgentQueryResult,
    focusResult: HerdrAgentFocusResult
  ) {
    self.queryResult = queryResult
    self.focusResult = focusResult
  }

  func queryAgents(
    completion: @escaping @MainActor @Sendable (HerdrAgentQueryResult) -> Void
  ) {
    queryCount += 1
    completion(queryResult)
  }

  func focusAgent(
    paneID: String,
    completion: @escaping @MainActor @Sendable (HerdrAgentFocusResult) -> Void
  ) {
    focusedPaneIDs.append(paneID)
    completion(focusResult)
  }
}
