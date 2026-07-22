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
        .startBuiltInCamera,
        .stopAndReleaseCamera,
        .requestAuthorization,
        .startBuiltInCamera,
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
          .primaryWorkflowNoMatchingAgent,
          .primaryWorkflowLeadingPiAgentFocused,
          .primaryWorkflowFailed:
          true
        default:
          false
        }
      }
    )
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

  private func makeWorkflowReadyCoordinator() -> LaunchCoordinator {
    let coordinator = LaunchCoordinator()
    for event in [
      AppEvent.appLaunched,
      .menuBarApplicationConfigurationCompleted(.succeeded),
      .personalRecognizerChecked(.available),
      .camera(.authorizationChanged(.authorized)),
      .camera(.captureStartCompleted(.succeeded)),
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
private final class FakeCameraAdapter: CameraAdapting {
  private(set) var executedEffects: [CameraEffect] = []

  func execute(
    _ effect: CameraEffect,
    eventSink: @escaping @MainActor @Sendable (CameraEvent) -> Void
  ) {
    executedEffects.append(effect)
    switch effect {
    case .requestAuthorization:
      eventSink(.authorizationChanged(.authorized))
    case .startBuiltInCamera, .rebuildBuiltInCamera:
      eventSink(.captureStartCompleted(.succeeded))
    case .stopCapture:
      break
    case .stopAndReleaseCamera:
      eventSink(.released)
    }
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
