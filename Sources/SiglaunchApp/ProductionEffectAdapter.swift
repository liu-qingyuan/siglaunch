import AppKit
import Foundation
import SiglaunchCore

protocol RecognitionClockReading: Sendable {
  func now() -> TimeInterval
}

struct SystemRecognitionClock: RecognitionClockReading {
  func now() -> TimeInterval {
    ProcessInfo.processInfo.systemUptime
  }
}

enum PrimaryWorkflowPresentation: Equatable {
  case leadingPiAgentFocused
  case piAgentStarted
  case failed(PrimaryWorkflowFailure)
}

@MainActor
final class ProductionEffectAdapter {
  private let recognizerStore: any PersonalRecognizerStoring
  private let cameraAdapter: any CameraAdapting
  private let recognitionAdapter: any RecognitionAdapting
  private let recognitionClock: any RecognitionClockReading
  private let recognizerTrainer: any RecognizerTrainingAdapting
  private let workflowConfigurationStore: any WorkflowConfigurationLoading
  private let ghosttyPlatformAdapter: any GhosttyPlatformAdapting
  private let herdrAgentAdapter: any HerdrAgentAdapting
  private let domainExpansionHUDPresenter: any DomainExpansionHUDPresenting
  private let poseDatasetFolderSelector: any PoseDatasetFolderSelecting
  private let poseDatasetPreparer: any PoseDatasetPreparing
  private let eventSink: (AppEvent) -> Void
  private let menuSink: (MenuPresentation) -> Void
  private let workflowSink: (PrimaryWorkflowPresentation?) -> Void
  private let recognitionDiagnosticsSink: (RecognitionDiagnosticsUpdate) -> Void
  private let domainExpansionCandidateProgressSink: (DomainExpansionCandidateProgress?) -> Void
  private let poseDatasetSink: (PoseDatasetImportPresentation?) -> Void
  private let recognizerTrainingSink: (RecognizerTrainingPresentation?) -> Void
  private var pendingRecognitionAnalyses: [RecognitionFrameReference: RecognitionAnalysis] = [:]

