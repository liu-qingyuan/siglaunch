import SiglaunchCore
import XCTest

private func captureInterrupted(
  lifecycleID: UInt64 = 1
) -> AppEvent {
  .camera(
    .captureInterrupted(
      lifecycleID: RecognitionLifecycleID(rawValue: lifecycleID)
    )
  )
}

private func captureInterruptionEnded(
  lifecycleID: UInt64 = 1
) -> AppEvent {
  .camera(
    .captureInterruptionEnded(
      lifecycleID: RecognitionLifecycleID(rawValue: lifecycleID)
    )
  )
}

private func captureStartCompleted(
  _ result: CameraCaptureStartResult,
  lifecycleID: UInt64 = 1
) -> AppEvent {
  .camera(
    .captureStartCompleted(
      lifecycleID: RecognitionLifecycleID(rawValue: lifecycleID),
      result: result
    )
  )
}

final class LaunchCoordinatorTests: XCTestCase {
  private typealias Step = (name: String, event: AppEvent, effects: Effects)

  private enum RecognizerTrainingPriorTestState: CaseIterable {
    case activeMonitoring
    case pausedMonitoring
    case setupRequired
  }

  private enum RecognizerTrainingFailureStage: CaseIterable {
    case training
    case candidateSave
    case modelReplacement
  }

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

  func testAvailablePersonalRecognizerAuthorizesAndStartsActiveMonitoring() {
    let coordinator = makeCoordinator(
      after: [
        .appLaunched,
        .menuBarApplicationConfigurationCompleted(.succeeded),
      ]
    )
    let steps: [Step] = [
      (
        "availability requests camera authorization without claiming capture",
        .personalRecognizerChecked(.available),
        [
          .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
          .presentMenu(.awaitingCameraAuthorization),
          .camera(.requestAuthorization),
        ]
      ),
      (
        "authorization starts only the built-in camera",
        .camera(.authorizationChanged(.authorized)),
        [startBuiltInCameraEffect()]
      ),
      (
        "capture confirmation enters Active Monitoring",
        captureStartCompleted(.succeeded),
        [.presentMenu(.activeMonitoring)]
      ),
      (
        "menu presentation completion has no further effects",
        .menuPresented(.activeMonitoring),
        []
      ),
      (
        "a stale missing result cannot replace Active Monitoring",
        .personalRecognizerChecked(.missing),
        []
      ),
    ]

    assertEffects(steps, from: coordinator)
  }

  func testCameraAuthorizationAndCaptureFailuresRemainDiagnosableAndRecoverable() {
    let authorizationFailures:
      [(status: CameraAuthorizationStatus, reason: CameraUnavailableReason)] = [
        (.denied, .authorizationDenied),
        (.restricted, .authorizationRestricted),
      ]

    for testCase in authorizationFailures {
      let coordinator = makeCoordinatorAwaitingCameraAuthorization()
      XCTAssertEqual(
        coordinator.handle(.camera(.authorizationChanged(testCase.status))),
        [.presentMenu(.cameraUnavailable(testCase.reason))],
        "authorization status: \(testCase.status)"
      )
      XCTAssertEqual(
        coordinator.handle(captureStartCompleted(.succeeded)),
        [],
        "unavailable authorization must not accept capture: \(testCase.status)"
      )
      XCTAssertEqual(
        coordinator.handle(.camera(.authorizationChanged(.authorized))),
        [startBuiltInCameraEffect()],
        "a later authorization event should recover: \(testCase.status)"
      )
    }

    let pending = makeCoordinatorAwaitingCameraAuthorization()
    XCTAssertEqual(
      pending.handle(.camera(.authorizationChanged(.notDetermined))),
      []
    )
    XCTAssertEqual(
      pending.handle(.camera(.authorizationChanged(.authorized))),
      [startBuiltInCameraEffect()]
    )

    let pausedWhileAwaitingAuthorization = makeCoordinatorAwaitingCameraAuthorization()
    XCTAssertEqual(
      pausedWhileAwaitingAuthorization.handle(.pauseMonitoringRequested),
      [
        .clearRecognitionEvidence,
        .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
        .presentMenu(.pausedMonitoring),
      ]
    )
    XCTAssertEqual(
      pausedWhileAwaitingAuthorization.handle(
        .camera(.authorizationChanged(.authorized))
      ),
      [],
      "a late authorization event must not override Paused Monitoring"
    )

    for failure in [
      CameraCaptureFailure.builtInCameraUnavailable,
      .configurationFailed,
      .startFailed,
    ] {
      let coordinator = makeCoordinatorStartingCamera()
      XCTAssertEqual(
        coordinator.handle(captureStartCompleted(.failed(failure))),
        [
          .clearRecognitionEvidence,
          .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
          .presentMenu(.cameraUnavailable(.capture(failure))),
        ],
        "capture failure: \(failure)"
      )
      XCTAssertEqual(
        coordinator.handle(.camera(.authorizationChanged(.authorized))),
        [startBuiltInCameraEffect(lifecycleID: 2)],
        "an authorization refresh should retry capture: \(failure)"
      )
    }
  }

