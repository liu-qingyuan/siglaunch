import SiglaunchCore
import XCTest

final class RecognitionDiagnosticsTests: XCTestCase {
  func testActiveMonitoringStartsCaptureAtTheDefaultRecognitionFrameRate() {
    let coordinator = LaunchCoordinator()
    _ = coordinator.handle(.appLaunched)
    _ = coordinator.handle(.menuBarApplicationConfigurationCompleted(.succeeded))
    XCTAssertEqual(
      coordinator.handle(.personalRecognizerChecked(.available)),
      [
        .presentMenu(.awaitingCameraAuthorization),
        .camera(.requestAuthorization),
      ]
    )

    XCTAssertEqual(
      coordinator.handle(.camera(.authorizationChanged(.authorized))),
      [
        .camera(
          .startBuiltInCamera(
            targetFrameRate: .fps15,
            lifecycleID: RecognitionLifecycleID(rawValue: 1)
          )
        )
      ]
    )
  }

  func testActiveMonitoringChangesEveryRecognitionFrameRate() {
    let coordinator = makeActiveMonitoringCoordinator()
    let cases: [(target: RecognitionFrameRate, lifecycle: UInt64)] = [
      (.fps10, 2),
      (.fps15, 3),
      (.fps30, 4),
    ]

    for testCase in cases {
      XCTAssertEqual(
        coordinator.handle(.recognitionFrameRateRequested(testCase.target)),
        [
          .clearRecognitionEvidence,
          .camera(
            .updateRecognitionFrameRate(
              targetFrameRate: testCase.target,
              lifecycleID: RecognitionLifecycleID(
                rawValue: testCase.lifecycle
              )
            )
          ),
        ],
        "target: \(testCase.target.rawValue) FPS"
      )
    }
  }

  func testLatestOnlyBufferOverwritesPendingFrameAndAnalyzesOneAtATime() {
    let coordinator = makeActiveMonitoringCoordinator()
    let first = frame(1)
    let overwritten = frame(2)
    let latest = frame(3)

    XCTAssertEqual(
      coordinator.handle(.recognitionFrameCaptured(first)),
      [.recognition(.analyzeFrame(first))]
    )
    XCTAssertEqual(
      coordinator.handle(.recognitionFrameCaptured(overwritten)),
      []
    )
    XCTAssertEqual(
      coordinator.handle(.recognitionFrameCaptured(latest)),
      [.recognition(.discardFrame(overwritten))]
    )

    let diagnostic = DiagnosticGestureResult(
      handDetection: .detected,
      recognizedJointCount: 21,
      extendedFingerCount: 5,
      isOpenPalm: true
    )
    XCTAssertEqual(
      coordinator.handle(
        .recognitionFrameCompleted(
          RecognitionFrameCompletion(
            frame: first,
            diagnosticGesture: diagnostic,
            personalRecognizerResult: .failed
          )
        )
      ),
      [.recognition(.analyzeFrame(latest))]
    )

    XCTAssertEqual(
      coordinator.handle(
        .recognitionFrameCompleted(
          RecognitionFrameCompletion(
            frame: overwritten,
            diagnosticGesture: diagnostic,
            personalRecognizerResult: .failed
          )
        )
      ),
      [],
      "an overwritten frame cannot complete or enter diagnostics"
    )
  }

  func testActualFPSUsesOnlyCompletedFramesAndAControllableClock() {
    let clock = TestRecognitionClock(now: 100)
    let coordinator = makeActiveMonitoringCoordinator(clock: clock)
    _ = coordinator.handle(.recognitionDiagnosticsRequested)
    let first = frame(1)
    let second = frame(2)
    let diagnostic = DiagnosticGestureResult(
      handDetection: .notDetected,
      recognizedJointCount: 0,
      extendedFingerCount: 0,
      isOpenPalm: false
    )

    _ = coordinator.handle(.recognitionFrameCaptured(first))
    XCTAssertEqual(clock.eventCount, 1, "captured frames do not request clock time")
    let firstCompletion = coordinator.handle(
      .recognitionFrameCompleted(
        RecognitionFrameCompletion(
          frame: first,
          diagnosticGesture: diagnostic,
          personalRecognizerResult: .failed
        )
      )
    )
    XCTAssertEqual(completedFPS(in: firstCompletion), 0)
    XCTAssertEqual(clock.eventCount, 1)

    _ = coordinator.handle(.recognitionFrameCaptured(second))
    XCTAssertEqual(clock.eventCount, 1, "pending frames do not request clock time")
    clock.advance(by: 0.1)
    let secondCompletion = coordinator.handle(
      .recognitionFrameCompleted(
        RecognitionFrameCompletion(
          frame: second,
          diagnosticGesture: diagnostic,
          personalRecognizerResult: .failed
        )
      )
    )
    XCTAssertEqual(completedFPS(in: secondCompletion) ?? -1, 10, accuracy: 0.001)
    XCTAssertEqual(clock.eventCount, 2)
  }

