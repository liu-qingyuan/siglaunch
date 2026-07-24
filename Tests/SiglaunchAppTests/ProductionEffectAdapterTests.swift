import CoreGraphics
import CoreVideo
import SiglaunchCore
import XCTest

@testable import SiglaunchApp

@MainActor
final class ProductionEffectAdapterTests: XCTestCase {
  func testExistingPiBranchOnlyQueriesHerdrThroughCoordinatorLoop() {
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
    let existingAgent = HerdrAgent(
      paneID: "pane-existing-pi",
      agent: "pi",
      cwd: "/Users/developer/work/llm-abm-marketing-sim",
      foregroundCwd: nil
    )
    let herdrAdapter = FakeHerdrAgentAdapter(
      queryResult: .agents([existingAgent])
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
        .queryHerdrAgents(attemptID: 1, phase: .initial),
        .primaryWorkflowPiAgentPreserved,
      ]
    )
    XCTAssertEqual(configurationLoader.loadCount, 0)
    XCTAssertEqual(ghosttyAdapter.resolutionCount, 0)
    XCTAssertEqual(ghosttyAdapter.launchedPaths, [])
    XCTAssertEqual(ghosttyAdapter.sessionEnsureCount, 0)
    XCTAssertEqual(herdrAdapter.queryCount, 1)
    XCTAssertEqual(herdrAdapter.startedConfigurations, [])
    XCTAssertEqual(workflowPresentations, [.piAgentPreserved])
  }

  func testFakeAdaptersDriveColdPiStartThroughCoordinatorLoop() {
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
          isRunning: true
        )
      ),
      launchResult: .succeeded,
      sessionResult: .ready(.reused)
    )
    let herdrAdapter = FakeHerdrAgentAdapter(
      queryResult: .agents([]),
      startResult: .succeeded
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
        .queryHerdrAgents(attemptID: 1, phase: .initial),
        .loadWorkflowConfiguration,
        .resolveGhostty,
        .ensureDefaultHerdrSession,
        .queryHerdrAgents(attemptID: 1, phase: .postBootstrap),
        .startPiAgent(
          workspacePath: configuration.workspacePath,
          command: configuration.piCommand
        ),
        .primaryWorkflowPiAgentStarted(
          PrimaryWorkflowContext(
            configuration: configuration,
            defaultHerdrSession: .reused
          )
        ),
      ]
    )
    XCTAssertEqual(configurationLoader.loadCount, 1)
    XCTAssertEqual(ghosttyAdapter.resolutionCount, 1)
    XCTAssertEqual(ghosttyAdapter.launchedPaths, [])
    XCTAssertEqual(ghosttyAdapter.sessionEnsureCount, 1)
    XCTAssertEqual(herdrAdapter.queryCount, 2)
    XCTAssertEqual(herdrAdapter.startedConfigurations, [configuration])
    XCTAssertEqual(workflowPresentations, [nil, .piAgentStarted])
  }

  func testFakeCameraAdapterDrivesMonitoringLifecycleThroughCoordinatorLoop() {
    let cameraAdapter = FakeCameraAdapter()
    let coordinator = LaunchCoordinator()
    for event in [
      AppEvent.appLaunched,
      .menuBarApplicationConfigurationCompleted(.succeeded),
    ] {
      _ = coordinator.handle(event)
    }

    var observedEffects: [AppEffect] = []
    var menuPresentations: [MenuPresentation] = []
    var sendEvent: ((AppEvent) -> Void)!
    var effectAdapter: ProductionEffectAdapter!
    effectAdapter = ProductionEffectAdapter(
      recognizerStore: PersonalRecognizerStore(),
      cameraAdapter: cameraAdapter,
      eventSink: { event in sendEvent(event) },
      menuSink: { menuPresentations.append($0) },
      workflowSink: { _ in }
    )
    sendEvent = { event in
      let effects = coordinator.handle(event)
      observedEffects.append(contentsOf: effects)
      for effect in effects {
        effectAdapter.execute(effect)
      }
    }

    sendEvent(.personalRecognizerChecked(.available))
    sendEvent(.pauseMonitoringRequested)
    sendEvent(.resumeMonitoringRequested)

    XCTAssertEqual(
      cameraAdapter.executedEffects,
      [
        .requestAuthorization,
        .startBuiltInCamera(
          targetFrameRate: .fps15,
          lifecycleID: RecognitionLifecycleID(rawValue: 1)
        ),
        .stopAndReleaseCamera,
        .requestAuthorization,
        .startBuiltInCamera(
          targetFrameRate: .fps15,
          lifecycleID: RecognitionLifecycleID(rawValue: 2)
        ),
      ]
    )
    XCTAssertEqual(
      menuPresentations,
      [
        .awaitingCameraAuthorization,
        .activeMonitoring,
        .pausedMonitoring,
        .awaitingCameraAuthorization,
        .activeMonitoring,
      ]
    )
    XCTAssertFalse(
      observedEffects.contains { effect in
        switch effect {
        case .loadWorkflowConfiguration,
          .resolveGhostty,
          .launchGhostty,
          .ensureDefaultHerdrSession,
          .queryHerdrAgents,
          .startPiAgent,
          .primaryWorkflowPiAgentPreserved,
          .primaryWorkflowPiAgentStarted,
          .primaryWorkflowFailed:
          true
        default:
          false
        }
      }
    )
  }

  func testPausedDiagnosticsUsesAndReleasesTheExistingCameraPipeline() throws {
    let cameraAdapter = FakeCameraAdapter()
    let cameraImage = try makeImage(width: 64, height: 48)
    let normalizedCrop = try makeImage(width: 224, height: 224)
    let recognitionAdapter = FakeRecognitionAdapter(
      diagnostic: DiagnosticGestureResult(
        handDetection: .detected,
        recognizedJointCount: 21,
        extendedFingerCount: 2,
        isOpenPalm: false
      ),
      classifications: [
        PersonalRecognizerClassification(
          label: "domain_expansion",
          confidence: 0.9
        )
      ],
      cameraImage: cameraImage,
      normalizedCrop: normalizedCrop
    )
    let coordinator = LaunchCoordinator()
    for event in [
      AppEvent.appLaunched,
      .menuBarApplicationConfigurationCompleted(.succeeded),
    ] {
      _ = coordinator.handle(event)
    }

    var menuPresentations: [MenuPresentation] = []
    var snapshots: [RecognitionDiagnosticsSnapshot] = []
    var openedSessionCount = 0
    var closedSessionCount = 0
    var workflowPresentations: [PrimaryWorkflowPresentation?] = []
    var sendEvent: ((AppEvent) -> Void)!
    var effectAdapter: ProductionEffectAdapter!
    effectAdapter = ProductionEffectAdapter(
      recognizerStore: PersonalRecognizerStore(),
      cameraAdapter: cameraAdapter,
      recognitionAdapter: recognitionAdapter,
      eventSink: { event in sendEvent(event) },
      menuSink: { menuPresentations.append($0) },
      workflowSink: { workflowPresentations.append($0) },
      recognitionDiagnosticsSink: { update in
        switch update {
        case .opened:
          openedSessionCount += 1
        case .snapshot(let snapshot):
          snapshots.append(snapshot)
        case .closed:
          closedSessionCount += 1
        }
      }
    )
    sendEvent = { event in
      for effect in coordinator.handle(event) {
        effectAdapter.execute(effect)
      }
    }

    sendEvent(.personalRecognizerChecked(.available))
    sendEvent(.pauseMonitoringRequested)
    sendEvent(.recognitionDiagnosticsRequested)
    let frame = try makeCapturedFrame(sequenceNumber: 1, lifecycleID: 2)
    cameraAdapter.emit(frame)
    sendEvent(.recognitionDiagnosticsClosed)

    XCTAssertEqual(
      cameraAdapter.executedEffects,
      [
        .requestAuthorization,
        .startBuiltInCamera(
          targetFrameRate: .fps15,
          lifecycleID: RecognitionLifecycleID(rawValue: 1)
        ),
        .stopAndReleaseCamera,
        .requestAuthorization,
        .startBuiltInCamera(
          targetFrameRate: .fps15,
          lifecycleID: RecognitionLifecycleID(rawValue: 2)
        ),
        .stopAndReleaseCamera,
      ]
    )
    XCTAssertEqual(
      recognitionAdapter.executedEffects,
      [.analyzeFrame(frame.reference)]
    )
    XCTAssertEqual(
      menuPresentations,
      [
        .awaitingCameraAuthorization,
        .activeMonitoring,
        .pausedMonitoring,
        .pausedMonitoring,
      ]
    )
    XCTAssertEqual(openedSessionCount, 1)
    XCTAssertEqual(closedSessionCount, 1)
    XCTAssertEqual(snapshots.count, 1)
    XCTAssertTrue(snapshots.first?.cameraImage === cameraImage)
    XCTAssertTrue(snapshots.first?.normalizedCrop === normalizedCrop)
    XCTAssertTrue(workflowPresentations.isEmpty)
  }

  func testCameraFramesPublishOnlyAcceptedSameFrameDiagnostics() throws {
    let cameraAdapter = FakeCameraAdapter()
    let diagnostic = DiagnosticGestureResult(
      handDetection: .detected,
      recognizedJointCount: 21,
      extendedFingerCount: 2,
      isOpenPalm: false
    )
    let cameraImage = try makeImage(width: 64, height: 48)
    let normalizedCrop = try makeImage(width: 224, height: 224)
    let top = PersonalRecognizerClassification(
      label: "domain_expansion",
      confidence: 0.9
    )
    let recognitionAdapter = FakeRecognitionAdapter(
      diagnostic: diagnostic,
      classifications: [top],
      cameraImage: cameraImage,
      normalizedCrop: normalizedCrop
    )
    let coordinator = LaunchCoordinator()
    for event in [
      AppEvent.appLaunched,
      .menuBarApplicationConfigurationCompleted(.succeeded),
    ] {
      _ = coordinator.handle(event)
    }

    var observedEffects: [AppEffect] = []
    var adapterEvents: [AppEvent] = []
    var sessions: [RecognitionDiagnosticsSession?] = []
    var snapshots: [RecognitionDiagnosticsSnapshot] = []
    var menuPresentationCount = 0
    var workflowPresentations: [PrimaryWorkflowPresentation?] = []
    var sendEvent: ((AppEvent) -> Void)!
    var effectAdapter: ProductionEffectAdapter!
    effectAdapter = ProductionEffectAdapter(
      recognizerStore: PersonalRecognizerStore(),
      cameraAdapter: cameraAdapter,
      recognitionAdapter: recognitionAdapter,
      recognitionClock: FixedRecognitionClock(value: 123.5),
      eventSink: { event in
        adapterEvents.append(event)
        sendEvent(event)
      },
      menuSink: { _ in menuPresentationCount += 1 },
      workflowSink: { workflowPresentations.append($0) },
      recognitionDiagnosticsSink: { update in
        switch update {
        case .opened(let session):
          sessions.append(session)
        case .snapshot(let snapshot):
          snapshots.append(snapshot)
        case .closed:
          sessions.append(nil)
        }
      }
    )
    sendEvent = { event in
      let effects = coordinator.handle(event)
      observedEffects.append(contentsOf: effects)
      for effect in effects {
        effectAdapter.execute(effect)
      }
    }

    sendEvent(.personalRecognizerChecked(.available))
    sendEvent(.recognitionDiagnosticsRequested)
    menuPresentationCount = 0
    let frame = try makeCapturedFrame(sequenceNumber: 1)
    cameraAdapter.emit(frame)

    XCTAssertEqual(recognitionAdapter.receivedFrames.map(\.reference), [frame.reference])
    XCTAssertEqual(
      recognitionAdapter.executedEffects,
      [.analyzeFrame(frame.reference)]
    )
    XCTAssertEqual(sessions.compactMap { $0 }.count, 1)
    XCTAssertEqual(snapshots.count, 1)
    XCTAssertEqual(snapshots.first?.diagnostics.frame, frame.reference)
    XCTAssertEqual(snapshots.first?.diagnostics.topClassification, top)
    XCTAssertTrue(snapshots.first?.cameraImage === cameraImage)
    XCTAssertTrue(snapshots.first?.normalizedCrop === normalizedCrop)

    for sequenceNumber in 2...25 {
      cameraAdapter.emit(
        try makeCapturedFrame(sequenceNumber: UInt64(sequenceNumber))
      )
    }
    XCTAssertEqual(snapshots.count, 25)
    XCTAssertEqual(
      snapshots.last?.diagnostics.frame.sequenceNumber,
      25
    )
    XCTAssertEqual(menuPresentationCount, 0)
    let clockEventIndex = adapterEvents.firstIndex(of: .recognitionClockRead(123.5))
    let completionEventIndex = adapterEvents.firstIndex {
      guard case .recognitionFrameCompleted = $0 else { return false }
      return true
    }
    XCTAssertNotNil(clockEventIndex)
    XCTAssertNotNil(completionEventIndex)
    if let clockEventIndex, let completionEventIndex {
      XCTAssertLessThan(clockEventIndex, completionEventIndex)
    }
    XCTAssertTrue(
      observedEffects.contains(.recognition(.analyzeFrame(frame.reference)))
    )
    XCTAssertTrue(workflowPresentations.isEmpty)
  }

  func testRejectedCompletionCannotPublishOrRetainAnAnalysisPayload() {
    let diagnostic = DiagnosticGestureResult(
      handDetection: .detected,
      recognizedJointCount: 21,
      extendedFingerCount: 2,
      isOpenPalm: false
    )
    let recognitionAdapter = FakeRecognitionAdapter(
      diagnostic: diagnostic,
      classifications: [
        PersonalRecognizerClassification(
          label: "domain_expansion",
          confidence: 0.9
        )
      ]
    )
    let coordinator = makeWorkflowReadyCoordinator()
    var snapshots: [RecognitionDiagnosticsSnapshot] = []
    var effectAdapter: ProductionEffectAdapter!
    effectAdapter = ProductionEffectAdapter(
      recognizerStore: PersonalRecognizerStore(),
      recognitionAdapter: recognitionAdapter,
      eventSink: { event in
        for effect in coordinator.handle(event) {
          effectAdapter.execute(effect)
        }
      },
      menuSink: { _ in },
      workflowSink: { _ in },
      recognitionDiagnosticsSink: { update in
        guard case .snapshot(let snapshot) = update else { return }
        snapshots.append(snapshot)
      }
    )
    let rejectedFrame = RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: 1),
      sequenceNumber: 99
    )

    effectAdapter.execute(.recognition(.analyzeFrame(rejectedFrame)))
    effectAdapter.execute(
      .presentRecognitionDiagnosticsFrame(
        RecognitionDiagnosticsFrame(
          frame: rejectedFrame,
          policy: .standard,
          topClassification: PersonalRecognizerClassification(
            label: "domain_expansion",
            confidence: 0.9
          ),
          isPoseMatch: true,
          poseMatchCount: 1,
          targetFrameRate: .fps15,
          captureFramesPerSecond: nil,
          completedRecognitionFramesPerSecond: 0
        )
      )
    )

    XCTAssertTrue(snapshots.isEmpty)
  }

  func testPoseTriggerRunsPrimaryWorkflowOnceThroughProductionAdapters() throws {
    let cameraAdapter = FakeCameraAdapter()
    let diagnostic = DiagnosticGestureResult(
      handDetection: .detected,
      recognizedJointCount: 21,
      extendedFingerCount: 5,
      isOpenPalm: true
    )
    let recognitionAdapter = FakeRecognitionAdapter(
      diagnostic: diagnostic,
      classifications: [
        PersonalRecognizerClassification(
          label: "domain_expansion",
          confidence: 0.9
        ),
        PersonalRecognizerClassification(label: "other", confidence: 0.1),
      ]
    )
    let configuration = WorkflowConfiguration(
      workspacePath: "/Users/developer/work/siglaunch",
      piCommand: ["pi"]
    )
    let configurationLoader = FakeWorkflowConfigurationLoader(
      result: .loaded(configuration)
    )
    let ghosttyAdapter = FakeGhosttyPlatformAdapter(
      resolution: .found(
        GhosttyApplication(
          path: "/Applications/Ghostty.app",
          version: "1.3.0",
          isRunning: true
        )
      ),
      launchResult: .succeeded,
      sessionResult: .ready(.reused)
    )
    let herdrAdapter = FakeHerdrAgentAdapter(
      queryResult: .agents([]),
      startResult: .succeeded
    )
    let hudPresenter = FakeDomainExpansionHUDPresenter()
    let coordinator = LaunchCoordinator()
    for event in [
      AppEvent.appLaunched,
      .menuBarApplicationConfigurationCompleted(.succeeded),
    ] {
      _ = coordinator.handle(event)
    }

    var observedEffects: [AppEffect] = []
    var progressValues: [DomainExpansionCandidateProgress?] = []
    var workflowPresentations: [PrimaryWorkflowPresentation?] = []
    var sendEvent: ((AppEvent) -> Void)!
    var effectAdapter: ProductionEffectAdapter!
    effectAdapter = ProductionEffectAdapter(
      recognizerStore: PersonalRecognizerStore(),
      cameraAdapter: cameraAdapter,
      recognitionAdapter: recognitionAdapter,
      workflowConfigurationStore: configurationLoader,
      ghosttyPlatformAdapter: ghosttyAdapter,
      herdrAgentAdapter: herdrAdapter,
      domainExpansionHUDPresenter: hudPresenter,
      eventSink: { event in sendEvent(event) },
      menuSink: { _ in },
      workflowSink: { workflowPresentations.append($0) },
      domainExpansionCandidateProgressSink: { progressValues.append($0) }
    )
    sendEvent = { event in
      let effects = coordinator.handle(event)
      observedEffects.append(contentsOf: effects)
      for effect in effects {
        effectAdapter.execute(effect)
      }
    }

    sendEvent(.personalRecognizerChecked(.available))
    for sequenceNumber in 1...4 {
      cameraAdapter.emit(
        try makeCapturedFrame(sequenceNumber: UInt64(sequenceNumber))
      )
    }

    XCTAssertEqual(
      progressValues,
      [
        DomainExpansionCandidateProgress(poseMatchCount: 1),
        DomainExpansionCandidateProgress(poseMatchCount: 2),
        nil,
      ]
    )
    XCTAssertEqual(hudPresenter.executedEffects, [.showDomainExpansion])
    hudPresenter.send(.animationCompleted)
    XCTAssertEqual(
      hudPresenter.executedEffects,
      [.showDomainExpansion, .fade]
    )
    XCTAssertEqual(
      observedEffects.filter { $0 == .loadWorkflowConfiguration }.count,
      1
    )
    XCTAssertEqual(configurationLoader.loadCount, 1)
    XCTAssertEqual(
      herdrAdapter.startedConfigurations,
      [configuration]
    )
    XCTAssertEqual(
      workflowPresentations,
      [.none, .piAgentStarted]
    )
  }

  func testHUDPresentationEventsReturnThroughCoordinatorSeam() {
    let hudPresenter = FakeDomainExpansionHUDPresenter()
    var events: [AppEvent] = []
    let effectAdapter = ProductionEffectAdapter(
      recognizerStore: PersonalRecognizerStore(),
      domainExpansionHUDPresenter: hudPresenter,
      eventSink: { events.append($0) },
      menuSink: { _ in },
      workflowSink: { _ in }
    )

    effectAdapter.execute(
      .presentDomainExpansionHUD(.showDomainExpansion)
    )
    XCTAssertEqual(hudPresenter.executedEffects, [.showDomainExpansion])

    hudPresenter.send(.animationCompleted)
    XCTAssertEqual(events, [.domainExpansionHUD(.animationCompleted)])
  }

  func testFakePoseDatasetAdaptersDriveImportThroughCoordinatorLoop() async {
    let rootPath = "/Users/developer/Pose Dataset"
    let progress = PoseDatasetPreparationProgress(
      label: .other,
      processedImageCount: 20,
      totalImageCount: 20
    )
    let summary = PoseDatasetSummary(
      domainExpansion: PoseDatasetLabelSummary(
        validImageCount: 10,
        handlessImageCount: 1,
        unreadableImageCount: 0
      ),
      other: PoseDatasetLabelSummary(
        validImageCount: 10,
        handlessImageCount: 0,
        unreadableImageCount: 2
      )
    )
    let samples = PoseDatasetLabel.allCases.flatMap { label in
      (0..<summary.summary(for: label).validImageCount).map { index in
        PoseDatasetSample(
          label: label,
          imagePath: "/prepared/\(label.rawValue)/\(index).png"
        )
      }
    }
    let input = PoseDatasetTrainingInput(
      directoryPath: "/prepared",
      samples: samples,
      summary: summary
    )!
    let folderSelector = FakePoseDatasetFolderSelector(
      result: .selected(path: rootPath)
    )
    let preparer = FakePoseDatasetPreparer(
      progress: [progress],
      result: .succeeded(input)
    )
    let coordinator = makeSetupRequiredCoordinator()
    let ready = expectation(description: "Pose Dataset ready")

    var observedEffects: [AppEffect] = []
    var presentations: [PoseDatasetImportPresentation?] = []
    var sendEvent: ((AppEvent) -> Void)!
    var effectAdapter: ProductionEffectAdapter!
    effectAdapter = ProductionEffectAdapter(
      recognizerStore: PersonalRecognizerStore(),
      poseDatasetFolderSelector: folderSelector,
      poseDatasetPreparer: preparer,
      eventSink: { event in sendEvent(event) },
      menuSink: { _ in },
      workflowSink: { _ in },
      poseDatasetSink: { presentation in
        presentations.append(presentation)
        if presentation == .ready(input) {
          ready.fulfill()
        }
      }
    )
    sendEvent = { event in
      let effects = coordinator.handle(event)
      observedEffects.append(contentsOf: effects)
      for effect in effects {
        effectAdapter.execute(effect)
      }
    }

    sendEvent(.poseDatasetImportRequested)
    await fulfillment(of: [ready], timeout: 1)

    XCTAssertEqual(
      observedEffects,
      [
        .presentPoseDatasetImport(.choosingFolder),
        .selectPoseDatasetFolder,
        .presentPoseDatasetImport(.validating(nil)),
        .preparePoseDataset(at: rootPath),
        .presentPoseDatasetImport(.validating(progress)),
        .presentPoseDatasetImport(.ready(input)),
      ]
    )
    XCTAssertEqual(
      presentations,
      [
        .choosingFolder,
        .validating(nil),
        .validating(progress),
        .ready(input),
      ]
    )
    XCTAssertEqual(folderSelector.selectionCount, 1)
    let requestedPaths = await preparer.requestedPaths
    XCTAssertEqual(requestedPaths, [rootPath])
  }

  func testFakeRecognizerAdaptersDriveTrainingThroughCoordinatorLoop() async {
    let input = makeTrainingInput()
    let artifact = RecognizerTrainingArtifact(path: "/tmp/trained.mlmodel")
    let candidate = PersonalRecognizerCandidate(identifier: "candidate")
    let progress = RecognizerTrainingProgress(
      completedUnitCount: 6,
      totalUnitCount: 10
    )
    let trainer = FakeRecognizerTrainingAdapter(
      progress: [progress],
      result: .succeeded(artifact)
    )
    let recognizerStore = FakePersonalRecognizerStore(
      saveResult: .succeeded(candidate),
      replacementResult: .succeeded
    )
    let cameraAdapter = FakeCameraAdapter()
    let coordinator = makeSetupRequiredCoordinator()
    _ = coordinator.handle(.poseDatasetImportRequested)
    _ = coordinator.handle(
      .poseDatasetFolderSelectionCompleted(.selected(path: "/Pose Dataset"))
    )
    _ = coordinator.handle(.poseDatasetPreparationCompleted(.succeeded(input)))
    let active = expectation(description: "first recognizer activates monitoring")

    var observedEffects: [AppEffect] = []
    var trainingPresentations: [RecognizerTrainingPresentation?] = []
    var sendEvent: ((AppEvent) -> Void)!
    var effectAdapter: ProductionEffectAdapter!
    effectAdapter = ProductionEffectAdapter(
      recognizerStore: recognizerStore,
      cameraAdapter: cameraAdapter,
      recognizerTrainer: trainer,
      eventSink: { event in sendEvent(event) },
      menuSink: { presentation in
        if presentation == .activeMonitoring {
          active.fulfill()
        }
      },
      workflowSink: { _ in },
      recognizerTrainingSink: { trainingPresentations.append($0) }
    )
    sendEvent = { event in
      let effects = coordinator.handle(event)
      observedEffects.append(contentsOf: effects)
      for effect in effects {
        effectAdapter.execute(effect)
      }
    }

    sendEvent(.recognizerTrainingRequested)
    await fulfillment(of: [active], timeout: 1)

    XCTAssertEqual(
      observedEffects,
      [
        .presentRecognizerTraining(.training(nil)),
        .startRecognizerTraining(input),
        .presentRecognizerTraining(.training(progress)),
        .presentRecognizerTraining(.saving),
        .savePersonalRecognizerCandidate(artifact),
        .presentRecognizerTraining(.replacing),
        .replacePersonalRecognizer(candidate),
        .clearRecognitionEvidence,
        .presentRecognizerTraining(.succeeded),
        .presentMenu(.awaitingCameraAuthorization),
        .camera(.requestAuthorization),
        .camera(
          .startBuiltInCamera(
            targetFrameRate: .fps15,
            lifecycleID: RecognitionLifecycleID(rawValue: 1)
          )
        ),
        .presentMenu(.activeMonitoring),
      ]
    )
    XCTAssertEqual(trainer.inputs, [input])
    XCTAssertEqual(recognizerStore.savedArtifacts, [artifact])
    XCTAssertEqual(recognizerStore.replacedCandidates, [candidate])
    XCTAssertEqual(
      trainingPresentations,
      [.training(nil), .training(progress), .saving, .replacing, .succeeded]
    )
  }

  func testTrainingCancellationReturnsAnEventThroughCoordinatorLoop() {
    let input = makeTrainingInput()
    let trainer = FakeRecognizerTrainingAdapter(progress: [], result: nil)
    let recognizerStore = FakePersonalRecognizerStore(
      saveResult: .failed(.artifactUnavailable),
      replacementResult: .failed(.candidateUnavailable)
    )
    let coordinator = makeSetupRequiredCoordinator()
    _ = coordinator.handle(.poseDatasetImportRequested)
    _ = coordinator.handle(
      .poseDatasetFolderSelectionCompleted(.selected(path: "/Pose Dataset"))
    )
    _ = coordinator.handle(.poseDatasetPreparationCompleted(.succeeded(input)))

    var observedEffects: [AppEffect] = []
    var presentations: [RecognizerTrainingPresentation?] = []
    var sendEvent: ((AppEvent) -> Void)!
    var effectAdapter: ProductionEffectAdapter!
    effectAdapter = ProductionEffectAdapter(
      recognizerStore: recognizerStore,
      recognizerTrainer: trainer,
      eventSink: { event in sendEvent(event) },
      menuSink: { _ in },
      workflowSink: { _ in },
      recognizerTrainingSink: { presentations.append($0) }
    )
    sendEvent = { event in
      let effects = coordinator.handle(event)
      observedEffects.append(contentsOf: effects)
      for effect in effects {
        effectAdapter.execute(effect)
      }
    }

    sendEvent(.recognizerTrainingRequested)
    sendEvent(.recognizerTrainingCancellationRequested)

    XCTAssertEqual(
      observedEffects,
      [
        .presentRecognizerTraining(.training(nil)),
        .startRecognizerTraining(input),
        .presentRecognizerTraining(.cancelling),
        .cancelRecognizerTraining,
        .presentRecognizerTraining(.cancelled),
      ]
    )
    XCTAssertEqual(presentations, [.training(nil), .cancelling, .cancelled])
    XCTAssertEqual(trainer.cancellationCount, 1)
    XCTAssertTrue(recognizerStore.savedArtifacts.isEmpty)
    XCTAssertTrue(recognizerStore.replacedCandidates.isEmpty)
  }

  private func makeImage(width: Int, height: Int) throws -> CGImage {
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      let image = context.makeImage()
    else {
      throw ProductionEffectAdapterTestError.imageCreationFailed
    }
    return image
  }

  private func makeCapturedFrame(
    sequenceNumber: UInt64,
    lifecycleID: UInt64 = 1
  ) throws -> CapturedRecognitionFrame {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      16,
      16,
      kCVPixelFormatType_32BGRA,
      nil,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else {
      throw ProductionEffectAdapterTestError.pixelBufferCreationFailed(status)
    }
    return CapturedRecognitionFrame(
      reference: RecognitionFrameReference(
        lifecycleID: RecognitionLifecycleID(rawValue: lifecycleID),
        sequenceNumber: sequenceNumber
      ),
      pixelBuffer: pixelBuffer
    )
  }

  private func makeTrainingInput() -> PoseDatasetTrainingInput {
    let summary = PoseDatasetLabelSummary(
      validImageCount: 10,
      handlessImageCount: 0,
      unreadableImageCount: 0
    )
    let samples = PoseDatasetLabel.allCases.flatMap { label in
      (0..<10).map { index in
        PoseDatasetSample(
          label: label,
          imagePath: "/prepared/\(label.rawValue)/\(index).png"
        )
      }
    }
    return PoseDatasetTrainingInput(
      directoryPath: "/prepared",
      samples: samples,
      summary: PoseDatasetSummary(
        domainExpansion: summary,
        other: summary
      )
    )!
  }

  private func makeWorkflowReadyCoordinator() -> LaunchCoordinator {
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
      .menuPresented(.activeMonitoring),
    ] {
      _ = coordinator.handle(event)
    }
    return coordinator
  }

  private func makeSetupRequiredCoordinator() -> LaunchCoordinator {
    let coordinator = LaunchCoordinator()
    for event in [
      AppEvent.appLaunched,
      .menuBarApplicationConfigurationCompleted(.succeeded),
      .personalRecognizerChecked(.missing),
      .menuPresented(.setupRequired),
    ] {
      _ = coordinator.handle(event)
    }
    return coordinator
  }
}

