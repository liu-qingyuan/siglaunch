import Combine
import SiglaunchCore

@MainActor
final class AppRuntime: ObservableObject {
  @Published private(set) var menuPresentation: MenuPresentation?
  @Published private(set) var recognitionFrameRate: RecognitionFrameRate = .defaultValue
  @Published private(set) var isRecognitionDiagnosticsOpen = false
  @Published private(set) var primaryWorkflowPresentation: PrimaryWorkflowPresentation?
  @Published private(set) var poseDatasetImportPresentation: PoseDatasetImportPresentation?
  @Published private(set) var recognizerTrainingPresentation: RecognizerTrainingPresentation?

  let recognitionDiagnosticsStore = RecognitionDiagnosticsStore()

  private let coordinator = LaunchCoordinator()
  private lazy var recognitionDiagnosticsWindowController =
    RecognitionDiagnosticsWindowController(
      store: recognitionDiagnosticsStore,
      onClose: { [weak self] in self?.send(.recognitionDiagnosticsClosed) }
    )
  private lazy var effectAdapter = ProductionEffectAdapter(
    recognizerStore: PersonalRecognizerStore(),
    eventSink: { [weak self] event in self?.send(event) },
    menuSink: { [weak self] presentation in
      self?.menuPresentation = presentation
    },
    workflowSink: { [weak self] presentation in
      self?.primaryWorkflowPresentation = presentation
    },
    recognitionDiagnosticsSink: { [weak self] update in
      guard let self else { return }
      switch update {
      case .opened(let session):
        isRecognitionDiagnosticsOpen = true
        recognitionDiagnosticsStore.setSession(session)
        recognitionDiagnosticsWindowController.show()
      case .snapshot(let snapshot):
        recognitionDiagnosticsStore.publish(snapshot)
      case .closed:
        isRecognitionDiagnosticsOpen = false
        recognitionDiagnosticsStore.setSession(nil)
        recognitionDiagnosticsWindowController.close()
      }
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
    recognitionFrameRate = frameRate
    send(.recognitionFrameRateRequested(frameRate))
  }

  func openRecognitionDiagnostics() {
    if isRecognitionDiagnosticsOpen {
      recognitionDiagnosticsWindowController.show()
    } else {
      send(.recognitionDiagnosticsRequested)
    }
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