  func testAuthorizationRevocationReleasesActiveCameraBeforeRecovery() {
    let cases: [(status: CameraAuthorizationStatus, reason: CameraUnavailableReason)] = [
      (.denied, .authorizationDenied),
      (.restricted, .authorizationRestricted),
    ]

    for testCase in cases {
      let coordinator = makeActiveMonitoringCoordinator()
      XCTAssertEqual(
        coordinator.handle(.camera(.authorizationChanged(testCase.status))),
        [
          .clearRecognitionEvidence,
          .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
          .camera(.stopAndReleaseCamera),
          .presentMenu(.cameraUnavailable(testCase.reason)),
        ]
      )
      XCTAssertEqual(
        coordinator.handle(.camera(.authorizationChanged(.authorized))),
        [],
        "recovery must wait for release: \(testCase.status)"
      )
      XCTAssertEqual(coordinator.handle(.camera(.released)), [])
      XCTAssertEqual(
        coordinator.handle(.camera(.authorizationChanged(.authorized))),
        [startBuiltInCameraEffect(lifecycleID: 2)]
      )
    }
  }

  func testPauseResumeAndQuitKeepCameraOwnershipAlignedWithMonitoring() {
    let coordinator = makeActiveMonitoringCoordinator()
    let steps: [Step] = [
      (
        "pause clears evidence and releases camera ownership",
        .pauseMonitoringRequested,
        [
          .clearRecognitionEvidence,
          .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
          .camera(.stopAndReleaseCamera),
        ]
      ),
      (
        "pause waits for release instead of claiming Paused Monitoring early",
        .pauseMonitoringRequested,
        []
      ),
      (
        "release confirmation enters Paused Monitoring",
        .camera(.released),
        [.presentMenu(.pausedMonitoring)]
      ),
      (
        "resume rechecks authorization before reacquiring the camera",
        .resumeMonitoringRequested,
        [
          .presentMenu(.awaitingCameraAuthorization),
          .camera(.requestAuthorization),
        ]
      ),
      (
        "authorized resume reacquires only the built-in camera",
        .camera(.authorizationChanged(.authorized)),
        [startBuiltInCameraEffect(lifecycleID: 2)]
      ),
      (
        "capture confirmation restores Active Monitoring",
        captureStartCompleted(.succeeded, lifecycleID: 2),
        [.presentMenu(.activeMonitoring)]
      ),
      (
        "quit clears evidence and releases before terminating",
        .quitRequested,
        [
          .clearRecognitionEvidence,
          .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
          .camera(.stopAndReleaseCamera),
        ]
      ),
      (
        "quit cannot terminate before release confirmation",
        .quitRequested,
        []
      ),
      (
        "release confirmation terminates exactly once",
        .camera(.released),
        [.terminateApplication]
      ),
      (
        "stale release confirmation has no effect",
        .camera(.released),
        []
      ),
    ]

    assertEffects(steps, from: coordinator)

    let paused = makeActiveMonitoringCoordinator()
    _ = paused.handle(.pauseMonitoringRequested)
    _ = paused.handle(.camera(.released))
    XCTAssertEqual(paused.handle(.quitRequested), [.terminateApplication])
  }

  func testCaptureInterruptionClearsEvidenceAndHonorsCurrentMonitoringIntent() {
    let active = makeActiveMonitoringCoordinator()
    let activeSteps: [Step] = [
      (
        "interruption stops frame delivery and clears recognition evidence",
        captureInterrupted(),
        [
          .clearRecognitionEvidence,
          .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
          .camera(.stopCapture),
          .presentMenu(.captureInterrupted),
        ]
      ),
      (
        "interruption end resumes while the user still wants Active Monitoring",
        captureInterruptionEnded(),
        [startBuiltInCameraEffect(lifecycleID: 2)]
      ),
      (
        "resumed capture restores Active Monitoring",
        captureStartCompleted(.succeeded, lifecycleID: 2),
        [.presentMenu(.activeMonitoring)]
      ),
    ]
    assertEffects(activeSteps, from: active)

    let pausedDuringInterruption = makeActiveMonitoringCoordinator()
    XCTAssertEqual(
      pausedDuringInterruption.handle(captureInterrupted()),
      [
        .clearRecognitionEvidence,
        .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
        .camera(.stopCapture),
        .presentMenu(.captureInterrupted),
      ]
    )
    XCTAssertEqual(
      pausedDuringInterruption.handle(.pauseMonitoringRequested),
      [.camera(.stopAndReleaseCamera)]
    )
    XCTAssertEqual(
      pausedDuringInterruption.handle(captureInterruptionEnded()),
      [],
      "interruption end must not override a later Pause request"
    )
    XCTAssertEqual(
      pausedDuringInterruption.handle(.camera(.released)),
      [.presentMenu(.pausedMonitoring)]
    )
  }