@MainActor
private final class FakeDomainExpansionHUDPresenter: DomainExpansionHUDPresenting {
  private(set) var executedEffects: [DomainExpansionHUDPresentationEffect] = []
  private var eventSink: (@MainActor @Sendable (DomainExpansionHUDPresentationEvent) -> Void)?

  func execute(
    _ effect: DomainExpansionHUDPresentationEffect,
    eventSink: @escaping @MainActor @Sendable (DomainExpansionHUDPresentationEvent) -> Void
  ) {
    executedEffects.append(effect)
    self.eventSink = eventSink
  }

  func send(_ event: DomainExpansionHUDPresentationEvent) {
    eventSink?(event)
  }
}

private struct FixedRecognitionClock: RecognitionClockReading {
  let value: TimeInterval

  func now() -> TimeInterval {
    value
  }
}

@MainActor
private enum ProductionEffectAdapterTestError: Error {
  case imageCreationFailed
  case pixelBufferCreationFailed(CVReturn)
}

@MainActor
private final class FakeRecognitionAdapter: RecognitionAdapting {
  let diagnostic: DiagnosticGestureResult
  let classifications: [PersonalRecognizerClassification]?
  let cameraImage: CGImage?
  let normalizedCrop: CGImage?
  private(set) var receivedFrames: [CapturedRecognitionFrame] = []
  private(set) var executedEffects: [RecognitionEffect] = []

