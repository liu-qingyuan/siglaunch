import AppKit
import SiglaunchCore

enum PrimaryWorkflowPresentation: Equatable {
  case leadingPiAgentFocused
  case noMatchingPiAgent
  case failed(PrimaryWorkflowFailure)
}

@MainActor
final class ProductionEffectAdapter {
  private let recognizerStore: PersonalRecognizerStore
  private let cameraAdapter: any CameraAdapting
  private let workflowConfigurationStore: any WorkflowConfigurationLoading
  private let ghosttyPlatformAdapter: any GhosttyPlatformAdapting
  private let herdrAgentAdapter: any HerdrAgentAdapting
  private let poseDatasetFolderSelector: any PoseDatasetFolderSelecting
  private let poseDatasetPreparer: any PoseDatasetPreparing
  private let eventSink: (AppEvent) -> Void
  private let menuSink: (MenuPresentation) -> Void
  private let workflowSink: (PrimaryWorkflowPresentation?) -> Void
  private let poseDatasetSink: (PoseDatasetImportPresentation?) -> Void

  init(
    recognizerStore: PersonalRecognizerStore,
    cameraAdapter: any CameraAdapting = ProductionCameraAdapter(),
    workflowConfigurationStore: any WorkflowConfigurationLoading = WorkflowConfigurationStore(),
    ghosttyPlatformAdapter: any GhosttyPlatformAdapting = GhosttyPlatformAdapter(),
    herdrAgentAdapter: any HerdrAgentAdapting = HerdrAgentAdapter(),
    poseDatasetFolderSelector: any PoseDatasetFolderSelecting = SystemPoseDatasetFolderPicker(),
    poseDatasetPreparer: any PoseDatasetPreparing = PoseDatasetAdapter(),
    eventSink: @escaping (AppEvent) -> Void,
    menuSink: @escaping (MenuPresentation) -> Void,
    workflowSink: @escaping (PrimaryWorkflowPresentation?) -> Void,
    poseDatasetSink: @escaping (PoseDatasetImportPresentation?) -> Void = { _ in }
  ) {
    self.recognizerStore = recognizerStore
    self.cameraAdapter = cameraAdapter
    self.workflowConfigurationStore = workflowConfigurationStore
    self.ghosttyPlatformAdapter = ghosttyPlatformAdapter
    self.herdrAgentAdapter = herdrAgentAdapter
    self.poseDatasetFolderSelector = poseDatasetFolderSelector
    self.poseDatasetPreparer = poseDatasetPreparer
    self.eventSink = eventSink
    self.menuSink = menuSink
    self.workflowSink = workflowSink
    self.poseDatasetSink = poseDatasetSink
  }

  func execute(_ effect: AppEffect) {
    switch effect {
    case .configureMenuBarApplication:
      let result: MenuBarApplicationConfigurationResult =
        NSApplication.shared.setActivationPolicy(.accessory) ? .succeeded : .failed
      eventSink(.menuBarApplicationConfigurationCompleted(result))
    case .checkPersonalRecognizer:
      eventSink(.personalRecognizerChecked(recognizerStore.availability))
    case .camera(let cameraEffect):
      cameraAdapter.execute(cameraEffect) { [weak self] event in
        self?.eventSink(.camera(event))
      }
    case .presentMenu(let presentation):
      menuSink(presentation)
      eventSink(.menuPresented(presentation))
    case .clearRecognitionEvidence:
      break
    case .loadWorkflowConfiguration:
      workflowSink(nil)
      eventSink(
        .workflowConfigurationLoadCompleted(workflowConfigurationStore.load())
      )
    case .resolveGhostty:
      eventSink(.ghosttyResolutionCompleted(ghosttyPlatformAdapter.resolve()))
    case .launchGhostty(let path):
      ghosttyPlatformAdapter.launch(at: path) { [weak self] result in
        self?.eventSink(.ghosttyLaunchCompleted(result))
      }
    case .ensureDefaultHerdrSession:
      ghosttyPlatformAdapter.ensureDefaultHerdrSession { [weak self] result in
        self?.eventSink(.defaultHerdrSessionEnsureCompleted(result))
      }
    case .queryHerdrAgents:
      herdrAgentAdapter.queryAgents { [weak self] result in
        self?.eventSink(.herdrAgentQueryCompleted(result))
      }
    case .focusHerdrAgent(let paneID):
      herdrAgentAdapter.focusAgent(paneID: paneID) { [weak self] result in
        self?.eventSink(.herdrAgentFocusCompleted(result))
      }
    case .primaryWorkflowNoMatchingAgent:
      workflowSink(.noMatchingPiAgent)
    case .primaryWorkflowLeadingPiAgentFocused:
      workflowSink(.leadingPiAgentFocused)
    case .primaryWorkflowFailed(let failure):
      workflowSink(.failed(failure))
    case .presentPoseDatasetImport(let presentation):
      poseDatasetSink(presentation)
    case .selectPoseDatasetFolder:
      eventSink(
        .poseDatasetFolderSelectionCompleted(
          poseDatasetFolderSelector.selectFolder()
        )
      )
    case .preparePoseDataset(let path):
      let preparer = poseDatasetPreparer
      Task { [weak self] in
        let result = await preparer.prepare(at: path) { [weak self] progress in
          await self?.sendPoseDatasetProgress(progress)
        }
        self?.eventSink(.poseDatasetPreparationCompleted(result))
      }
    case .terminateApplication:
      NSApplication.shared.terminate(nil)
    }
  }

  private func sendPoseDatasetProgress(_ progress: PoseDatasetPreparationProgress) {
    eventSink(.poseDatasetPreparationProgressed(progress))
  }
}
