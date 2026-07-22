import SiglaunchCore
import XCTest

final class LaunchCoordinatorTests: XCTestCase {
  private typealias Step = (name: String, event: AppEvent, effects: Effects)

  func testLaunchWithoutPersonalRecognizerPresentsSetupRequired() {
    let coordinator = LaunchCoordinator()
    let steps: [Step] = [
      (
        "launch configures a menu-bar-only application",
        .appLaunched,
        [.configureMenuBarApplication]
      ),
      (
        "a duplicate launch does not repeat configuration",
        .appLaunched,
        []
      ),
      (
        "configuration completion checks for a Personal Recognizer",
        .menuBarApplicationConfigurationCompleted(.succeeded),
        [.checkPersonalRecognizer]
      ),
      (
        "a duplicate configuration result does not repeat the check",
        .menuBarApplicationConfigurationCompleted(.succeeded),
        []
      ),
      (
        "a missing Personal Recognizer presents Setup Required",
        .personalRecognizerChecked(.missing),
        [.presentMenu(.setupRequired)]
      ),
      (
        "menu presentation completion has no further effects",
        .menuPresented(.setupRequired),
        []
      ),
      (
        "a duplicate result does not repeat menu presentation",
        .personalRecognizerChecked(.missing),
        []
      ),
    ]

    assertEffects(steps, from: coordinator)
  }

  func testEveryMenuBarConfigurationResultContinuesRecognizerCheck() {
    let results: [MenuBarApplicationConfigurationResult] = [.succeeded, .failed]

    for result in results {
      let coordinator = makeCoordinator(after: [.appLaunched])
      XCTAssertEqual(
        coordinator.handle(.menuBarApplicationConfigurationCompleted(result)),
        [.checkPersonalRecognizer],
        "configuration result: \(result)"
      )
    }
  }

  func testAvailablePersonalRecognizerPresentsReadyWithoutClaimingMonitoring() {
    let coordinator = makeCoordinator(
      after: [
        .appLaunched,
        .menuBarApplicationConfigurationCompleted(.succeeded),
      ]
    )
    let steps: [Step] = [
      (
        "availability presents a truthful pre-monitoring status",
        .personalRecognizerChecked(.available),
        [.presentMenu(.personalRecognizerReady)]
      ),
      (
        "menu presentation completion has no further effects",
        .menuPresented(.personalRecognizerReady),
        []
      ),
      (
        "a stale missing result cannot replace availability",
        .personalRecognizerChecked(.missing),
        []
      ),
    ]

    assertEffects(steps, from: coordinator)
  }

  func testQuitTerminatesApplicationOnceFromEveryReachableMenuState() {
    let cases: [(name: String, priorEvents: [AppEvent])] = [
      ("configuring the menu-bar application", [.appLaunched]),
      (
        "checking Personal Recognizer",
        [
          .appLaunched,
          .menuBarApplicationConfigurationCompleted(.succeeded),
        ]
      ),
      (
        "Personal Recognizer ready",
        [
          .appLaunched,
          .menuBarApplicationConfigurationCompleted(.succeeded),
          .personalRecognizerChecked(.available),
          .menuPresented(.personalRecognizerReady),
        ]
      ),
      (
        "Setup Required",
        [
          .appLaunched,
          .menuBarApplicationConfigurationCompleted(.succeeded),
          .personalRecognizerChecked(.missing),
          .menuPresented(.setupRequired),
        ]
      ),
    ]

    for testCase in cases {
      let coordinator = makeCoordinator(after: testCase.priorEvents)
      XCTAssertEqual(
        coordinator.handle(.quitRequested),
        [.terminateApplication],
        testCase.name
      )
      XCTAssertEqual(
        coordinator.handle(.quitRequested),
        [],
        "\(testCase.name) should terminate only once"
      )
    }
  }

  func testPrimaryWorkflowColdStartPreparesGhosttyAndQueriesAgents() {
    let coordinator = makeWorkflowReadyCoordinator()
    let configuration = WorkflowConfiguration(
      workspacePath: "/Users/developer/work/siglaunch",
      piCommand: ["pi", "--model", "gpt-5"]
    )
    let ghostty = GhosttyApplication(
      path: "/Applications/Ghostty.app",
      version: "1.3.0",
      isRunning: false
    )
    let steps: [Step] = [
      (
        "a Primary Workflow request loads its strict local configuration",
        .primaryWorkflowRequested,
        [.loadWorkflowConfiguration]
      ),
      (
        "the validated configuration starts Ghostty resolution",
        .workflowConfigurationLoadCompleted(.loaded(configuration)),
        [.resolveGhostty]
      ),
      (
        "a supported stopped Ghostty is launched from its resolved bundle",
        .ghosttyResolutionCompleted(.found(ghostty)),
        [.launchGhostty(at: ghostty.path)]
      ),
      (
        "a successful launch proceeds to the native AppleScript session check",
        .ghosttyLaunchCompleted(.succeeded),
        [.ensureDefaultHerdrSession]
      ),
      (
        "starting the default Herdr Session queries its Agents",
        .defaultHerdrSessionEnsureCompleted(.ready(.started)),
        [.queryHerdrAgents]
      ),
    ]

    assertEffects(steps, from: coordinator)
  }

