import SiglaunchCore
import XCTest

final class DomainExpansionTriggerTests: XCTestCase {
  func testThreeQualifiedTopClassificationsInLatestFiveTriggerPrimaryWorkflow() {
    let clock = TestClock(now: 100)
    let coordinator = makeActiveMonitoringCoordinator(clock: clock)
    let cases:
      [(
        classifications: [PersonalRecognizerClassification],
        expectedTriggerEffects: Effects
      )] = [
        (
          [classification("domain_expansion", 0.75), classification("other", 0.25)],
          [.presentDomainExpansionCandidateProgress(.init(poseMatchCount: 1))]
        ),
        (
          [classification("other", 0.8), classification("domain_expansion", 0.2)],
          []
        ),
        (
          [classification("domain_expansion", 0.9), classification("other", 0.1)],
          [.presentDomainExpansionCandidateProgress(.init(poseMatchCount: 2))]
        ),
        (
          [classification("other", 0.51), classification("domain_expansion", 0.49)],
          []
        ),
        (
          [classification("domain_expansion", 0.8), classification("other", 0.2)],
          [
            .presentDomainExpansionCandidateProgress(nil),
            .domainExpansionTriggered,
            .loadWorkflowConfiguration,
          ]
        ),
      ]

    for (index, testCase) in cases.enumerated() {
      let effects = completeFrame(
        UInt64(index + 1),
        classifications: testCase.classifications,
        with: coordinator
      )
      XCTAssertEqual(
        triggerEffects(in: effects),
        testCase.expectedTriggerEffects,
        "completed classification \(index + 1)"
      )
    }
  }

  func testPoseMatchRequiresExactTopLabelAtConfidenceThreshold() {
    let cases:
      [(
        name: String,
        classifications: [PersonalRecognizerClassification]?,
        isPoseMatch: Bool
      )] = [
        (
          "exact label at threshold",
          [classification("domain_expansion", 0.75), classification("other", 0.25)],
          true
        ),
        (
          "below threshold",
          [classification("domain_expansion", 0.749_999), classification("other", 0.25)],
          false
        ),
        (
          "exact label is not top",
          [classification("other", 0.8), classification("domain_expansion", 0.79)],
          false
        ),
        (
          "label is case sensitive",
          [classification("Domain_Expansion", 0.99), classification("other", 0.01)],
          false
        ),
        (
          "confidence is outside Core ML probability range",
          [classification("domain_expansion", 1.01)],
          false
        ),
        ("Diagnostic Gesture without a classification", nil, false),
      ]

    for testCase in cases {
      let coordinator = makeActiveMonitoringCoordinator()
      let effects = completeFrame(
        1,
        classifications: testCase.classifications,
        with: coordinator
      )
      XCTAssertEqual(
        candidateProgress(in: effects),
        testCase.isPoseMatch
          ? DomainExpansionCandidateProgress(poseMatchCount: 1)
          : nil,
        testCase.name
      )
      XCTAssertFalse(
        triggerEffects(in: effects).contains(.domainExpansionTriggered),
        testCase.name
      )
    }
  }

  func testRollingWindowDropsClassificationsOlderThanTheLatestFive() {
    let coordinator = makeActiveMonitoringCoordinator()
    _ = completeFrame(1, classifications: qualifiedMatch, with: coordinator)
    _ = completeFrame(2, classifications: qualifiedMatch, with: coordinator)
    _ = completeFrame(3, classifications: nonmatch, with: coordinator)
    _ = completeFrame(4, classifications: nonmatch, with: coordinator)
    _ = completeFrame(5, classifications: nonmatch, with: coordinator)

    let sixth = completeFrame(6, classifications: nonmatch, with: coordinator)
    XCTAssertEqual(
      candidateProgress(in: sixth),
      DomainExpansionCandidateProgress(poseMatchCount: 1)
    )
    _ = completeFrame(7, classifications: qualifiedMatch, with: coordinator)
    let eighth = completeFrame(
      8,
      classifications: qualifiedMatch,
      with: coordinator
    )
    XCTAssertEqual(
      candidateProgress(in: eighth),
      DomainExpansionCandidateProgress(poseMatchCount: 2)
    )
    let ninth = completeFrame(
      9,
      classifications: qualifiedMatch,
      with: coordinator
    )
    XCTAssertTrue(triggerEffects(in: ninth).contains(.domainExpansionTriggered))
  }