  func testSleepWakeReleasesCameraAndRestoresOnlyActiveMonitoringIntent() {
    let wakeBeforeRelease = makeActiveMonitoringCoordinator()
    let activeSteps: [Step] = [
      (
        "sleep clears evidence and begins camera release",
        .camera(.systemWillSleep),
        [
          .clearRecognitionEvidence,
          .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
          .camera(.stopAndReleaseCamera),
          .presentMenu(.captureInterrupted),
        ]
      ),
      (
        "wake cannot reacquire before the old camera is released",
        .camera(.systemDidWake),
        []
      ),
      (
        "release after wake reacquires for the prior Active intent",
        .camera(.released),
        [startBuiltInCameraEffect(lifecycleID: 2)]
      ),
      (
        "reacquired capture restores Active Monitoring",
        captureStartCompleted(.succeeded, lifecycleID: 2),
        [.presentMenu(.activeMonitoring)]
      ),
    ]
    assertEffects(activeSteps, from: wakeBeforeRelease)

    let wakeAfterRelease = makeActiveMonitoringCoordinator()
    _ = wakeAfterRelease.handle(.camera(.systemWillSleep))
    XCTAssertEqual(wakeAfterRelease.handle(.camera(.released)), [])
    XCTAssertEqual(
      wakeAfterRelease.handle(.camera(.systemDidWake)),
      [startBuiltInCameraEffect(lifecycleID: 2)]
    )

    let paused = makeActiveMonitoringCoordinator()
    _ = paused.handle(.pauseMonitoringRequested)
    _ = paused.handle(.camera(.released))
    XCTAssertEqual(
      paused.handle(.camera(.systemWillSleep)),
      [
        .clearRecognitionEvidence,
        .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
      ]
    )
    XCTAssertEqual(
      paused.handle(.camera(.systemDidWake)),
      [],
      "a pre-sleep Paused intent must remain released"
    )

    let pausedWhileSleeping = makeActiveMonitoringCoordinator()
    _ = pausedWhileSleeping.handle(.camera(.systemWillSleep))
    XCTAssertEqual(pausedWhileSleeping.handle(.pauseMonitoringRequested), [])
    _ = pausedWhileSleeping.handle(.camera(.released))
    XCTAssertEqual(
      pausedWhileSleeping.handle(.camera(.systemDidWake)),
      [.presentMenu(.pausedMonitoring)]
    )
  }

  func testCameraSwitchRebuildsOnlyActiveBuiltInCaptureWithoutWorkflowEffects() {
    let active = makeActiveMonitoringCoordinator()
    XCTAssertEqual(
      active.handle(.camera(.cameraSwitchDetected)),
      [
        .clearRecognitionEvidence,
        .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
        rebuildBuiltInCameraEffect(),
        .presentMenu(.captureInterrupted),
      ]
    )
    XCTAssertEqual(
      active.handle(captureStartCompleted(.succeeded, lifecycleID: 2)),
      [.presentMenu(.activeMonitoring)]
    )

    let paused = makeActiveMonitoringCoordinator()
    _ = paused.handle(.pauseMonitoringRequested)
    _ = paused.handle(.camera(.released))
    XCTAssertEqual(
      paused.handle(.camera(.cameraSwitchDetected)),
      [
        .clearRecognitionEvidence,
        .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
      ],
      "a camera switch must not reacquire capture while Paused Monitoring"
    )
  }

  func testSetupRequiredPoseDatasetImportReachesDatasetReadyThroughPublicEffects() {
    let coordinator = makeSetupRequiredCoordinator()
    let selectedPath = "/Users/developer/Pose Dataset"
    let progress = PoseDatasetPreparationProgress(
      label: .domainExpansion,
      processedImageCount: 7,
      totalImageCount: 24
    )
    let input = makeTrainingInput()
    let steps: [Step] = [
      (
        "Setup Required offers the system folder picker",
        .poseDatasetImportRequested,
        [
          .presentPoseDatasetImport(.choosingFolder),
          .selectPoseDatasetFolder,
        ]
      ),
      (
        "a duplicate request cannot open a second picker",
        .poseDatasetImportRequested,
        []
      ),
      (
        "the selected root starts production preparation",
        .poseDatasetFolderSelectionCompleted(.selected(path: selectedPath)),
        [
          .presentPoseDatasetImport(.validating(nil)),
          .preparePoseDataset(at: selectedPath),
        ]
      ),
      (
        "production progress remains observable at the coordinator seam",
        .poseDatasetPreparationProgressed(progress),
        [.presentPoseDatasetImport(.validating(progress))]
      ),
      (
        "validated normalized samples become local training input only",
        .poseDatasetPreparationCompleted(.succeeded(input)),
        [.presentPoseDatasetImport(.ready(input))]
      ),
      (
        "a stale completion cannot replace the ready input",
        .poseDatasetPreparationCompleted(
          .failed(.rootDirectoryUnavailable(.missing))
        ),
        []
      ),
      (
        "Dataset Ready permits an explicit replacement import",
        .poseDatasetImportRequested,
        [
          .presentPoseDatasetImport(.choosingFolder),
          .selectPoseDatasetFolder,
        ]
      ),
    ]

    assertEffects(steps, from: coordinator)
  }