  func testHerdrQuerySelectsLeadingPiAgentUsingCanonicalWorkspacePaths() {
    let cases: [(name: String, agents: [HerdrAgent], paneID: String)] = [
      (
        "agent type is filtered before cwd matching",
        [
          HerdrAgent(
            paneID: "pane-codex",
            agent: "codex",
            cwd: workflowConfiguration.workspacePath,
            foregroundCwd: workflowConfiguration.workspacePath
          ),
          HerdrAgent(
            paneID: "pane-leading-pi",
            agent: "pi",
            cwd: workflowConfiguration.workspacePath,
            foregroundCwd: "/Users/developer"
          ),
        ],
        "pane-leading-pi"
      ),
      (
        "cwd uses the same canonical path rule as Workspace",
        [
          HerdrAgent(
            paneID: "pane-canonical-cwd",
            agent: "pi",
            cwd: "/Users/developer/work/other/../siglaunch/",
            foregroundCwd: nil
          )
        ],
        "pane-canonical-cwd"
      ),
      (
        "foreground cwd can match and original order wins",
        [
          HerdrAgent(
            paneID: "pane-first",
            agent: "pi",
            cwd: "/Users/developer",
            foregroundCwd: "/Users/developer/work/./siglaunch"
          ),
          HerdrAgent(
            paneID: "pane-second",
            agent: "pi",
            cwd: workflowConfiguration.workspacePath,
            foregroundCwd: nil
          ),
        ],
        "pane-first"
      ),
    ]

    for testCase in cases {
      let coordinator = makeCoordinatorQueryingHerdrAgents()
      XCTAssertEqual(
        coordinator.handle(.herdrAgentQueryCompleted(.agents(testCase.agents))),
        [.focusHerdrAgent(paneID: testCase.paneID)],
        testCase.name
      )
    }
  }

  func testHerdrQueryWithoutMatchingAgentProducesColdStartResult() {
    let coordinator = makeCoordinatorQueryingHerdrAgents()
    let agents = [
      HerdrAgent(
        paneID: "pane-nonmatching-pi",
        agent: "pi",
        cwd: "/Users/developer/work/another-workspace",
        foregroundCwd: nil
      ),
      HerdrAgent(
        paneID: "pane-matching-codex",
        agent: "codex",
        cwd: workflowConfiguration.workspacePath,
        foregroundCwd: nil
      ),
    ]

    XCTAssertEqual(
      coordinator.handle(.herdrAgentQueryCompleted(.agents(agents))),
      [
        .primaryWorkflowNoMatchingAgent(
          PrimaryWorkflowContext(
            configuration: workflowConfiguration,
            defaultHerdrSession: .reused
          )
        )
      ]
    )
    XCTAssertEqual(coordinator.handle(.herdrAgentQueryCompleted(.agents([]))), [])
  }

  func testHerdrQueryFailuresRemainDistinctAndStopTheWorkflow() {
    let cases: [(queryResult: HerdrAgentQueryResult, failure: PrimaryWorkflowFailure)] = [
      (.herdrUnavailable, .herdrUnavailable),
      (.malformedOutput, .malformedHerdrOutput),
    ]

    for testCase in cases {
      let coordinator = makeCoordinatorQueryingHerdrAgents()
      XCTAssertEqual(
        coordinator.handle(.herdrAgentQueryCompleted(testCase.queryResult)),
        [.primaryWorkflowFailed(testCase.failure)]
      )
      XCTAssertEqual(
        coordinator.handle(.herdrAgentQueryCompleted(.agents([]))),
        [],
        "query failure must terminate the current Workflow: \(testCase.queryResult)"
      )
    }
  }

  func testLeadingPiAgentFocusSuccessCompletesWorkflowOnce() {
    let coordinator = makeCoordinatorQueryingHerdrAgents()
    let agent = HerdrAgent(
      paneID: "pane-leading-pi",
      agent: "pi",
      cwd: workflowConfiguration.workspacePath,
      foregroundCwd: nil
    )
    XCTAssertEqual(
      coordinator.handle(.herdrAgentQueryCompleted(.agents([agent]))),
      [.focusHerdrAgent(paneID: agent.paneID)]
    )

    XCTAssertEqual(
      coordinator.handle(.herdrAgentFocusCompleted(.succeeded)),
      [
        .primaryWorkflowLeadingPiAgentFocused(
          LeadingPiAgentContext(
            workflow: PrimaryWorkflowContext(
              configuration: workflowConfiguration,
              defaultHerdrSession: .reused
            ),
            agent: agent
          )
        )
      ]
    )
    XCTAssertEqual(coordinator.handle(.herdrAgentFocusCompleted(.succeeded)), [])
  }