  init(
    diagnostic: DiagnosticGestureResult,
    classifications: [PersonalRecognizerClassification]? = nil,
    cameraImage: CGImage? = nil,
    normalizedCrop: CGImage? = nil
  ) {
    self.diagnostic = diagnostic
    self.classifications = classifications
    self.cameraImage = cameraImage
    self.normalizedCrop = normalizedCrop
  }

  func receive(_ frame: CapturedRecognitionFrame) {
    receivedFrames.append(frame)
  }

  func execute(
    _ effect: RecognitionEffect,
    analysisSink: @escaping @MainActor @Sendable (RecognitionAnalysis) -> Void
  ) {
    executedEffects.append(effect)
    guard case .analyzeFrame(let reference) = effect else { return }
    analysisSink(
      RecognitionAnalysis(
        frame: reference,
        cameraImage: cameraImage,
        normalizedCrop: normalizedCrop,
        diagnosticGesture: diagnostic,
        personalRecognizerResult: classifications.map {
          .classified($0)
        } ?? .failed
      )
    )
  }

  func reset() {
    receivedFrames.removeAll()
  }
}

@MainActor
private final class FakeRecognizerTrainingAdapter: RecognizerTrainingAdapting {
  let progressValues: [RecognizerTrainingProgress]
  let result: RecognizerTrainingResult?
  private(set) var inputs: [PoseDatasetTrainingInput] = []
  private(set) var cancellationCount = 0
  private var completionSink:
    (
      @MainActor @Sendable (RecognizerTrainingResult) -> Void
    )?