  func testLifecycleTransitionsResetDiagnosticsAndRejectOldCompletions() {
    let cases: [(name: String, event: AppEvent, trailingEffects: Effects)] = [
      (
        "pause",
        .pauseMonitoringRequested,
        [.camera(.stopAndReleaseCamera)]
      ),
      (
        "capture interruption",
        .camera(
          .captureInterrupted(
            lifecycleID: RecognitionLifecycleID(rawValue: 1)
          )
        ),
        [
          .camera(.stopCapture),
          .presentMenu(.captureInterrupted),
        ]
      ),
      (
        "system sleep",
        .camera(.systemWillSleep),
        [
          .camera(.stopAndReleaseCamera),
          .presentMenu(.captureInterrupted),
        ]
      ),
      (
        "camera switch",
        .camera(.cameraSwitchDetected),
        [
          .camera(
            .rebuildBuiltInCamera(
              targetFrameRate: .fps15,
              lifecycleID: RecognitionLifecycleID(rawValue: 2)
            )
          ),
          .presentMenu(.captureInterrupted),
        ]
      ),
    ]
    let diagnostic = DiagnosticGestureResult(
      handDetection: .detected,
      recognizedJointCount: 21,
      extendedFingerCount: 5,
      isOpenPalm: true
    )

    for testCase in cases {
      let coordinator = makeActiveMonitoringCoordinator()
      let inFlight = frame(1)
      _ = coordinator.handle(.recognitionFrameCaptured(inFlight))

      XCTAssertEqual(
        coordinator.handle(testCase.event),
        [
          .clearRecognitionEvidence
        ] + testCase.trailingEffects,
        testCase.name
      )
      XCTAssertEqual(
        coordinator.handle(
          .recognitionFrameCompleted(
            RecognitionFrameCompletion(
              frame: inFlight,
              diagnosticGesture: diagnostic,
              personalRecognizerResult: .failed
            )
          )
        ),
        [],
        "\(testCase.name) must reject an old lifecycle completion"
      )
    }
  }

  func testStaleCaptureStartCompletionCannotOverrideTheCurrentLifecycle() {
    let coordinator = LaunchCoordinator()
    _ = coordinator.handle(.appLaunched)
    _ = coordinator.handle(.menuBarApplicationConfigurationCompleted(.succeeded))
    _ = coordinator.handle(.personalRecognizerChecked(.available))
    _ = coordinator.handle(.camera(.authorizationChanged(.authorized)))
    _ = coordinator.handle(.camera(.cameraSwitchDetected))

    XCTAssertEqual(
      coordinator.handle(
        .camera(
          .captureStartCompleted(
            lifecycleID: RecognitionLifecycleID(rawValue: 1),
            result: .failed(.configurationFailed)
          )
        )
      ),
      []
    )
    XCTAssertEqual(
      coordinator.handle(
        .camera(
          .captureStartCompleted(
            lifecycleID: RecognitionLifecycleID(rawValue: 2),
            result: .succeeded
          )
        )
      ),
      [.presentMenu(.activeMonitoring)]
    )
  }

  func testStaleSessionInterruptionCannotResetTheCurrentLifecycle() {
    let coordinator = makeActiveMonitoringCoordinator()
    _ = coordinator.handle(.recognitionFrameRateRequested(.fps30))

    XCTAssertEqual(
      coordinator.handle(
        .camera(
          .captureInterrupted(
            lifecycleID: RecognitionLifecycleID(rawValue: 1)
          )
        )
      ),
      []
    )
    XCTAssertEqual(
      coordinator.handle(
        .camera(
          .captureInterrupted(
            lifecycleID: RecognitionLifecycleID(rawValue: 2)
          )
        )
      ),
      [
        .clearRecognitionEvidence,
        .camera(.stopCapture),
        .presentMenu(.captureInterrupted),
      ]
    )
    XCTAssertEqual(
      coordinator.handle(
        .camera(
          .captureInterruptionEnded(
            lifecycleID: RecognitionLifecycleID(rawValue: 1)
          )
        )
      ),
      []
    )
    XCTAssertEqual(
      coordinator.handle(
        .camera(
          .captureInterruptionEnded(
            lifecycleID: RecognitionLifecycleID(rawValue: 2)
          )
        )
      ),
      [
        .camera(
          .startBuiltInCamera(
            targetFrameRate: .fps30,
            lifecycleID: RecognitionLifecycleID(rawValue: 3)
          )
        )
      ]
    )
  }