  func testLeadingPiAgentFocusFailureStopsWorkflow() {
    let coordinator = makeCoordinatorQueryingHerdrAgents()
    let agent = HerdrAgent(
      paneID: "pane-leading-pi",
      agent: "pi",
      cwd: workflowConfiguration.workspacePath,
      foregroundCwd: nil
    )
    _ = coordinator.handle(.herdrAgentQueryCompleted(.agents([agent])))

    XCTAssertEqual(
      coordinator.handle(.herdrAgentFocusCompleted(.failed)),
      [.primaryWorkflowFailed(.herdrUnavailable)]
    )
    XCTAssertEqual(coordinator.handle(.herdrAgentFocusCompleted(.succeeded)), [])
  }

  func testPrimaryWorkflowConfigurationFailuresStopBeforeGhosttyResolution() {
    let failures: [WorkflowConfigurationFailure] = [
      .unavailable,
      .malformed,
      .invalidStructure,
      .emptyWorkspacePath,
      .emptyPiCommand,
    ]

    for failure in failures {
      let coordinator = makeWorkflowReadyCoordinator()
      XCTAssertEqual(
        coordinator.handle(.primaryWorkflowRequested),
        [.loadWorkflowConfiguration]
      )
      XCTAssertEqual(
        coordinator.handle(.workflowConfigurationLoadCompleted(.failed(failure))),
        [.primaryWorkflowFailed(.configuration(failure))],
        "configuration failure: \(failure)"
      )
      XCTAssertEqual(
        coordinator.handle(
          .ghosttyResolutionCompleted(
            .found(
              GhosttyApplication(
                path: "/Applications/Ghostty.app",
                version: "1.3.0",
                isRunning: true
              )
            )
          )
        ),
        [],
        "configuration failure must stop before Ghostty resolution: \(failure)"
      )
    }
  }

  func testRunningGhosttyReusesDefaultHerdrSessionWithoutLaunchingAgain() {
    let coordinator = makeCoordinatorResolvingGhostty()
    let steps: [Step] = [
      (
        "a supported running Ghostty proceeds directly to AppleScript",
        .ghosttyResolutionCompleted(
          .found(
            GhosttyApplication(
              path: "/Applications/Ghostty.app",
              version: "1.3.1",
              isRunning: true
            )
          )
        ),
        [.ensureDefaultHerdrSession]
      ),
      (
        "the existing default Herdr Session is reused before querying Agents",
        .defaultHerdrSessionEnsureCompleted(.ready(.reused)),
        [.queryHerdrAgents]
      ),
    ]

    assertEffects(steps, from: coordinator)
  }

  func testGhosttyFailuresStopAtTheirExactWorkflowStep() {
    let missingGhostty = makeCoordinatorResolvingGhostty()
    XCTAssertEqual(
      missingGhostty.handle(.ghosttyResolutionCompleted(.notInstalled)),
      [.primaryWorkflowFailed(.ghosttyNotInstalled)]
    )
    XCTAssertEqual(missingGhostty.handle(.ghosttyLaunchCompleted(.succeeded)), [])

    let launchFailure = makeCoordinatorResolvingGhostty()
    XCTAssertEqual(
      launchFailure.handle(
        .ghosttyResolutionCompleted(
          .found(
            GhosttyApplication(
              path: "/Applications/Ghostty.app",
              version: "1.3.0",
              isRunning: false
            )
          )
        )
      ),
      [.launchGhostty(at: "/Applications/Ghostty.app")]
    )
    XCTAssertEqual(
      launchFailure.handle(.ghosttyLaunchCompleted(.failed)),
      [.primaryWorkflowFailed(.ghosttyLaunchFailed)]
    )
    XCTAssertEqual(
      launchFailure.handle(.defaultHerdrSessionEnsureCompleted(.ready(.started))),
      []
    )

    let automationCases:
      [(failure: GhosttyAutomationFailure, workflowFailure: PrimaryWorkflowFailure)] = [
        (.denied, .ghosttyAutomationDenied),
        (.unavailable, .ghosttyAutomationUnavailable),
      ]
    for testCase in automationCases {
      let automationFailure = makeCoordinatorEnsuringDefaultHerdrSession()
      XCTAssertEqual(
        automationFailure.handle(
          .defaultHerdrSessionEnsureCompleted(.automationFailed(testCase.failure))
        ),
        [.primaryWorkflowFailed(testCase.workflowFailure)]
      )
      XCTAssertEqual(
        automationFailure.handle(.defaultHerdrSessionEnsureCompleted(.ready(.reused))),
        []
      )
    }

    let herdrFailure = makeCoordinatorEnsuringDefaultHerdrSession()
    XCTAssertEqual(
      herdrFailure.handle(.defaultHerdrSessionEnsureCompleted(.herdrUnavailable)),
      [.primaryWorkflowFailed(.herdrUnavailable)]
    )
    XCTAssertEqual(
      herdrFailure.handle(.defaultHerdrSessionEnsureCompleted(.ready(.started))),
      []
    )
  }