  init(
    progress: [RecognizerTrainingProgress],
    result: RecognizerTrainingResult?
  ) {
    progressValues = progress
    self.result = result
  }

  func start(
    with input: PoseDatasetTrainingInput,
    progress: @escaping @MainActor @Sendable (RecognizerTrainingProgress) -> Void,
    completion: @escaping @MainActor @Sendable (RecognizerTrainingResult) -> Void
  ) {
    inputs.append(input)
    for value in progressValues {
      progress(value)
    }
    if let result {
      completion(result)
    } else {
      completionSink = completion
    }
  }

  func cancel() {
    cancellationCount += 1
    let completion = completionSink
    completionSink = nil
    completion?(.cancelled)
  }
}

@MainActor
private final class FakePersonalRecognizerStore: PersonalRecognizerStoring {
  let availability: PersonalRecognizerAvailability = .available
  let saveResult: PersonalRecognizerCandidateSaveResult
  let replacementResult: PersonalRecognizerReplacementResult
  private(set) var savedArtifacts: [RecognizerTrainingArtifact] = []
  private(set) var replacedCandidates: [PersonalRecognizerCandidate] = []

  init(
    saveResult: PersonalRecognizerCandidateSaveResult,
    replacementResult: PersonalRecognizerReplacementResult
  ) {
    self.saveResult = saveResult
    self.replacementResult = replacementResult
  }