  func testFrameRateConfigurationFailureStopsTheInvalidCaptureLifecycle() {
    let coordinator = makeActiveMonitoringCoordinator()
    _ = coordinator.handle(.recognitionFrameRateRequested(.fps30))

    XCTAssertEqual(
      coordinator.handle(
        .camera(
          .captureStartCompleted(
            lifecycleID: RecognitionLifecycleID(rawValue: 2),
            result: .failed(.configurationFailed)
          )
        )
      ),
      [
        .clearRecognitionEvidence,
        .camera(.stopAndReleaseCamera),
        .presentMenu(.cameraUnavailable(.capture(.configurationFailed))),
      ]
    )
  }

  func testUnsupportedTargetReportsTheClosestLowerCaptureRate() {
    let coordinator = makeActiveMonitoringCoordinator()
    let selection = RecognitionFrameRateSelection(
      lifecycleID: RecognitionLifecycleID(rawValue: 1),
      targetFrameRate: .fps15,
      actualFramesPerSecond: 12
    )

    XCTAssertEqual(
      coordinator.handle(.camera(.recognitionFrameRateSelected(selection))),
      []
    )
    XCTAssertEqual(
      coordinator.handle(.recognitionDiagnosticsRequested),
      [
        .openRecognitionDiagnostics(
          RecognitionDiagnosticsSession(
            policy: .standard,
            targetFrameRate: .fps15,
            captureFramesPerSecond: 12
          )
        )
      ]
    )

    let staleSelection = RecognitionFrameRateSelection(
      lifecycleID: RecognitionLifecycleID(rawValue: 0),
      targetFrameRate: .fps15,
      actualFramesPerSecond: 15
    )
    XCTAssertEqual(
      coordinator.handle(.camera(.recognitionFrameRateSelected(staleSelection))),
      []
    )
  }

  func testLockedTriggerKeepsCooldownAndRearmEligibilityAcrossDiagnostics() {
    let clock = TestRecognitionClock(now: 0)
    let coordinator = makeActiveMonitoringCoordinator(clock: clock)
    let match = PersonalRecognizerClassification(
      label: "domain_expansion",
      confidence: 0.9
    )
    _ = completeClassifiedFrame(1, top: match, with: coordinator)
    _ = completeClassifiedFrame(2, top: match, with: coordinator)
    let firstSuccess = completeClassifiedFrame(3, top: match, with: coordinator)
    XCTAssertTrue(
      firstSuccess.contains(.presentDomainExpansionHUD(.showDomainExpansion))
    )
    _ = coordinator.handle(
      .workflowConfigurationLoadCompleted(.failed(.unavailable))
    )
    _ = coordinator.handle(.domainExpansionHUD(.animationCompleted))
    _ = coordinator.handle(.domainExpansionHUD(.dismissed))

    clock.advance(by: 4)
    _ = completeInferenceFrame(4, result: .noHandDetected, with: coordinator)
    _ = coordinator.handle(.recognitionDiagnosticsRequested)
    for sequenceNumber in 5...7 {
      let effects = completeClassifiedFrame(
        UInt64(sequenceNumber),
        top: match,
        with: coordinator
      )
      XCTAssertFalse(effects.contains(.presentDomainExpansionHUD(.showDomainExpansion)))
    }
    _ = coordinator.handle(.recognitionDiagnosticsClosed)

    clock.advance(by: 2)
    _ = completeInferenceFrame(8, result: .noHandDetected, with: coordinator)
    _ = completeClassifiedFrame(9, top: match, with: coordinator)
    _ = completeClassifiedFrame(10, top: match, with: coordinator)
    let secondSuccess = completeClassifiedFrame(11, top: match, with: coordinator)
    XCTAssertTrue(
      secondSuccess.contains(.presentDomainExpansionHUD(.showDomainExpansion)),
      "diagnostics must not reset the absence and cooldown facts needed for Rearm"
    )
  }