  func testOnlyFramesWithCompletedClassificationsEnterEvidenceWindow() {
    let coordinator = makeActiveMonitoringCoordinator()
    _ = completeFrame(1, classifications: qualifiedMatch, with: coordinator)
    _ = completeFrame(2, classifications: qualifiedMatch, with: coordinator)

    for sequenceNumber in 3...7 {
      let result: PersonalRecognizerInferenceResult =
        sequenceNumber.isMultiple(of: 2) ? .noHandDetected : .failed
      let unclassified = completeInferenceFrame(
        UInt64(sequenceNumber),
        result: result,
        with: coordinator
      )
      XCTAssertTrue(triggerEffects(in: unclassified).isEmpty)
    }

    let trigger = completeFrame(
      8,
      classifications: qualifiedMatch,
      with: coordinator
    )
    XCTAssertTrue(triggerEffects(in: trigger).contains(.domainExpansionTriggered))
  }

  func testRecognitionLifecycleEventsClearEvidenceAndCandidateProgress() {
    let cases: [(name: String, event: AppEvent)] = [
      ("pause", .pauseMonitoringRequested),
      (
        "capture interruption",
        .camera(
          .captureInterrupted(
            lifecycleID: RecognitionLifecycleID(rawValue: 1)
          )
        )
      ),
      ("system sleep", .camera(.systemWillSleep)),
      ("camera switch", .camera(.cameraSwitchDetected)),
      ("frame-rate lifecycle", .recognitionFrameRateRequested(.fps30)),
    ]

    for testCase in cases {
      let coordinator = makeActiveMonitoringCoordinator()
      _ = completeFrame(
        1,
        classifications: qualifiedMatch,
        with: coordinator
      )

      let effects = coordinator.handle(testCase.event)

      XCTAssertTrue(
        effects.contains(.clearRecognitionEvidence),
        testCase.name
      )
      XCTAssertTrue(
        effects.contains(.presentDomainExpansionCandidateProgress(nil)),
        testCase.name
      )
    }
  }

  func testPauseAndResumeCannotJoinEvidenceAcrossCaptureLifecycles() {
    let coordinator = makeActiveMonitoringCoordinator()
    _ = completeFrame(1, classifications: qualifiedMatch, with: coordinator)
    _ = coordinator.handle(.pauseMonitoringRequested)
    _ = coordinator.handle(.camera(.released))
    XCTAssertEqual(
      coordinator.handle(.resumeMonitoringRequested),
      [
        .clearRecognitionEvidence,
        .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
        .presentMenu(.awaitingCameraAuthorization),
        .camera(.requestAuthorization),
      ]
    )
    _ = coordinator.handle(.camera(.authorizationChanged(.authorized)))
    _ = coordinator.handle(
      .camera(
        .captureStartCompleted(
          lifecycleID: RecognitionLifecycleID(rawValue: 2),
          result: .succeeded
        )
      )
    )

    let first = completeFrame(
      1,
      classifications: qualifiedMatch,
      lifecycleID: 2,
      with: coordinator
    )
    let second = completeFrame(
      2,
      classifications: qualifiedMatch,
      lifecycleID: 2,
      with: coordinator
    )

    XCTAssertEqual(
      candidateProgress(in: first),
      DomainExpansionCandidateProgress(poseMatchCount: 1)
    )
    XCTAssertEqual(
      candidateProgress(in: second),
      DomainExpansionCandidateProgress(poseMatchCount: 2)
    )
    XCTAssertFalse(triggerEffects(in: second).contains(.domainExpansionTriggered))
  }

