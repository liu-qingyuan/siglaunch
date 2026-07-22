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
        .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
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
          .presentRecognitionDiagnostics(
            .initial(targetFrameRate: testCase.target)
          ),
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
            diagnosticGesture: diagnostic
          )
        )
      ),
      [
        .presentRecognitionDiagnostics(
          RecognitionDiagnostics(
            targetFrameRate: .fps15,
            captureFramesPerSecond: nil,
            completedRecognitionFramesPerSecond: 0,
            diagnosticGesture: diagnostic
          )
        ),
        .recognition(.analyzeFrame(latest)),
      ]
    )

    XCTAssertEqual(
      coordinator.handle(
        .recognitionFrameCompleted(
          RecognitionFrameCompletion(
            frame: overwritten,
            diagnosticGesture: diagnostic
          )
        )
      ),
      [],
      "an overwritten frame cannot complete or enter diagnostics"
    )
  }

  func testActualFPSUsesOnlyCompletedFramesAndAControllableClock() {
    let clock = TestRecognitionClock(now: 100)
    let coordinator = makeActiveMonitoringCoordinator(clock: clock.now)
    let first = frame(1)
    let second = frame(2)
    let diagnostic = DiagnosticGestureResult(
      handDetection: .notDetected,
      recognizedJointCount: 0,
      extendedFingerCount: 0,
      isOpenPalm: false
    )

    _ = coordinator.handle(.recognitionFrameCaptured(first))
    XCTAssertEqual(clock.readCount, 0, "captured frames do not update actual FPS")
    let firstCompletion = coordinator.handle(
      .recognitionFrameCompleted(
        RecognitionFrameCompletion(frame: first, diagnosticGesture: diagnostic)
      )
    )
    XCTAssertEqual(completedFPS(in: firstCompletion), 0)
    XCTAssertEqual(clock.readCount, 1)

    _ = coordinator.handle(.recognitionFrameCaptured(second))
    XCTAssertEqual(clock.readCount, 1, "pending frames do not update actual FPS")
    clock.advance(by: 0.1)
    let secondCompletion = coordinator.handle(
      .recognitionFrameCompleted(
        RecognitionFrameCompletion(frame: second, diagnosticGesture: diagnostic)
      )
    )
    XCTAssertEqual(completedFPS(in: secondCompletion) ?? -1, 10, accuracy: 0.001)
    XCTAssertEqual(clock.readCount, 2)
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
          .clearRecognitionEvidence,
          .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
        ] + testCase.trailingEffects,
        testCase.name
      )
      XCTAssertEqual(
        coordinator.handle(
          .recognitionFrameCompleted(
            RecognitionFrameCompletion(
              frame: inFlight,
              diagnosticGesture: diagnostic
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
        .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps30)),
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
        .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps30)),
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
      [
        .presentRecognitionDiagnostics(
          RecognitionDiagnostics(
            targetFrameRate: .fps15,
            captureFramesPerSecond: 12,
            completedRecognitionFramesPerSecond: 0,
            diagnosticGesture: nil
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

  private func completedFPS(in effects: Effects) -> Double? {
    effects.compactMap { effect -> Double? in
      guard case .presentRecognitionDiagnostics(let diagnostics) = effect else {
        return nil
      }
      return diagnostics.completedRecognitionFramesPerSecond
    }.first
  }

  private func frame(_ sequenceNumber: UInt64) -> RecognitionFrameReference {
    RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: 1),
      sequenceNumber: sequenceNumber
    )
  }

  private func makeActiveMonitoringCoordinator(
    clock: @escaping () -> TimeInterval = {
      ProcessInfo.processInfo.systemUptime
    }
  ) -> LaunchCoordinator {
    let coordinator = LaunchCoordinator(clock: clock)
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
    return coordinator
  }
}

private final class TestRecognitionClock {
  private(set) var nowValue: TimeInterval
  private(set) var readCount = 0

  init(now: TimeInterval) {
    nowValue = now
  }

  func now() -> TimeInterval {
    readCount += 1
    return nowValue
  }

  func advance(by interval: TimeInterval) {
    nowValue += interval
  }
}
