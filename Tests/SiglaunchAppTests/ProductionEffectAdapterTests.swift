import CoreVideo
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
    XCTAssertEqual(herdrAdapter.startedConfigurations, [])
    XCTAssertEqual(workflowPresentations, [nil, .leadingPiAgentFocused])
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
      focusResult: .succeeded,
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
        .loadWorkflowConfiguration,
        .resolveGhostty,
        .ensureDefaultHerdrSession,
        .queryHerdrAgents,
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
    XCTAssertEqual(ghosttyAdapter.launchedPaths, [])
    XCTAssertEqual(herdrAdapter.queryCount, 1)
    XCTAssertEqual(herdrAdapter.focusedPaneIDs, [])
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
          .focusHerdrAgent,
          .startPiAgent,
          .primaryWorkflowLeadingPiAgentFocused,
          .primaryWorkflowPiAgentStarted,
          .primaryWorkflowFailed:
          true
        default:
          false
        }
      }
    )
  }

  func testCameraFramesDriveRecognitionDiagnosticsThroughCoordinatorLoop() throws {
    let cameraAdapter = FakeCameraAdapter()
    let diagnostic = DiagnosticGestureResult(
      handDetection: .detected,
      recognizedJointCount: 21,
      extendedFingerCount: 5,
      isOpenPalm: true
    )
    let recognitionAdapter = FakeRecognitionAdapter(diagnostic: diagnostic)
    let coordinator = LaunchCoordinator()
    for event in [
      AppEvent.appLaunched,
      .menuBarApplicationConfigurationCompleted(.succeeded),
    ] {
      _ = coordinator.handle(event)
    }

    var observedEffects: [AppEffect] = []
    var adapterEvents: [AppEvent] = []
    var diagnostics: [RecognitionDiagnostics] = []
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
      menuSink: { _ in },
      workflowSink: { workflowPresentations.append($0) },
      recognitionDiagnosticsSink: { diagnostics.append($0) }
    )
    sendEvent = { event in
      let effects = coordinator.handle(event)
      observedEffects.append(contentsOf: effects)
      for effect in effects {
        effectAdapter.execute(effect)
      }
    }

    sendEvent(.personalRecognizerChecked(.available))
    let frame = try makeCapturedFrame(sequenceNumber: 1)
    cameraAdapter.emit(frame)

    XCTAssertEqual(recognitionAdapter.receivedFrames.map(\.reference), [frame.reference])
    XCTAssertEqual(
      recognitionAdapter.executedEffects,
      [.analyzeFrame(frame.reference)]
    )
    XCTAssertEqual(diagnostics.last?.diagnosticGesture, diagnostic)
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
      focusResult: .succeeded,
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
        .presentRecognitionDiagnostics(.initial(targetFrameRate: .fps15)),
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

  private func makeCapturedFrame(
    sequenceNumber: UInt64
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
        lifecycleID: RecognitionLifecycleID(rawValue: 1),
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
  case pixelBufferCreationFailed(CVReturn)
}

@MainActor
private final class FakeRecognitionAdapter: RecognitionAdapting {
  let diagnostic: DiagnosticGestureResult
  let classifications: [PersonalRecognizerClassification]?
  private(set) var receivedFrames: [CapturedRecognitionFrame] = []
  private(set) var executedEffects: [RecognitionEffect] = []

  init(
    diagnostic: DiagnosticGestureResult,
    classifications: [PersonalRecognizerClassification]? = nil
  ) {
    self.diagnostic = diagnostic
    self.classifications = classifications
  }

  func receive(_ frame: CapturedRecognitionFrame) {
    receivedFrames.append(frame)
  }

  func execute(
    _ effect: RecognitionEffect,
    eventSink: @escaping @MainActor @Sendable (RecognitionFrameCompletion) -> Void
  ) {
    executedEffects.append(effect)
    guard case .analyzeFrame(let reference) = effect else { return }
    eventSink(
      RecognitionFrameCompletion(
        frame: reference,
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
  let startResult: HerdrAgentStartResult
  private(set) var queryCount = 0
  private(set) var focusedPaneIDs: [String] = []
  private(set) var startedConfigurations: [WorkflowConfiguration] = []

  init(
    queryResult: HerdrAgentQueryResult,
    focusResult: HerdrAgentFocusResult,
    startResult: HerdrAgentStartResult = .succeeded
  ) {
    self.queryResult = queryResult
    self.focusResult = focusResult
    self.startResult = startResult
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