  func testFirstRecognizerTrainingSavesAndReplacesBeforeStartingMonitoring() {
    let coordinator = makeCoordinatorWithReadyPoseDataset()
    let input = makeTrainingInput()
    let progress = RecognizerTrainingProgress(
      completedUnitCount: 4,
      totalUnitCount: 10
    )
    let artifact = RecognizerTrainingArtifact(path: "/tmp/PersonalRecognizer.mlmodel")
    let candidate = PersonalRecognizerCandidate(identifier: "candidate-1")
    let steps: [Step] = [
      (
        "validated normalized samples start local training",
        .recognizerTrainingRequested,
        [
          .presentRecognizerTraining(.training(nil)),
          .startRecognizerTraining(input),
        ]
      ),
      (
        "Create ML progress remains observable",
        .recognizerTrainingProgressed(progress),
        [.presentRecognizerTraining(.training(progress))]
      ),
      (
        "a trained artifact is saved as a candidate before activation",
        .recognizerTrainingCompleted(.succeeded(artifact)),
        [
          .presentRecognizerTraining(.saving),
          .savePersonalRecognizerCandidate(artifact),
        ]
      ),
      (
        "a reliable candidate is atomically activated",
        .personalRecognizerCandidateSaveCompleted(.succeeded(candidate)),
        [
          .presentRecognizerTraining(.replacing),
          .replacePersonalRecognizer(candidate),
        ]
      ),
      (
        "first replacement clears evidence and starts Active Monitoring",
        .personalRecognizerReplacementCompleted(.succeeded),
        [
          .clearRecognitionEvidence,
          .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
          .presentRecognizerTraining(.succeeded),
          .presentMenu(.awaitingCameraAuthorization),
          .camera(.requestAuthorization),
        ]
      ),
      (
        "authorization acquires the built-in camera only after replacement",
        .camera(.authorizationChanged(.authorized)),
        [startBuiltInCameraEffect()]
      ),
      (
        "capture confirmation enters Active Monitoring",
        captureStartCompleted(.succeeded),
        [.presentMenu(.activeMonitoring)]
      ),
    ]

    assertEffects(steps, from: coordinator)
  }

  func testRecognizerTrainingProgressAndCancellationRestoreEveryPriorState() {
    let progress = RecognizerTrainingProgress(
      completedUnitCount: 7,
      totalUnitCount: 10
    )

    for priorState in RecognizerTrainingPriorTestState.allCases {
      let coordinator = makeCoordinatorReadyToTrain(from: priorState)
      let startEffects = coordinator.handle(.recognizerTrainingRequested)

      switch priorState {
      case .activeMonitoring:
        XCTAssertEqual(
          startEffects,
          [
            .presentRecognizerTraining(.preparing),
            .clearRecognitionEvidence,
            .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
            .camera(.stopAndReleaseCamera),
          ]
        )
        XCTAssertEqual(
          coordinator.handle(.recognizerTrainingProgressed(progress)),
          [],
          "progress cannot arrive before camera release"
        )
        XCTAssertEqual(
          coordinator.handle(.camera(.released)),
          [
            .presentRecognizerTraining(.training(nil)),
            .startRecognizerTraining(makeTrainingInput()),
          ]
        )
      case .pausedMonitoring, .setupRequired:
        XCTAssertEqual(
          startEffects,
          [
            .presentRecognizerTraining(.training(nil)),
            .startRecognizerTraining(makeTrainingInput()),
          ]
        )
      }

      XCTAssertEqual(
        coordinator.handle(.recognizerTrainingProgressed(progress)),
        [.presentRecognizerTraining(.training(progress))],
        "prior state: \(priorState)"
      )
      XCTAssertEqual(
        coordinator.handle(.recognizerTrainingCancellationRequested),
        [
          .presentRecognizerTraining(.cancelling),
          .cancelRecognizerTraining,
        ],
        "prior state: \(priorState)"
      )

      let restoration = coordinator.handle(
        .recognizerTrainingCompleted(.cancelled)
      )
      switch priorState {
      case .activeMonitoring:
        XCTAssertEqual(
          restoration,
          [
            .presentRecognizerTraining(.cancelled),
            .presentMenu(.awaitingCameraAuthorization),
            .camera(.requestAuthorization),
          ]
        )
      case .pausedMonitoring:
        XCTAssertEqual(
          restoration,
          [
            .presentRecognizerTraining(.cancelled),
            .presentMenu(.pausedMonitoring),
          ]
        )
      case .setupRequired:
        XCTAssertEqual(
          restoration,
          [.presentRecognizerTraining(.cancelled)]
        )
      }

      XCTAssertEqual(
        coordinator.handle(
          .recognizerTrainingCompleted(
            .succeeded(RecognizerTrainingArtifact(path: "/tmp/stale.mlmodel"))
          )
        ),
        [],
        "a stale success cannot save or replace a model"
      )
    }
  }

