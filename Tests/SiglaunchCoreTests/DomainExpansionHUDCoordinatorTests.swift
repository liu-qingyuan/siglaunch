import SiglaunchCore
import XCTest

final class DomainExpansionHUDCoordinatorTests: XCTestCase {
  func testWorkflowFailureWaitsForDomainExpansionAnimationToComplete() {
    let coordinator = makeTriggeredCoordinator()
    let failure = PrimaryWorkflowFailure.configuration(.unavailable)

    XCTAssertEqual(
      coordinator.handle(
        .workflowConfigurationLoadCompleted(.failed(.unavailable))
      ),
      [.primaryWorkflowFailed(failure)]
    )
    XCTAssertEqual(
      coordinator.handle(.domainExpansionHUD(.animationCompleted)),
      [.presentDomainExpansionHUD(.showError(failure))]
    )
  }

  func testPreservedPiAgentSuccessBeforeAnimationOnlyFadesAfterAnimation() {
    let coordinator = makeTriggeredCoordinator(initialQueryResult: nil)
    let existingAgent = HerdrAgent(
      paneID: "pane-existing-pi",
      agent: "pi",
      cwd: "/Users/developer/work/llm-abm-marketing-sim",
      foregroundCwd: nil
    )

    XCTAssertEqual(
      coordinator.handle(
        .herdrAgentQueryCompleted(
          attemptID: 1,
          phase: .initial,
          result: .agents([existingAgent])
        )
      ),
      [.primaryWorkflowPiAgentPreserved]
    )
    XCTAssertEqual(
      coordinator.handle(.domainExpansionHUD(.animationCompleted)),
      [.presentDomainExpansionHUD(.fade)]
    )
  }

  func testWorkflowSuccessAfterAnimationCompletionFadesImmediately() {
    let coordinator = makeTriggeredCoordinator()
    XCTAssertEqual(
      coordinator.handle(.domainExpansionHUD(.animationCompleted)),
      []
    )

    XCTAssertEqual(
      completeSuccessfulPiStart(with: coordinator),
      [
        .primaryWorkflowPiAgentStarted(successfulWorkflowContext),
        .presentDomainExpansionHUD(.fade),
      ]
    )
  }