  func saveCandidate(
    from artifact: RecognizerTrainingArtifact
  ) async -> PersonalRecognizerCandidateSaveResult {
    savedArtifacts.append(artifact)
    return saveResult
  }

  func replaceActiveModel(
    with candidate: PersonalRecognizerCandidate
  ) async -> PersonalRecognizerReplacementResult {
    replacedCandidates.append(candidate)
    return replacementResult
  }
}

@MainActor
private final class FakeCameraAdapter: CameraAdapting {
  private(set) var executedEffects: [CameraEffect] = []
  private var frameSink: (@MainActor @Sendable (CapturedRecognitionFrame) -> Void)?

  func execute(
    _ effect: CameraEffect,
    eventSink: @escaping @MainActor @Sendable (CameraEvent) -> Void,
    frameSink: @escaping @MainActor @Sendable (CapturedRecognitionFrame) -> Void
  ) {
    executedEffects.append(effect)
    self.frameSink = frameSink
    switch effect {
    case .requestAuthorization:
      eventSink(.authorizationChanged(.authorized))
    case .startBuiltInCamera(_, let lifecycleID),
      .rebuildBuiltInCamera(_, let lifecycleID):
      eventSink(
        .captureStartCompleted(
          lifecycleID: lifecycleID,
          result: .succeeded
        )
      )
    case .updateRecognitionFrameRate:
      break
    case .stopCapture:
      break
    case .stopAndReleaseCamera:
      eventSink(.released)
    }
  }