  func testSuccessfulRecognizerReplacementRestoresActiveAndPausedIntent() {
    let artifact = RecognizerTrainingArtifact(path: "/tmp/replacement.mlmodel")
    let candidate = PersonalRecognizerCandidate(identifier: "replacement")

    for priorState in [
      RecognizerTrainingPriorTestState.activeMonitoring,
      .pausedMonitoring,
    ] {
      let coordinator = makeCoordinatorReadyToTrain(from: priorState)
      _ = coordinator.handle(.recognizerTrainingRequested)
      if priorState == .activeMonitoring {
        _ = coordinator.handle(.camera(.released))
      }
      _ = coordinator.handle(
        .recognizerTrainingCompleted(.succeeded(artifact))
      )
      _ = coordinator.handle(
        .personalRecognizerCandidateSaveCompleted(.succeeded(candidate))
      )

      let effects = coordinator.handle(
        .personalRecognizerReplacementCompleted(.succeeded)
      )
      switch priorState {
      case .activeMonitoring:
        XCTAssertEqual(
          effects,
          [
            .clearRecognitionEvidence,
            .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
            .presentRecognizerTraining(.succeeded),
            .presentMenu(.awaitingCameraAuthorization),
            .camera(.requestAuthorization),
          ]
        )
        XCTAssertEqual(
          coordinator.handle(.camera(.authorizationChanged(.authorized))),
          [startBuiltInCameraEffect(lifecycleID: 2)]
        )
      case .pausedMonitoring:
        XCTAssertEqual(
          effects,
          [
            .clearRecognitionEvidence,
            .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
            .presentRecognizerTraining(.succeeded),
            .presentMenu(.pausedMonitoring),
          ]
        )
        XCTAssertEqual(
          coordinator.handle(.camera(.authorizationChanged(.authorized))),
          [],
          "Paused Monitoring must not reacquire the camera"
        )
      case .setupRequired:
        XCTFail("not part of this replacement table")
      }
    }
  }

  func testEveryRecognizerTrainingFailureStageRestoresEveryPriorState() {
    let artifact = RecognizerTrainingArtifact(path: "/tmp/replacement.mlmodel")
    let candidate = PersonalRecognizerCandidate(identifier: "replacement")

    for priorState in RecognizerTrainingPriorTestState.allCases {
      for stage in RecognizerTrainingFailureStage.allCases {
        let coordinator = makeCoordinatorReadyToTrain(from: priorState)
        _ = coordinator.handle(.recognizerTrainingRequested)
        if priorState == .activeMonitoring {
          _ = coordinator.handle(.camera(.released))
        }

        let presentation: RecognizerTrainingPresentation
        switch stage {
        case .training:
          presentation = .failed(.training(.trainingFailed))
          XCTAssertEqual(
            coordinator.handle(
              .recognizerTrainingCompleted(.failed(.trainingFailed))
            ),
            expectedRecognizerTrainingRestoration(
              for: priorState,
              presentation: presentation
            )
          )
        case .candidateSave:
          _ = coordinator.handle(
            .recognizerTrainingCompleted(.succeeded(artifact))
          )
          presentation = .failed(.candidateSave(.storageUnavailable))
          XCTAssertEqual(
            coordinator.handle(
              .personalRecognizerCandidateSaveCompleted(
                .failed(.storageUnavailable)
              )
            ),
            expectedRecognizerTrainingRestoration(
              for: priorState,
              presentation: presentation
            )
          )
        case .modelReplacement:
          _ = coordinator.handle(
            .recognizerTrainingCompleted(.succeeded(artifact))
          )
          _ = coordinator.handle(
            .personalRecognizerCandidateSaveCompleted(.succeeded(candidate))
          )
          presentation = .failed(.modelReplacement(.replacementFailed))
          XCTAssertEqual(
            coordinator.handle(
              .personalRecognizerReplacementCompleted(
                .failed(.replacementFailed)
              )
            ),
            expectedRecognizerTrainingRestoration(
              for: priorState,
              presentation: presentation
            )
          )
        }

        XCTAssertEqual(
          coordinator.handle(.personalRecognizerReplacementCompleted(.succeeded)),
          [],
          "a stale replacement cannot activate after \(stage) failure from \(priorState)"
        )
      }
    }
  }