  func testEveryWorkflowFailurePreservesItsStepInTheErrorHUD() {
    let configuration = WorkflowConfiguration(
      workspacePath: "/Users/developer/work/siglaunch",
      piCommand: ["pi"]
    )
    let runningGhostty = GhosttyApplication(
      path: "/Applications/Ghostty.app",
      version: "1.3.0",
      isRunning: true
    )
    let readyForHerdr: [AppEvent] = [
      .workflowConfigurationLoadCompleted(.loaded(configuration)),
      .ghosttyResolutionCompleted(.found(runningGhostty)),
      .defaultHerdrSessionEnsureCompleted(.ready(.reused)),
    ]
    let cases: [(String, [AppEvent], PrimaryWorkflowFailure)] = [
      (
        "configuration",
        [.workflowConfigurationLoadCompleted(.failed(.unavailable))],
        .configuration(.unavailable)
      ),
      (
        "Ghostty install",
        [
          .workflowConfigurationLoadCompleted(.loaded(configuration)),
          .ghosttyResolutionCompleted(.notInstalled),
        ],
        .ghosttyNotInstalled
      ),
      (
        "Ghostty version lookup",
        [
          .workflowConfigurationLoadCompleted(.loaded(configuration)),
          .ghosttyResolutionCompleted(
            .found(
              GhosttyApplication(
                path: runningGhostty.path,
                version: nil,
                isRunning: true
              )
            )
          ),
        ],
        .ghosttyVersionUnavailable
      ),
      (
        "Ghostty invalid version",
        [
          .workflowConfigurationLoadCompleted(.loaded(configuration)),
          .ghosttyResolutionCompleted(
            .found(
              GhosttyApplication(
                path: runningGhostty.path,
                version: "invalid",
                isRunning: true
              )
            )
          ),
        ],
        .ghosttyVersionInvalid("invalid")
      ),
      (
        "Ghostty unsupported version",
        [
          .workflowConfigurationLoadCompleted(.loaded(configuration)),
          .ghosttyResolutionCompleted(
            .found(
              GhosttyApplication(
                path: runningGhostty.path,
                version: "1.2.0",
                isRunning: true
              )
            )
          ),
        ],
        .ghosttyVersionUnsupported(found: "1.2.0", minimum: "1.3.0")
      ),
      (
        "Ghostty launch",
        [
          .workflowConfigurationLoadCompleted(.loaded(configuration)),
          .ghosttyResolutionCompleted(
            .found(
              GhosttyApplication(
                path: runningGhostty.path,
                version: "1.3.0",
                isRunning: false
              )
            )
          ),
          .ghosttyLaunchCompleted(.failed),
        ],
        .ghosttyLaunchFailed
      ),
      (
        "Ghostty Automation permission",
        [
          .workflowConfigurationLoadCompleted(.loaded(configuration)),
          .ghosttyResolutionCompleted(.found(runningGhostty)),
          .defaultHerdrSessionEnsureCompleted(.automationFailed(.denied)),
        ],
        .ghosttyAutomationDenied
      ),
      (
        "Ghostty Automation availability",
        [
          .workflowConfigurationLoadCompleted(.loaded(configuration)),
          .ghosttyResolutionCompleted(.found(runningGhostty)),
          .defaultHerdrSessionEnsureCompleted(.automationFailed(.unavailable)),
        ],
        .ghosttyAutomationUnavailable
      ),
      (
        "Herdr availability",
        [
          .workflowConfigurationLoadCompleted(.loaded(configuration)),
          .ghosttyResolutionCompleted(.found(runningGhostty)),
          .defaultHerdrSessionEnsureCompleted(.herdrUnavailable),
        ],
        .herdrUnavailable
      ),
      (
        "Herdr Agent output",
        readyForHerdr + [
          .herdrAgentQueryCompleted(
            attemptID: 1,
            phase: .postBootstrap,
            result: .malformedOutput
          )
        ],
        .malformedHerdrOutput
      ),
      (
        "Pi Agent start",
        readyForHerdr + [
          .herdrAgentQueryCompleted(
            attemptID: 1,
            phase: .postBootstrap,
            result: .agents([])
          ),
          .herdrAgentStartCompleted(.failed),
        ],
        .piStartFailed
      ),
    ]

    for (name, events, failure) in cases {
      let coordinator = makeTriggeredCoordinator()
      _ = coordinator.handle(.domainExpansionHUD(.animationCompleted))
      var finalEffects: Effects = []
      for event in events {
        finalEffects = coordinator.handle(event)
      }
      XCTAssertEqual(
        finalEffects,
        [
          .primaryWorkflowFailed(failure),
          .presentDomainExpansionHUD(.showError(failure)),
        ],
        name
      )
    }
  }

  func testPresentationFailureDoesNotBlockOrCancelTheWorkflow() {
    let coordinator = makeTriggeredCoordinator()
    let configuration = WorkflowConfiguration(
      workspacePath: "/Users/developer/work/siglaunch",
      piCommand: ["pi"]
    )

    XCTAssertEqual(
      coordinator.handle(
        .domainExpansionHUD(
          .presentationFailed(.showDomainExpansion)
        )
      ),
      []
    )
    XCTAssertEqual(
      coordinator.handle(
        .workflowConfigurationLoadCompleted(.loaded(configuration))
      ),
      [.resolveGhostty]
    )
    XCTAssertEqual(
      coordinator.handle(.domainExpansionHUD(.animationCompleted)),
      []
    )
  }