  func emit(_ frame: CapturedRecognitionFrame) {
    frameSink?(frame)
  }
}

@MainActor
private final class FakePoseDatasetFolderSelector: PoseDatasetFolderSelecting {
  let result: PoseDatasetFolderSelectionResult
  private(set) var selectionCount = 0

  init(result: PoseDatasetFolderSelectionResult) {
    self.result = result
  }

  func selectFolder() -> PoseDatasetFolderSelectionResult {
    selectionCount += 1
    return result
  }
}

private actor FakePoseDatasetPreparer: PoseDatasetPreparing {
  let progressValues: [PoseDatasetPreparationProgress]
  let result: PoseDatasetPreparationResult
  private(set) var requestedPaths: [String] = []

  init(
    progress: [PoseDatasetPreparationProgress],
    result: PoseDatasetPreparationResult
  ) {
    self.progressValues = progress
    self.result = result
  }

  func prepare(
    at rootPath: String,
    progress: @escaping @Sendable (PoseDatasetPreparationProgress) async -> Void
  ) async -> PoseDatasetPreparationResult {
    requestedPaths.append(rootPath)
    for value in progressValues {
      await progress(value)
    }
    return result
  }
}

private final class FakeWorkflowConfigurationLoader: WorkflowConfigurationLoading {
  let result: WorkflowConfigurationLoadResult
  private(set) var loadCount = 0