  func testDiagnosticsUsesIndependentEvidenceWithoutRecognitionSuccess() {
    let coordinator = makeActiveMonitoringCoordinator()
    let match = PersonalRecognizerClassification(
      label: "domain_expansion",
      confidence: 0.9
    )
    _ = completeClassifiedFrame(1, top: match, with: coordinator)
    _ = completeClassifiedFrame(2, top: match, with: coordinator)

    XCTAssertEqual(
      coordinator.handle(.recognitionDiagnosticsRequested),
      [
        .presentDomainExpansionCandidateProgress(nil),
        .openRecognitionDiagnostics(
          RecognitionDiagnosticsSession(
            policy: .standard,
            targetFrameRate: .fps15,
            captureFramesPerSecond: nil
          )
        ),
      ]
    )

    let nonMatch = PersonalRecognizerClassification(
      label: "other",
      confidence: 0.9
    )
    let diagnosticsClassifications = [
      match, match, match, nonMatch, nonMatch, nonMatch,
    ]
    var diagnosticsFrames: [RecognitionDiagnosticsFrame] = []
    for (offset, classification) in diagnosticsClassifications.enumerated() {
      let effects = completeClassifiedFrame(
        UInt64(offset + 3),
        top: classification,
        with: coordinator
      )
      diagnosticsFrames.append(
        contentsOf: effects.compactMap { effect in
          guard case .presentRecognitionDiagnosticsFrame(let frame) = effect else {
            return nil
          }
          return frame
        }
      )
      XCTAssertFalse(effects.contains(.presentDomainExpansionHUD(.showDomainExpansion)))
      XCTAssertFalse(effects.contains(.loadWorkflowConfiguration))
    }
    XCTAssertEqual(
      diagnosticsFrames.map(\.poseMatchCount),
      [1, 2, 3, 3, 3, 2]
    )
    XCTAssertEqual(
      diagnosticsFrames.map(\.isTriggerConditionSatisfied),
      [false, false, true, true, true, false]
    )

    XCTAssertEqual(
      coordinator.handle(.recognitionDiagnosticsClosed),
      [.closeRecognitionDiagnostics]
    )
    let resumedEffects = completeClassifiedFrame(9, top: match, with: coordinator)
    XCTAssertTrue(
      resumedEffects.contains(
        .presentDomainExpansionCandidateProgress(
          DomainExpansionCandidateProgress(poseMatchCount: 1)
        )
      )
    )
    XCTAssertFalse(
      resumedEffects.contains(.presentDomainExpansionHUD(.showDomainExpansion))
    )
  }

  func testDiagnosticsPublishesPolicyEvaluationForTheAcceptedFrame() {
    let coordinator = makeActiveMonitoringCoordinator()
    _ = coordinator.handle(.recognitionDiagnosticsRequested)
    let reference = frame(1)
    _ = coordinator.handle(.recognitionFrameCaptured(reference))
    let top = PersonalRecognizerClassification(
      label: "domain_expansion",
      confidence: 0.75
    )

    XCTAssertEqual(
      coordinator.handle(
        .recognitionFrameCompleted(
          RecognitionFrameCompletion(
            frame: reference,
            diagnosticGesture: DiagnosticGestureResult(
              handDetection: .detected,
              recognizedJointCount: 21,
              extendedFingerCount: 2,
              isOpenPalm: false
            ),
            personalRecognizerResult: .classified([
              PersonalRecognizerClassification(label: "other", confidence: 0.2),
              top,
            ])
          )
        )
      ),
      [
        .presentRecognitionDiagnosticsFrame(
          RecognitionDiagnosticsFrame(
            frame: reference,
            policy: .standard,
            topClassification: top,
            isPoseMatch: true,
            poseMatchCount: 1,
            targetFrameRate: .fps15,
            captureFramesPerSecond: nil,
            completedRecognitionFramesPerSecond: 0
          )
        )
      ]
    )
  }

  func testActiveMonitoringOwnsOneRecognitionDiagnosticsSession() {
    let coordinator = makeActiveMonitoringCoordinator()
    let session = RecognitionDiagnosticsSession(
      policy: .standard,
      targetFrameRate: .fps15,
      captureFramesPerSecond: nil
    )

    XCTAssertEqual(
      coordinator.handle(.recognitionDiagnosticsRequested),
      [.openRecognitionDiagnostics(session)]
    )
    XCTAssertEqual(coordinator.handle(.recognitionDiagnosticsRequested), [])
    XCTAssertEqual(
      coordinator.handle(.recognitionDiagnosticsClosed),
      [.closeRecognitionDiagnostics]
    )
    XCTAssertEqual(coordinator.handle(.recognitionDiagnosticsClosed), [])
  }