  func testPoseDatasetFolderCancellationReturnsToSetupRequired() {
    let coordinator = makeSetupRequiredCoordinator()
    XCTAssertEqual(
      coordinator.handle(.poseDatasetImportRequested),
      [
        .presentPoseDatasetImport(.choosingFolder),
        .selectPoseDatasetFolder,
      ]
    )
    XCTAssertEqual(
      coordinator.handle(.poseDatasetFolderSelectionCompleted(.cancelled)),
      [.presentPoseDatasetImport(nil)]
    )
    XCTAssertEqual(
      coordinator.handle(
        .poseDatasetFolderSelectionCompleted(.selected(path: "/stale"))
      ),
      []
    )
    XCTAssertEqual(
      coordinator.handle(.poseDatasetImportRequested),
      [
        .presentPoseDatasetImport(.choosingFolder),
        .selectPoseDatasetFolder,
      ]
    )
  }

  func testPoseDatasetValidationFailuresReportAndPermitAnotherImport() {
    let summary = PoseDatasetSummary(
      domainExpansion: PoseDatasetLabelSummary(
        validImageCount: 9,
        handlessImageCount: 2,
        unreadableImageCount: 1
      ),
      other: PoseDatasetLabelSummary(
        validImageCount: 10,
        handlessImageCount: 0,
        unreadableImageCount: 3
      )
    )
    let failures: [PoseDatasetImportFailure] = [
      .rootDirectoryUnavailable(.unreadable),
      .labelDirectoryUnavailable(label: .domainExpansion, reason: .missing),
      .labelDirectoryUnavailable(label: .other, reason: .notDirectory),
      .insufficientValidImages(summary: summary, minimumPerLabel: 10),
      .preparationFailed(summary: summary),
      .outputUnavailable,
    ]

    for failure in failures {
      let coordinator = makeCoordinatorValidatingPoseDataset()
      XCTAssertEqual(
        coordinator.handle(.poseDatasetPreparationCompleted(.failed(failure))),
        [.presentPoseDatasetImport(.failed(failure))],
        "failure: \(failure)"
      )
      XCTAssertEqual(
        coordinator.handle(.poseDatasetImportRequested),
        [
          .presentPoseDatasetImport(.choosingFolder),
          .selectPoseDatasetFolder,
        ],
        "failure should return to Setup Required: \(failure)"
      )
    }
  }

  func testActiveAndPausedMonitoringCanPrepareReplacementTrainingInput() {
    for priorState in [
      RecognizerTrainingPriorTestState.activeMonitoring,
      .pausedMonitoring,
    ] {
      let coordinator = makeWorkflowReadyCoordinator()
      if priorState == .pausedMonitoring {
        _ = coordinator.handle(.pauseMonitoringRequested)
        _ = coordinator.handle(.camera(.released))
      }
      let input = makeTrainingInput()
      let selectedPath = "/Users/developer/Replacement Pose Dataset"

      XCTAssertEqual(
        coordinator.handle(.poseDatasetImportRequested),
        [
          .presentPoseDatasetImport(.choosingFolder),
          .selectPoseDatasetFolder,
        ],
        "prior state: \(priorState)"
      )
      XCTAssertEqual(
        coordinator.handle(
          .poseDatasetFolderSelectionCompleted(.selected(path: selectedPath))
        ),
        [
          .presentPoseDatasetImport(.validating(nil)),
          .preparePoseDataset(at: selectedPath),
        ]
      )
      XCTAssertEqual(
        coordinator.handle(.poseDatasetPreparationCompleted(.succeeded(input))),
        [.presentPoseDatasetImport(.ready(input))]
      )

      let trainingEffects = coordinator.handle(.recognizerTrainingRequested)
      switch priorState {
      case .activeMonitoring:
        XCTAssertEqual(
          trainingEffects,
          [
            .presentRecognizerTraining(.preparing),
            .clearRecognitionEvidence,
            .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
            .camera(.stopAndReleaseCamera),
          ]
        )
      case .pausedMonitoring:
        XCTAssertEqual(
          trainingEffects,
          [
            .presentRecognizerTraining(.training(nil)),
            .startRecognizerTraining(input),
          ]
        )
      case .setupRequired:
        XCTFail("not part of this replacement table")
      }
    }
  }

  func testRecognizerTrainingRequiresAValidatedPoseDatasetInput() {
    let setupRequired = makeSetupRequiredCoordinator()
    XCTAssertEqual(setupRequired.handle(.recognizerTrainingRequested), [])

    let existingRecognizer = makeWorkflowReadyCoordinator()
    XCTAssertEqual(existingRecognizer.handle(.recognizerTrainingRequested), [])
    XCTAssertEqual(
      existingRecognizer.handle(
        .recognizerTrainingProgressed(
          RecognizerTrainingProgress(completedUnitCount: 1, totalUnitCount: 2)
        )
      ),
      []
    )
  }