  init(result: WorkflowConfigurationLoadResult) {
    self.result = result
  }

  func load() -> WorkflowConfigurationLoadResult {
    loadCount += 1
    return result
  }
}

@MainActor
private final class FakeGhosttyPlatformAdapter: GhosttyPlatformAdapting {
  let resolution: GhosttyResolutionResult
  let launchResult: GhosttyLaunchResult
  let sessionResult: DefaultHerdrSessionEnsureResult
  private(set) var resolutionCount = 0
  private(set) var launchedPaths: [String] = []
  private(set) var sessionEnsureCount = 0

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
    resolutionCount += 1
    return resolution
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
    sessionEnsureCount += 1
    completion(sessionResult)
  }
}

@MainActor
private final class FakeHerdrAgentAdapter: HerdrAgentAdapting {
  let queryResult: HerdrAgentQueryResult
  let startResult: HerdrAgentStartResult
  private(set) var queryCount = 0
  private(set) var startedConfigurations: [WorkflowConfiguration] = []

  init(
    queryResult: HerdrAgentQueryResult,
    startResult: HerdrAgentStartResult = .succeeded
  ) {
    self.queryResult = queryResult
    self.startResult = startResult
  }

  func queryAgents(
    completion: @escaping @MainActor @Sendable (HerdrAgentQueryResult) -> Void
  ) {
    queryCount += 1
    completion(queryResult)
  }

  func startPiAgent(
    workspacePath: String,
    command: [String],
    completion: @escaping @MainActor @Sendable (HerdrAgentStartResult) -> Void
  ) {
    startedConfigurations.append(
      WorkflowConfiguration(workspacePath: workspacePath, piCommand: command)
    )
    completion(startResult)
  }
}