  func testGhosttyVersionUsesSemanticVersionMinimum() {
    let cases: [(version: String?, effects: Effects)] = [
      (nil, [.primaryWorkflowFailed(.ghosttyVersionUnavailable)]),
      ("", [.primaryWorkflowFailed(.ghosttyVersionInvalid(""))]),
      ("1.3", [.primaryWorkflowFailed(.ghosttyVersionInvalid("1.3"))]),
      ("01.3.0", [.primaryWorkflowFailed(.ghosttyVersionInvalid("01.3.0"))]),
      ("1.03.0", [.primaryWorkflowFailed(.ghosttyVersionInvalid("1.03.0"))]),
      ("1.3.0-", [.primaryWorkflowFailed(.ghosttyVersionInvalid("1.3.0-"))]),
      ("1.3.0+", [.primaryWorkflowFailed(.ghosttyVersionInvalid("1.3.0+"))]),
      (
        "1.3.1-alpha.01",
        [.primaryWorkflowFailed(.ghosttyVersionInvalid("1.3.1-alpha.01"))]
      ),
      (
        "1.2.99",
        [
          .primaryWorkflowFailed(
            .ghosttyVersionUnsupported(found: "1.2.99", minimum: "1.3.0")
          )
        ]
      ),
      (
        "1.3.0-beta.1",
        [
          .primaryWorkflowFailed(
            .ghosttyVersionUnsupported(found: "1.3.0-beta.1", minimum: "1.3.0")
          )
        ]
      ),
      ("1.3.0", [.ensureDefaultHerdrSession]),
      ("1.3.1-beta.1", [.ensureDefaultHerdrSession]),
      ("1.3.0+build.1", [.ensureDefaultHerdrSession]),
      ("2.0.0", [.ensureDefaultHerdrSession]),
    ]

    for testCase in cases {
      let coordinator = makeCoordinatorResolvingGhostty()
      let ghostty = GhosttyApplication(
        path: "/Applications/Ghostty.app",
        version: testCase.version,
        isRunning: true
      )
      XCTAssertEqual(
        coordinator.handle(.ghosttyResolutionCompleted(.found(ghostty))),
        testCase.effects,
        "Ghostty version: \(testCase.version ?? "missing")"
      )
    }
  }

  private func assertEffects(_ steps: [Step], from coordinator: LaunchCoordinator) {
    for step in steps {
      XCTAssertEqual(coordinator.handle(step.event), step.effects, step.name)
    }
  }

  private func makeCoordinator(after events: [AppEvent]) -> LaunchCoordinator {
    let coordinator = LaunchCoordinator()
    for event in events {
      _ = coordinator.handle(event)
    }
    return coordinator
  }

  private func makeWorkflowReadyCoordinator() -> LaunchCoordinator {
    makeCoordinator(
      after: [
        .appLaunched,
        .menuBarApplicationConfigurationCompleted(.succeeded),
        .personalRecognizerChecked(.available),
        .menuPresented(.personalRecognizerReady),
      ]
    )
  }

  private var workflowConfiguration: WorkflowConfiguration {
    WorkflowConfiguration(
      workspacePath: "/Users/developer/work/siglaunch",
      piCommand: ["pi"]
    )
  }

  private func makeCoordinatorResolvingGhostty() -> LaunchCoordinator {
    let coordinator = makeWorkflowReadyCoordinator()
    _ = coordinator.handle(.primaryWorkflowRequested)
    _ = coordinator.handle(
      .workflowConfigurationLoadCompleted(.loaded(workflowConfiguration))
    )
    return coordinator
  }

  private func makeCoordinatorEnsuringDefaultHerdrSession() -> LaunchCoordinator {
    let coordinator = makeCoordinatorResolvingGhostty()
    _ = coordinator.handle(
      .ghosttyResolutionCompleted(
        .found(
          GhosttyApplication(
            path: "/Applications/Ghostty.app",
            version: "1.3.0",
            isRunning: true
          )
        )
      )
    )
    return coordinator
  }

  private func makeCoordinatorQueryingHerdrAgents() -> LaunchCoordinator {
    let coordinator = makeCoordinatorEnsuringDefaultHerdrSession()
    _ = coordinator.handle(.defaultHerdrSessionEnsureCompleted(.ready(.reused)))
    return coordinator
  }
}