  init(
    recognizerStore: any PersonalRecognizerStoring,
    cameraAdapter: any CameraAdapting = ProductionCameraAdapter(),
    recognitionAdapter: any RecognitionAdapting = VisionDiagnosticAdapter(),
    recognitionClock: any RecognitionClockReading = SystemRecognitionClock(),
    recognizerTrainer: any RecognizerTrainingAdapting = CreateMLRecognizerTrainingAdapter(),
    workflowConfigurationStore: any WorkflowConfigurationLoading = WorkflowConfigurationStore(),
    ghosttyPlatformAdapter: any GhosttyPlatformAdapting = GhosttyPlatformAdapter(),
    herdrAgentAdapter: any HerdrAgentAdapting = HerdrAgentAdapter(),
    domainExpansionHUDPresenter: any DomainExpansionHUDPresenting =
      AppKitDomainExpansionHUDAdapter(),
    poseDatasetFolderSelector: any PoseDatasetFolderSelecting = SystemPoseDatasetFolderPicker(),
    poseDatasetPreparer: any PoseDatasetPreparing = PoseDatasetAdapter(),
    eventSink: @escaping (AppEvent) -> Void,
    menuSink: @escaping (MenuPresentation) -> Void,
    workflowSink: @escaping (PrimaryWorkflowPresentation?) -> Void,
    recognitionDiagnosticsSink: @escaping (RecognitionDiagnosticsUpdate) -> Void = {
      _ in
    },
    domainExpansionCandidateProgressSink: @escaping (DomainExpansionCandidateProgress?) -> Void = {
      _ in
    },
    poseDatasetSink: @escaping (PoseDatasetImportPresentation?) -> Void = { _ in },
    recognizerTrainingSink: @escaping (RecognizerTrainingPresentation?) -> Void = { _ in }
  ) {
    self.recognizerStore = recognizerStore
    self.cameraAdapter = cameraAdapter
    self.recognitionAdapter = recognitionAdapter
    self.recognitionClock = recognitionClock
    self.recognizerTrainer = recognizerTrainer
    self.workflowConfigurationStore = workflowConfigurationStore
    self.ghosttyPlatformAdapter = ghosttyPlatformAdapter
    self.herdrAgentAdapter = herdrAgentAdapter
    self.domainExpansionHUDPresenter = domainExpansionHUDPresenter
    self.poseDatasetFolderSelector = poseDatasetFolderSelector
    self.poseDatasetPreparer = poseDatasetPreparer
    self.eventSink = eventSink
    self.menuSink = menuSink
    self.workflowSink = workflowSink
    self.recognitionDiagnosticsSink = recognitionDiagnosticsSink
    self.domainExpansionCandidateProgressSink = domainExpansionCandidateProgressSink
    self.poseDatasetSink = poseDatasetSink
    self.recognizerTrainingSink = recognizerTrainingSink
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
      cameraAdapter.execute(
        cameraEffect,
        eventSink: { [weak self] event in
          self?.eventSink(.camera(event))
        },
        frameSink: { [weak self] frame in
          guard let self else { return }
          recognitionAdapter.receive(frame)
          eventSink(.recognitionFrameCaptured(frame.reference))
        }
      )
    case .recognition(let recognitionEffect):
      recognitionAdapter.execute(recognitionEffect) { [weak self] analysis in
        guard let self else { return }
        pendingRecognitionAnalyses[analysis.frame] = analysis
        defer { pendingRecognitionAnalyses.removeValue(forKey: analysis.frame) }
        eventSink(.recognitionClockRead(recognitionClock.now()))
        eventSink(.recognitionFrameCompleted(analysis.completion))
      }
    case .presentMenu(let presentation):
      menuSink(presentation)
      eventSink(.menuPresented(presentation))
    case .openRecognitionDiagnostics(let session):
      recognitionDiagnosticsSink(.opened(session))
    case .closeRecognitionDiagnostics:
      pendingRecognitionAnalyses.removeAll()
      recognitionDiagnosticsSink(.closed)
    case .presentRecognitionDiagnosticsFrame(let diagnostics):
      guard
        let analysis = pendingRecognitionAnalyses.removeValue(
          forKey: diagnostics.frame
        )
      else { return }
      recognitionDiagnosticsSink(
        .snapshot(
          RecognitionDiagnosticsSnapshot(
            diagnostics: diagnostics,
            analysis: analysis
          )
        )
      )
    case .clearRecognitionEvidence:
      pendingRecognitionAnalyses.removeAll()
      recognitionAdapter.reset()
    case .presentDomainExpansionCandidateProgress(let progress):
      domainExpansionCandidateProgressSink(progress)
    case .presentDomainExpansionHUD(let presentationEffect):
      domainExpansionHUDPresenter.execute(presentationEffect) { [weak self] event in
        self?.eventSink(.domainExpansionHUD(event))
      }
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
    case .startPiAgent(let workspacePath, let command):
      herdrAgentAdapter.startPiAgent(
        workspacePath: workspacePath,
        command: command
      ) { [weak self] result in
        self?.eventSink(.herdrAgentStartCompleted(result))
      }
    case .primaryWorkflowLeadingPiAgentFocused:
      workflowSink(.leadingPiAgentFocused)
    case .primaryWorkflowPiAgentStarted:
      workflowSink(.piAgentStarted)
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
    case .presentRecognizerTraining(let presentation):
      recognizerTrainingSink(presentation)
    case .startRecognizerTraining(let input):
      recognizerTrainer.start(
        with: input,
        progress: { [weak self] progress in
          self?.eventSink(.recognizerTrainingProgressed(progress))
        },
        completion: { [weak self] result in
          self?.eventSink(.recognizerTrainingCompleted(result))
        }
      )
    case .cancelRecognizerTraining:
      recognizerTrainer.cancel()
    case .savePersonalRecognizerCandidate(let artifact):
      let recognizerStore = recognizerStore
      Task { [weak self] in
        let result = await recognizerStore.saveCandidate(from: artifact)
        self?.eventSink(.personalRecognizerCandidateSaveCompleted(result))
      }
    case .replacePersonalRecognizer(let candidate):
      let recognizerStore = recognizerStore
      Task { [weak self] in
        let result = await recognizerStore.replaceActiveModel(with: candidate)
        self?.eventSink(.personalRecognizerReplacementCompleted(result))
      }
    case .terminateApplication:
      NSApplication.shared.terminate(nil)
    }
  }

  private func sendPoseDatasetProgress(_ progress: PoseDatasetPreparationProgress) {
    eventSink(.poseDatasetPreparationProgressed(progress))
  }
}