  func testQuitDuringRecognizerTrainingCancelsWorkAndWaitsForCameraRelease() {
    let setupRequired = makeCoordinatorWithReadyPoseDataset()
    _ = setupRequired.handle(.recognizerTrainingRequested)
    XCTAssertEqual(
      setupRequired.handle(.quitRequested),
      [.cancelRecognizerTraining, .terminateApplication]
    )
    XCTAssertEqual(setupRequired.handle(.quitRequested), [])

    let active = makeCoordinatorReadyToTrain(from: .activeMonitoring)
    _ = active.handle(.recognizerTrainingRequested)
    XCTAssertEqual(
      active.handle(.quitRequested),
      [],
      "termination must wait for the in-flight camera release"
    )
    XCTAssertEqual(
      active.handle(.camera(.released)),
      [.terminateApplication]
    )
    XCTAssertEqual(active.handle(.camera(.released)), [])
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
        "awaiting camera authorization",
        [
          .appLaunched,
          .menuBarApplicationConfigurationCompleted(.succeeded),
          .personalRecognizerChecked(.available),
          .menuPresented(.awaitingCameraAuthorization),
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
      (
        "choosing a Pose Dataset folder",
        [
          .appLaunched,
          .menuBarApplicationConfigurationCompleted(.succeeded),
          .personalRecognizerChecked(.missing),
          .menuPresented(.setupRequired),
          .poseDatasetImportRequested,
        ]
      ),
      (
        "validating a Pose Dataset",
        [
          .appLaunched,
          .menuBarApplicationConfigurationCompleted(.succeeded),
          .personalRecognizerChecked(.missing),
          .menuPresented(.setupRequired),
          .poseDatasetImportRequested,
          .poseDatasetFolderSelectionCompleted(.selected(path: "/Pose Dataset")),
        ]
      ),
      (
        "Pose Dataset ready",
        [
          .appLaunched,
          .menuBarApplicationConfigurationCompleted(.succeeded),
          .personalRecognizerChecked(.missing),
          .menuPresented(.setupRequired),
          .poseDatasetImportRequested,
          .poseDatasetFolderSelectionCompleted(.selected(path: "/Pose Dataset")),
          .poseDatasetPreparationCompleted(.succeeded(makeTrainingInput())),
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

  func testHerdrQueryWithoutMatchingAgentStartsConfiguredPiInWorkspace() {
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
        .startPiAgent(
          workspacePath: workflowConfiguration.workspacePath,
          command: workflowConfiguration.piCommand
        )
      ]
    )
    XCTAssertEqual(coordinator.handle(.herdrAgentQueryCompleted(.agents([]))), [])
  }

  func testPiStartSuccessCompletesWorkflowOnce() {
    let coordinator = makeCoordinatorQueryingHerdrAgents()
    _ = coordinator.handle(.herdrAgentQueryCompleted(.agents([])))

    XCTAssertEqual(
      coordinator.handle(.herdrAgentStartCompleted(.succeeded)),
      [
        .primaryWorkflowPiAgentStarted(
          PrimaryWorkflowContext(
            configuration: workflowConfiguration,
            defaultHerdrSession: .reused
          )
        )
      ]
    )
    XCTAssertEqual(coordinator.handle(.herdrAgentStartCompleted(.succeeded)), [])
  }

  func testPiStartFailureStopsWorkflowUntilANewTrigger() {
    let coordinator = makeCoordinatorQueryingHerdrAgents()
    _ = coordinator.handle(.herdrAgentQueryCompleted(.agents([])))

    XCTAssertEqual(
      coordinator.handle(.herdrAgentStartCompleted(.failed)),
      [.primaryWorkflowFailed(.piStartFailed)]
    )
    XCTAssertEqual(coordinator.handle(.herdrAgentStartCompleted(.succeeded)), [])
    XCTAssertEqual(
      coordinator.handle(.primaryWorkflowRequested),
      [.loadWorkflowConfiguration]
    )
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

  private func startBuiltInCameraEffect(
    lifecycleID: UInt64 = 1,
    targetFrameRate: RecognitionFrameRate = .fps15
  ) -> AppEffect {
    .camera(
      .startBuiltInCamera(
        targetFrameRate: targetFrameRate,
        lifecycleID: RecognitionLifecycleID(rawValue: lifecycleID)
      )
    )
  }

  private func rebuildBuiltInCameraEffect(
    lifecycleID: UInt64 = 2,
    targetFrameRate: RecognitionFrameRate = .fps15
  ) -> AppEffect {
    .camera(
      .rebuildBuiltInCamera(
        targetFrameRate: targetFrameRate,
        lifecycleID: RecognitionLifecycleID(rawValue: lifecycleID)
      )
    )
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

  private func makeCoordinatorAwaitingCameraAuthorization() -> LaunchCoordinator {
    makeCoordinator(
      after: [
        .appLaunched,
        .menuBarApplicationConfigurationCompleted(.succeeded),
        .personalRecognizerChecked(.available),
      ]
    )
  }

  private func makeCoordinatorStartingCamera() -> LaunchCoordinator {
    makeCoordinator(
      after: [
        .appLaunched,
        .menuBarApplicationConfigurationCompleted(.succeeded),
        .personalRecognizerChecked(.available),
        .camera(.authorizationChanged(.authorized)),
      ]
    )
  }

  private func makeActiveMonitoringCoordinator() -> LaunchCoordinator {
    makeCoordinator(
      after: [
        .appLaunched,
        .menuBarApplicationConfigurationCompleted(.succeeded),
        .personalRecognizerChecked(.available),
        .camera(.authorizationChanged(.authorized)),
        captureStartCompleted(.succeeded),
        .menuPresented(.activeMonitoring),
      ]
    )
  }

  private func makeWorkflowReadyCoordinator() -> LaunchCoordinator {
    makeActiveMonitoringCoordinator()
  }

  private func makeSetupRequiredCoordinator() -> LaunchCoordinator {
    makeCoordinator(
      after: [
        .appLaunched,
        .menuBarApplicationConfigurationCompleted(.succeeded),
        .personalRecognizerChecked(.missing),
        .menuPresented(.setupRequired),
      ]
    )
  }

  private func expectedRecognizerTrainingRestoration(
    for priorState: RecognizerTrainingPriorTestState,
    presentation: RecognizerTrainingPresentation
  ) -> Effects {
    switch priorState {
    case .activeMonitoring:
      [
        .presentRecognizerTraining(presentation),
        .presentMenu(.awaitingCameraAuthorization),
        .camera(.requestAuthorization),
      ]
    case .pausedMonitoring:
      [
        .presentRecognizerTraining(presentation),
        .presentMenu(.pausedMonitoring),
      ]
    case .setupRequired:
      [.presentRecognizerTraining(presentation)]
    }
  }

  private func makeCoordinatorReadyToTrain(
    from priorState: RecognizerTrainingPriorTestState
  ) -> LaunchCoordinator {
    let coordinator = makeCoordinatorWithReadyPoseDataset()
    guard priorState != .setupRequired else { return coordinator }

    _ = coordinator.handle(.recognizerTrainingRequested)
    _ = coordinator.handle(
      .recognizerTrainingCompleted(
        .succeeded(RecognizerTrainingArtifact(path: "/tmp/initial.mlmodel"))
      )
    )
    _ = coordinator.handle(
      .personalRecognizerCandidateSaveCompleted(
        .succeeded(PersonalRecognizerCandidate(identifier: "initial"))
      )
    )
    _ = coordinator.handle(
      .personalRecognizerReplacementCompleted(.succeeded)
    )
    _ = coordinator.handle(.camera(.authorizationChanged(.authorized)))
    _ = coordinator.handle(captureStartCompleted(.succeeded))

    if priorState == .pausedMonitoring {
      _ = coordinator.handle(.pauseMonitoringRequested)
      _ = coordinator.handle(.camera(.released))
    }
    return coordinator
  }

  private func makeCoordinatorWithReadyPoseDataset() -> LaunchCoordinator {
    let coordinator = makeCoordinatorValidatingPoseDataset()
    _ = coordinator.handle(
      .poseDatasetPreparationCompleted(.succeeded(makeTrainingInput()))
    )
    return coordinator
  }

  private func makeCoordinatorValidatingPoseDataset() -> LaunchCoordinator {
    let coordinator = makeSetupRequiredCoordinator()
    _ = coordinator.handle(.poseDatasetImportRequested)
    _ = coordinator.handle(
      .poseDatasetFolderSelectionCompleted(.selected(path: "/Pose Dataset"))
    )
    return coordinator
  }

  private func makeTrainingInput() -> PoseDatasetTrainingInput {
    let directoryPath = "/Application Support/Siglaunch/Pose Datasets/prepared"
    let summary = PoseDatasetSummary(
      domainExpansion: PoseDatasetLabelSummary(
        validImageCount: 10,
        handlessImageCount: 1,
        unreadableImageCount: 2
      ),
      other: PoseDatasetLabelSummary(
        validImageCount: 11,
        handlessImageCount: 3,
        unreadableImageCount: 4
      )
    )
    let sampleCounts: [(PoseDatasetLabel, Int)] = [
      (.domainExpansion, summary.domainExpansion.validImageCount),
      (.other, summary.other.validImageCount),
    ]
    let samples = sampleCounts.flatMap { label, count in
      (0..<count).map { index in
        PoseDatasetSample(
          label: label,
          imagePath: "\(directoryPath)/\(label.rawValue)/\(index).png"
        )
      }
    }
    return PoseDatasetTrainingInput(
      directoryPath: directoryPath,
      samples: samples,
      summary: summary
    )!
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