  func testLockedPoseStartsOneWorkflowUntilAbsenceAndCooldownPermitRearm() {
    let clock = TestClock(now: 100)
    let coordinator = makeActiveMonitoringCoordinator(clock: clock)

    let firstTrigger = trigger(with: coordinator)
    XCTAssertEqual(firstTrigger.filter { $0 == .loadWorkflowConfiguration }.count, 1)
    XCTAssertEqual(
      coordinator.handle(
        .workflowConfigurationLoadCompleted(.failed(.unavailable))
      ),
      [.primaryWorkflowFailed(.configuration(.unavailable))]
    )

    for sequenceNumber in 4...6 {
      let heldEffects = completeFrame(
        UInt64(sequenceNumber),
        classifications: qualifiedMatch,
        with: coordinator
      )
      XCTAssertTrue(triggerEffects(in: heldEffects).isEmpty)
    }

    clock.advance(by: 4)
    _ = completeInferenceFrame(
      7,
      result: .noHandDetected,
      with: coordinator
    )
    clock.advance(by: 1)
    let rearmed = completeInferenceFrame(
      8,
      result: .noHandDetected,
      with: coordinator
    )
    XCTAssertTrue(triggerEffects(in: rearmed).isEmpty)

    _ = completeFrame(9, classifications: qualifiedMatch, with: coordinator)
    _ = completeFrame(10, classifications: qualifiedMatch, with: coordinator)
    let secondTrigger = completeFrame(
      11,
      classifications: qualifiedMatch,
      with: coordinator
    )
    XCTAssertEqual(
      triggerEffects(in: secondTrigger),
      [
        .presentDomainExpansionCandidateProgress(nil),
        .domainExpansionTriggered,
        .loadWorkflowConfiguration,
      ]
    )
  }

  func testFailedInferenceInterruptsContinuousAbsence() {
    let clock = TestClock(now: 100)
    let coordinator = makeActiveMonitoringCoordinator(clock: clock)
    _ = trigger(with: coordinator)
    _ = coordinator.handle(
      .workflowConfigurationLoadCompleted(.failed(.unavailable))
    )

    clock.advance(by: 4)
    _ = completeInferenceFrame(
      4,
      result: .noHandDetected,
      with: coordinator
    )
    clock.advance(by: 0.5)
    _ = completeInferenceFrame(5, result: .failed, with: coordinator)
    clock.advance(by: 0.5)
    _ = completeInferenceFrame(
      6,
      result: .noHandDetected,
      with: coordinator
    )
    let stillLocked = completeFrame(
      7,
      classifications: qualifiedMatch,
      with: coordinator
    )
    XCTAssertNil(candidateProgress(in: stillLocked))

    _ = completeInferenceFrame(
      8,
      result: .noHandDetected,
      with: coordinator
    )
    clock.advance(by: 1)
    _ = completeInferenceFrame(
      9,
      result: .noHandDetected,
      with: coordinator
    )
    let firstNewMatch = completeFrame(
      10,
      classifications: qualifiedMatch,
      with: coordinator
    )
    XCTAssertEqual(
      candidateProgress(in: firstNewMatch),
      DomainExpansionCandidateProgress(poseMatchCount: 1)
    )
  }

