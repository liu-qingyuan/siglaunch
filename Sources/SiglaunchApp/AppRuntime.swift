import Combine
import SiglaunchCore

@MainActor
final class AppRuntime: ObservableObject {
  @Published private(set) var menuPresentation: MenuPresentation?
  @Published private(set) var recognitionDiagnostics: RecognitionDiagnostics?
  @Published private(set) var domainExpansionCandidateProgress: DomainExpansionCandidateProgress?
  @Published private(set) var domainExpansionTriggerSequence: UInt64 = 0
  @Published private(set) var primaryWorkflowPresentation: PrimaryWorkflowPresentation?
  @Published private(set) var poseDatasetImportPresentation: PoseDatasetImportPresentation?
  @Published private(set) var recognizerTrainingPresentation: RecognizerTrainingPresentation?

  private let coordinator = LaunchCoordinator()
  private lazy var effectAdapter = ProductionEffectAdapter(
    recognizerStore: PersonalRecognizerStore(),
    eventSink: { [weak self] event in self?.send(event) },
    menuSink: { [weak self] presentation in
      self?.menuPresentation = presentation
    },
    workflowSink: { [weak self] presentation in
      self?.primaryWorkflowPresentation = presentation
    },
    recognitionDiagnosticsSink: { [weak self] diagnostics in
      self?.recognitionDiagnostics = diagnostics
    },
    domainExpansionCandidateProgressSink: { [weak self] progress in
      self?.domainExpansionCandidateProgress = progress
    },
    domainExpansionTriggerSink: { [weak self] in
      self?.domainExpansionTriggerSequence &+= 1
    },
    poseDatasetSink: { [weak self] presentation in
      self?.poseDatasetImportPresentation = presentation
    },
    recognizerTrainingSink: { [weak self] presentation in
      self?.recognizerTrainingPresentation = presentation
    }
  )

  var menuBarSymbol: String {
    if recognizerTrainingPresentation?.isInProgress == true {
      return recognizerTrainingPresentation?.content.symbolName ?? "cpu"
    }
    if let domainExpansionCandidateProgress {
      return domainExpansionCandidateProgress.symbolName
    }
    return menuPresentation?.content.symbolName ?? "viewfinder.circle"
  }

  init() {
    send(.appLaunched)
  }

  func send(_ event: AppEvent) {
    for effect in coordinator.handle(event) {
      effectAdapter.execute(effect)
    }
  }

  func pauseMonitoring() {
    send(.pauseMonitoringRequested)
  }

  func resumeMonitoring() {
    send(.resumeMonitoringRequested)
  }

  func selectRecognitionFrameRate(_ frameRate: RecognitionFrameRate) {
    send(.recognitionFrameRateRequested(frameRate))
  }

  func importPoseDataset() {
    send(.poseDatasetImportRequested)
  }

  func startRecognizerTraining() {
    send(.recognizerTrainingRequested)
  }

  func cancelRecognizerTraining() {
    send(.recognizerTrainingCancellationRequested)
  }
}