  func testClosingDiagnosticsOutsideActiveStateCannotLeaveTriggerSuppressed() {
    let coordinator = makeActiveMonitoringCoordinator()
    _ = coordinator.handle(.recognitionDiagnosticsRequested)
    _ = coordinator.handle(
      .camera(
        .captureInterrupted(
          lifecycleID: RecognitionLifecycleID(rawValue: 1)
        )
      )
    )

    XCTAssertEqual(
      coordinator.handle(.recognitionDiagnosticsClosed),
      [.closeRecognitionDiagnostics]
    )
    XCTAssertEqual(
      coordinator.handle(
        .camera(
          .captureInterruptionEnded(
            lifecycleID: RecognitionLifecycleID(rawValue: 1)
          )
        )
      ),
      [
        .camera(
          .startBuiltInCamera(
            targetFrameRate: .fps15,
            lifecycleID: RecognitionLifecycleID(rawValue: 2)
          )
        )
      ]
    )
    XCTAssertEqual(
      coordinator.handle(
        .camera(
          .captureStartCompleted(
            lifecycleID: RecognitionLifecycleID(rawValue: 2),
            result: .succeeded
          )
        )
      ),
      [.presentMenu(.activeMonitoring)]
    )

    let match = PersonalRecognizerClassification(
      label: "domain_expansion",
      confidence: 0.9
    )
    _ = completeClassifiedFrame(1, top: match, lifecycleID: 2, with: coordinator)
    _ = completeClassifiedFrame(2, top: match, lifecycleID: 2, with: coordinator)
    let success = completeClassifiedFrame(
      3,
      top: match,
      lifecycleID: 2,
      with: coordinator
    )
    XCTAssertTrue(
      success.contains(.presentDomainExpansionHUD(.showDomainExpansion))
    )
    XCTAssertTrue(success.contains(.loadWorkflowConfiguration))
  }

  private func completeClassifiedFrame(
    _ sequenceNumber: UInt64,
    top: PersonalRecognizerClassification,
    lifecycleID: UInt64 = 1,
    with coordinator: LaunchCoordinator
  ) -> Effects {
    completeInferenceFrame(
      sequenceNumber,
      result: .classified([top]),
      lifecycleID: lifecycleID,
      with: coordinator
    )
  }

  private func completeInferenceFrame(
    _ sequenceNumber: UInt64,
    result: PersonalRecognizerInferenceResult,
    lifecycleID: UInt64 = 1,
    with coordinator: LaunchCoordinator
  ) -> Effects {
    let reference = frame(sequenceNumber, lifecycleID: lifecycleID)
    _ = coordinator.handle(.recognitionFrameCaptured(reference))
    return coordinator.handle(
      .recognitionFrameCompleted(
        RecognitionFrameCompletion(
          frame: reference,
          diagnosticGesture: DiagnosticGestureResult(
            handDetection: result == .noHandDetected ? .notDetected : .detected,
            recognizedJointCount: result == .noHandDetected ? 0 : 21,
            extendedFingerCount: result == .noHandDetected ? 0 : 2,
            isOpenPalm: false
          ),
          personalRecognizerResult: result
        )
      )
    )
  }

  private func completedFPS(in effects: Effects) -> Double? {
    effects.compactMap { effect -> Double? in
      guard case .presentRecognitionDiagnosticsFrame(let diagnostics) = effect else {
        return nil
      }
      return diagnostics.completedRecognitionFramesPerSecond
    }.first
  }

  private func frame(
    _ sequenceNumber: UInt64,
    lifecycleID: UInt64 = 1
  ) -> RecognitionFrameReference {
    RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: lifecycleID),
      sequenceNumber: sequenceNumber
    )
  }

  private func makeActiveMonitoringCoordinator(
    clock: TestRecognitionClock? = nil
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
    ] {
      _ = coordinator.handle(event)
    }
    if let clock {
      clock.connect(to: coordinator)
    } else {
      _ = coordinator.handle(.recognitionClockRead(0))
    }
    return coordinator
  }
}

private final class TestRecognitionClock {
  private(set) var nowValue: TimeInterval
  private(set) var eventCount = 0
  private weak var coordinator: LaunchCoordinator?

  init(now: TimeInterval) {
    nowValue = now
  }

  func connect(to coordinator: LaunchCoordinator) {
    self.coordinator = coordinator
    sendTimeEvent()
  }

  func advance(by interval: TimeInterval) {
    nowValue += interval
    sendTimeEvent()
  }

  private func sendTimeEvent() {
    eventCount += 1
    _ = coordinator?.handle(.recognitionClockRead(nowValue))
  }
}