  func testDismissingAnErrorHUDNeverRetriesTheWorkflow() {
    let coordinator = makeTriggeredCoordinator()
    _ = coordinator.handle(.domainExpansionHUD(.animationCompleted))
    _ = coordinator.handle(
      .workflowConfigurationLoadCompleted(.failed(.unavailable))
    )

    XCTAssertEqual(
      coordinator.handle(.domainExpansionHUD(.dismissed)),
      [.presentDomainExpansionHUD(.dismiss)]
    )
    XCTAssertEqual(
      coordinator.handle(.domainExpansionHUD(.dismissed)),
      []
    )
  }

  func testWorkflowFailureAfterAnimationShowsStepErrorImmediately() {
    let coordinator = makeTriggeredCoordinator()
    let failure = PrimaryWorkflowFailure.configuration(.malformed)

    XCTAssertEqual(
      coordinator.handle(.domainExpansionHUD(.animationCompleted)),
      []
    )
    XCTAssertEqual(
      coordinator.handle(
        .workflowConfigurationLoadCompleted(.failed(.malformed))
      ),
      [
        .primaryWorkflowFailed(failure),
        .presentDomainExpansionHUD(.showError(failure)),
      ]
    )
  }

  private var successfulWorkflowConfiguration: WorkflowConfiguration {
    WorkflowConfiguration(
      workspacePath: "/Users/developer/work/siglaunch",
      piCommand: ["pi"]
    )
  }

  private var successfulWorkflowContext: PrimaryWorkflowContext {
    PrimaryWorkflowContext(
      configuration: successfulWorkflowConfiguration,
      defaultHerdrSession: .reused
    )
  }

  private func completeSuccessfulPiStart(
    with coordinator: LaunchCoordinator
  ) -> Effects {
    let configuration = successfulWorkflowConfiguration
    _ = coordinator.handle(
      .workflowConfigurationLoadCompleted(.loaded(configuration))
    )
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
    _ = coordinator.handle(
      .defaultHerdrSessionEnsureCompleted(.ready(.reused))
    )
    _ = coordinator.handle(
      .herdrAgentQueryCompleted(
        attemptID: 1,
        phase: .postBootstrap,
        result: .agents([])
      )
    )
    return coordinator.handle(.herdrAgentStartCompleted(.succeeded))
  }

  private func makeTriggeredCoordinator(
    initialQueryResult: HerdrAgentQueryResult? = .agents([])
  ) -> LaunchCoordinator {
    let coordinator = LaunchCoordinator()
    for event in [
      AppEvent.appLaunched,
      .menuBarApplicationConfigurationCompleted(.succeeded),
      .personalRecognizerChecked(.available),
      .camera(.authorizationChanged(.authorized)),
      .camera(
        .captureStartCompleted(
          lifecycleID: RecognitionLifecycleID(rawValue: 1),
          result: .succeeded
        )
      ),
      .recognitionClockRead(100),
    ] {
      _ = coordinator.handle(event)
    }

    for sequenceNumber in 1...3 {
      let frame = RecognitionFrameReference(
        lifecycleID: RecognitionLifecycleID(rawValue: 1),
        sequenceNumber: UInt64(sequenceNumber)
      )
      _ = coordinator.handle(.recognitionFrameCaptured(frame))
      _ = coordinator.handle(
        .recognitionFrameCompleted(
          RecognitionFrameCompletion(
            frame: frame,
            diagnosticGesture: DiagnosticGestureResult(
              handDetection: .detected,
              recognizedJointCount: 21,
              extendedFingerCount: 3,
              isOpenPalm: false
            ),
            personalRecognizerResult: .classified(
              [
                PersonalRecognizerClassification(
                  label: "domain_expansion",
                  confidence: 0.9
                ),
                PersonalRecognizerClassification(label: "other", confidence: 0.1),
              ]
            )
          )
        )
      )
    }
    if let initialQueryResult {
      _ = coordinator.handle(
        .herdrAgentQueryCompleted(
          attemptID: 1,
          phase: .initial,
          result: initialQueryResult
        )
      )
    }
    return coordinator
  }
}