  func testRearmRequiresContinuousAbsenceAndCooldownTogether() {
    let clock = TestClock(now: 100)
    let coordinator = makeActiveMonitoringCoordinator(clock: clock)
    _ = trigger(with: coordinator)
    _ = coordinator.handle(
      .workflowConfigurationLoadCompleted(.failed(.unavailable))
    )

    _ = completeFrame(4, classifications: nonmatch, with: coordinator)
    clock.advance(by: 1)
    _ = completeFrame(5, classifications: nonmatch, with: coordinator)
    let tooEarlyForCooldown = completeFrame(
      6,
      classifications: qualifiedMatch,
      with: coordinator
    )
    XCTAssertNil(candidateProgress(in: tooEarlyForCooldown))

    clock.advance(by: 4)
    _ = completeFrame(7, classifications: nonmatch, with: coordinator)
    clock.advance(by: 0.999)
    _ = completeFrame(8, classifications: nonmatch, with: coordinator)
    let tooEarlyForAbsence = completeFrame(
      9,
      classifications: qualifiedMatch,
      with: coordinator
    )
    XCTAssertNil(candidateProgress(in: tooEarlyForAbsence))

    _ = completeFrame(10, classifications: nonmatch, with: coordinator)
    clock.advance(by: 1)
    _ = completeFrame(11, classifications: nonmatch, with: coordinator)
    let firstNewMatch = completeFrame(
      12,
      classifications: qualifiedMatch,
      with: coordinator
    )
    XCTAssertEqual(
      candidateProgress(in: firstNewMatch),
      DomainExpansionCandidateProgress(poseMatchCount: 1)
    )
  }

  private func classification(
    _ label: String,
    _ confidence: Double
  ) -> PersonalRecognizerClassification {
    PersonalRecognizerClassification(label: label, confidence: confidence)
  }

  private var qualifiedMatch: [PersonalRecognizerClassification] {
    [classification("domain_expansion", 0.9), classification("other", 0.1)]
  }

  private var nonmatch: [PersonalRecognizerClassification] {
    [classification("other", 0.9), classification("domain_expansion", 0.1)]
  }

  private func trigger(with coordinator: LaunchCoordinator) -> Effects {
    _ = completeFrame(1, classifications: qualifiedMatch, with: coordinator)
    _ = completeFrame(2, classifications: qualifiedMatch, with: coordinator)
    return completeFrame(3, classifications: qualifiedMatch, with: coordinator)
  }

  private func completeFrame(
    _ sequenceNumber: UInt64,
    classifications: [PersonalRecognizerClassification]?,
    lifecycleID: UInt64 = 1,
    with coordinator: LaunchCoordinator
  ) -> Effects {
    completeInferenceFrame(
      sequenceNumber,
      result: classifications.map { .classified($0) } ?? .failed,
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
    let frame = RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: lifecycleID),
      sequenceNumber: sequenceNumber
    )
    _ = coordinator.handle(.recognitionFrameCaptured(frame))
    return coordinator.handle(
      .recognitionFrameCompleted(
        RecognitionFrameCompletion(
          frame: frame,
          diagnosticGesture: DiagnosticGestureResult(
            handDetection: result == .noHandDetected ? .notDetected : .detected,
            recognizedJointCount: result == .noHandDetected ? 0 : 21,
            extendedFingerCount: result == .noHandDetected ? 0 : 5,
            isOpenPalm: result != .noHandDetected
          ),
          personalRecognizerResult: result
        )
      )
    )
  }

  private func candidateProgress(
    in effects: Effects
  ) -> DomainExpansionCandidateProgress? {
    for effect in effects.reversed() {
      if case .presentDomainExpansionCandidateProgress(let progress) = effect {
        return progress
      }
    }
    return nil
  }

  private func triggerEffects(in effects: Effects) -> Effects {
    effects.filter { effect in
      switch effect {
      case .presentDomainExpansionCandidateProgress,
        .domainExpansionTriggered,
        .loadWorkflowConfiguration:
        true
      default:
        false
      }
    }
  }

  private func makeActiveMonitoringCoordinator(
    clock: TestClock? = nil
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
      _ = coordinator.handle(.recognitionClockRead(100))
    }
    return coordinator
  }
}

private final class TestClock {
  private(set) var value: TimeInterval
  private weak var coordinator: LaunchCoordinator?

  init(now: TimeInterval) {
    value = now
  }

  func connect(to coordinator: LaunchCoordinator) {
    self.coordinator = coordinator
    _ = coordinator.handle(.recognitionClockRead(value))
  }

  func advance(by interval: TimeInterval) {
    value += interval
    _ = coordinator?.handle(.recognitionClockRead(value))
  }
}
