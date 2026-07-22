import Foundation

public enum PersonalRecognizerAvailability: Equatable, Sendable {
  case available
  case missing
}

public enum MenuBarApplicationConfigurationResult: Equatable, Sendable {
  case succeeded
  case failed
}

public enum CameraAuthorizationStatus: Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
  case restricted
}

public enum CameraCaptureFailure: Equatable, Sendable {
  case builtInCameraUnavailable
  case configurationFailed
  case startFailed
}

public enum CameraCaptureStartResult: Equatable, Sendable {
  case succeeded
  case failed(CameraCaptureFailure)
}

public enum CameraUnavailableReason: Equatable, Sendable {
  case authorizationDenied
  case authorizationRestricted
  case capture(CameraCaptureFailure)
}

public enum CameraEvent: Equatable, Sendable {
  case authorizationChanged(CameraAuthorizationStatus)
  case captureStartCompleted(CameraCaptureStartResult)
  case released
  case captureInterrupted
  case captureInterruptionEnded
  case systemWillSleep
  case systemDidWake
  case cameraSwitchDetected
}

public enum CameraEffect: Equatable, Sendable {
  case requestAuthorization
  case startBuiltInCamera
  case stopCapture
  case stopAndReleaseCamera
  case rebuildBuiltInCamera
}

public struct WorkflowConfiguration: Equatable, Sendable {
  public let workspacePath: String
  public let piCommand: [String]

  public init(workspacePath: String, piCommand: [String]) {
    self.workspacePath = workspacePath
    self.piCommand = piCommand
  }
}

public enum WorkflowConfigurationFailure: Equatable, Sendable {
  case unavailable
  case malformed
  case invalidStructure
  case emptyWorkspacePath
  case emptyPiCommand
}

public enum WorkflowConfigurationLoadResult: Equatable, Sendable {
  case loaded(WorkflowConfiguration)
  case failed(WorkflowConfigurationFailure)
}

public struct GhosttyApplication: Equatable, Sendable {
  public let path: String
  public let version: String?
  public let isRunning: Bool

  public init(path: String, version: String?, isRunning: Bool) {
    self.path = path
    self.version = version
    self.isRunning = isRunning
  }
}

public enum GhosttyResolutionResult: Equatable, Sendable {
  case found(GhosttyApplication)
  case notInstalled
}

public enum GhosttyLaunchResult: Equatable, Sendable {
  case succeeded
  case failed
}

public enum DefaultHerdrSession: Equatable, Sendable {
  case reused
  case started
}

public enum GhosttyAutomationFailure: Equatable, Sendable {
  case denied
  case unavailable
}

public enum DefaultHerdrSessionEnsureResult: Equatable, Sendable {
  case ready(DefaultHerdrSession)
  case automationFailed(GhosttyAutomationFailure)
  case herdrUnavailable
}

public struct HerdrAgent: Equatable, Sendable {
  public let paneID: String
  public let agent: String
  public let cwd: String?
  public let foregroundCwd: String?

  public init(
    paneID: String,
    agent: String,
    cwd: String?,
    foregroundCwd: String?
  ) {
    self.paneID = paneID
    self.agent = agent
    self.cwd = cwd
    self.foregroundCwd = foregroundCwd
  }
}

public enum HerdrAgentQueryResult: Equatable, Sendable {
  case agents([HerdrAgent])
  case herdrUnavailable
  case malformedOutput
}

public enum HerdrAgentFocusResult: Equatable, Sendable {
  case succeeded
  case failed
}

public enum PrimaryWorkflowFailure: Equatable, Sendable {
  case configuration(WorkflowConfigurationFailure)
  case ghosttyNotInstalled
  case ghosttyVersionUnavailable
  case ghosttyVersionInvalid(String)
  case ghosttyVersionUnsupported(found: String, minimum: String)
  case ghosttyLaunchFailed
  case ghosttyAutomationDenied
  case ghosttyAutomationUnavailable
  case herdrUnavailable
  case malformedHerdrOutput
}

public struct PrimaryWorkflowContext: Equatable, Sendable {
  public let configuration: WorkflowConfiguration
  public let defaultHerdrSession: DefaultHerdrSession

  public init(
    configuration: WorkflowConfiguration,
    defaultHerdrSession: DefaultHerdrSession
  ) {
    self.configuration = configuration
    self.defaultHerdrSession = defaultHerdrSession
  }
}

public struct LeadingPiAgentContext: Equatable, Sendable {
  public let workflow: PrimaryWorkflowContext
  public let agent: HerdrAgent

  public init(workflow: PrimaryWorkflowContext, agent: HerdrAgent) {
    self.workflow = workflow
    self.agent = agent
  }
}

public enum AppEvent: Equatable, Sendable {
  case appLaunched
  case menuBarApplicationConfigurationCompleted(MenuBarApplicationConfigurationResult)
  case personalRecognizerChecked(PersonalRecognizerAvailability)
  case camera(CameraEvent)
  case menuPresented(MenuPresentation)
  case pauseMonitoringRequested
  case resumeMonitoringRequested
  case primaryWorkflowRequested
  case workflowConfigurationLoadCompleted(WorkflowConfigurationLoadResult)
  case ghosttyResolutionCompleted(GhosttyResolutionResult)
  case ghosttyLaunchCompleted(GhosttyLaunchResult)
  case defaultHerdrSessionEnsureCompleted(DefaultHerdrSessionEnsureResult)
  case herdrAgentQueryCompleted(HerdrAgentQueryResult)
  case herdrAgentFocusCompleted(HerdrAgentFocusResult)
  case poseDatasetImportRequested
  case poseDatasetFolderSelectionCompleted(PoseDatasetFolderSelectionResult)
  case poseDatasetPreparationProgressed(PoseDatasetPreparationProgress)
  case poseDatasetPreparationCompleted(PoseDatasetPreparationResult)
  case recognizerTrainingRequested
  case recognizerTrainingCancellationRequested
  case recognizerTrainingProgressed(RecognizerTrainingProgress)
  case recognizerTrainingCompleted(RecognizerTrainingResult)
  case personalRecognizerCandidateSaveCompleted(PersonalRecognizerCandidateSaveResult)
  case personalRecognizerReplacementCompleted(PersonalRecognizerReplacementResult)
  case quitRequested
}

public enum MenuPresentation: Equatable, Sendable {
  case awaitingCameraAuthorization
  case activeMonitoring
  case pausedMonitoring
  case captureInterrupted
  case cameraUnavailable(CameraUnavailableReason)
  case setupRequired
}

public enum AppEffect: Equatable, Sendable {
  case configureMenuBarApplication
  case checkPersonalRecognizer
  case camera(CameraEffect)
  case presentMenu(MenuPresentation)
  case clearRecognitionEvidence
  case loadWorkflowConfiguration
  case resolveGhostty
  case launchGhostty(at: String)
  case ensureDefaultHerdrSession
  case queryHerdrAgents
  case focusHerdrAgent(paneID: String)
  case primaryWorkflowNoMatchingAgent(PrimaryWorkflowContext)
  case primaryWorkflowLeadingPiAgentFocused(LeadingPiAgentContext)
  case primaryWorkflowFailed(PrimaryWorkflowFailure)
  case presentPoseDatasetImport(PoseDatasetImportPresentation?)
  case selectPoseDatasetFolder
  case preparePoseDataset(at: String)
  case presentRecognizerTraining(RecognizerTrainingPresentation?)
  case startRecognizerTraining(PoseDatasetTrainingInput)
  case cancelRecognizerTraining
  case savePersonalRecognizerCandidate(RecognizerTrainingArtifact)
  case replacePersonalRecognizer(PersonalRecognizerCandidate)
  case terminateApplication
}

public typealias Effects = [AppEffect]

public final class LaunchCoordinator {
  private enum WakeAction {
    case startCapture
    case requestAuthorization
    case remainPaused
    case presentPaused
  }

  private enum CameraReleaseDestination {
    case paused
    case sleeping(WakeAction, wakeReceived: Bool)
    case unavailable(CameraUnavailableReason)
    case terminated
  }

  private enum MonitoringPoseDatasetState: Equatable {
    case idle
    case choosingFolder
    case validating
    case ready
  }

  private enum RecognizerTrainingPriorState {
    case activeMonitoring
    case pausedMonitoring
    case setupRequired
  }

  private struct RecognizerTrainingContext {
    let input: PoseDatasetTrainingInput
    let priorState: RecognizerTrainingPriorState
  }

  private enum RecognizerTrainingOutcome {
    case succeeded
    case cancelled
    case failed(RecognizerTrainingFailure)
  }

  private enum MonitoringState {
    case awaitingAuthorization
    case startingCapture
    case active
    case interrupted
    case rebuildingCapture
    case releasing(CameraReleaseDestination)
    case sleeping(WakeAction)
    case paused
    case unavailable(CameraUnavailableReason)
  }

  private enum State {
    case awaitingLaunch
    case configuringMenuBarApplication
    case checkingPersonalRecognizer
    case monitoring(MonitoringState)
    case setupRequired
    case choosingPoseDatasetFolder
    case validatingPoseDataset
    case poseDatasetReady(PoseDatasetTrainingInput)
    case suspendingRecognizerTraining(RecognizerTrainingContext)
    case trainingRecognizer(RecognizerTrainingContext)
    case cancellingRecognizerTrainingBeforeStart(RecognizerTrainingContext)
    case cancellingRecognizerTraining(RecognizerTrainingContext)
    case savingPersonalRecognizer(RecognizerTrainingContext)
    case replacingPersonalRecognizer(RecognizerTrainingContext)
    case terminatingAfterRecognizerTrainingCameraRelease
    case terminated
  }

  private enum PrimaryWorkflowState {
    case idle
    case loadingConfiguration
    case resolvingGhostty(WorkflowConfiguration)
    case launchingGhostty(WorkflowConfiguration)
    case ensuringDefaultHerdrSession(WorkflowConfiguration)
    case queryingHerdrAgents(PrimaryWorkflowContext)
    case focusingHerdrAgent(PrimaryWorkflowContext, HerdrAgent)
  }

  private var state: State = .awaitingLaunch
  private var primaryWorkflowState: PrimaryWorkflowState = .idle
  private var monitoringPoseDatasetState: MonitoringPoseDatasetState = .idle
  private var validatedTrainingInput: PoseDatasetTrainingInput?

  public init() {}

  public func handle(_ event: AppEvent) -> Effects {
    if let effects = handleMonitoringPoseDataset(event) {
      return effects
    }

    switch (state, event) {
    case (.awaitingLaunch, .appLaunched):
      state = .configuringMenuBarApplication
      return [.configureMenuBarApplication]

    case (
      .configuringMenuBarApplication,
      .menuBarApplicationConfigurationCompleted(_)
    ):
      state = .checkingPersonalRecognizer
      return [.checkPersonalRecognizer]

    case (.checkingPersonalRecognizer, .personalRecognizerChecked(.available)):
      state = .monitoring(.awaitingAuthorization)
      return [
        .presentMenu(.awaitingCameraAuthorization),
        .camera(.requestAuthorization),
      ]

    case (
      .monitoring(.awaitingAuthorization),
      .camera(.authorizationChanged(.authorized))
    ),
      (
        .monitoring(.unavailable),
        .camera(.authorizationChanged(.authorized))
      ):
      state = .monitoring(.startingCapture)
      return [.camera(.startBuiltInCamera)]

    case (
      .monitoring(.awaitingAuthorization),
      .camera(.authorizationChanged(.notDetermined))
    ):
      return []

    case (.monitoring(.active), .camera(.authorizationChanged(.denied))),
      (.monitoring(.startingCapture), .camera(.authorizationChanged(.denied))),
      (.monitoring(.interrupted), .camera(.authorizationChanged(.denied))),
      (.monitoring(.rebuildingCapture), .camera(.authorizationChanged(.denied))):
      return releaseCameraAfterAuthorizationFailure(.authorizationDenied)

    case (.monitoring(.active), .camera(.authorizationChanged(.restricted))),
      (.monitoring(.startingCapture), .camera(.authorizationChanged(.restricted))),
      (.monitoring(.interrupted), .camera(.authorizationChanged(.restricted))),
      (.monitoring(.rebuildingCapture), .camera(.authorizationChanged(.restricted))):
      return releaseCameraAfterAuthorizationFailure(.authorizationRestricted)

    case (
      .monitoring(.awaitingAuthorization),
      .camera(.authorizationChanged(.denied))
    ):
      let reason = CameraUnavailableReason.authorizationDenied
      state = .monitoring(.unavailable(reason))
      return [.presentMenu(.cameraUnavailable(reason))]

    case (
      .monitoring(.awaitingAuthorization),
      .camera(.authorizationChanged(.restricted))
    ):
      let reason = CameraUnavailableReason.authorizationRestricted
      state = .monitoring(.unavailable(reason))
      return [.presentMenu(.cameraUnavailable(reason))]

    case (
      .monitoring(.startingCapture),
      .camera(.captureStartCompleted(.succeeded))
    ),
      (
        .monitoring(.rebuildingCapture),
        .camera(.captureStartCompleted(.succeeded))
      ):
      state = .monitoring(.active)
      return [.presentMenu(.activeMonitoring)]

    case (
      .monitoring(.startingCapture),
      .camera(.captureStartCompleted(.failed(let failure)))
    ),
      (
        .monitoring(.rebuildingCapture),
        .camera(.captureStartCompleted(.failed(let failure)))
      ):
      let reason = CameraUnavailableReason.capture(failure)
      state = .monitoring(.unavailable(reason))
      return [.presentMenu(.cameraUnavailable(reason))]

    case (.monitoring(.active), .camera(.captureInterrupted)),
      (.monitoring(.startingCapture), .camera(.captureInterrupted)),
      (.monitoring(.rebuildingCapture), .camera(.captureInterrupted)):
      state = .monitoring(.interrupted)
      return [
        .clearRecognitionEvidence,
        .camera(.stopCapture),
        .presentMenu(.captureInterrupted),
      ]

    case (
      .monitoring(.interrupted),
      .camera(.captureInterruptionEnded)
    ):
      state = .monitoring(.startingCapture)
      return [.camera(.startBuiltInCamera)]

    case (.monitoring(.active), .camera(.cameraSwitchDetected)),
      (.monitoring(.startingCapture), .camera(.cameraSwitchDetected)),
      (.monitoring(.interrupted), .camera(.cameraSwitchDetected)):
      state = .monitoring(.rebuildingCapture)
      return [
        .clearRecognitionEvidence,
        .camera(.rebuildBuiltInCamera),
        .presentMenu(.captureInterrupted),
      ]

    case (.monitoring(.paused), .camera(.cameraSwitchDetected)),
      (.monitoring(.awaitingAuthorization), .camera(.cameraSwitchDetected)),
      (.monitoring(.unavailable), .camera(.cameraSwitchDetected)):
      return [.clearRecognitionEvidence]

    case (.monitoring(.active), .camera(.systemWillSleep)),
      (.monitoring(.startingCapture), .camera(.systemWillSleep)),
      (.monitoring(.interrupted), .camera(.systemWillSleep)),
      (.monitoring(.rebuildingCapture), .camera(.systemWillSleep)):
      state = .monitoring(
        .releasing(.sleeping(.startCapture, wakeReceived: false))
      )
      return [
        .clearRecognitionEvidence,
        .camera(.stopAndReleaseCamera),
        .presentMenu(.captureInterrupted),
      ]

    case (.monitoring(.paused), .camera(.systemWillSleep)):
      state = .monitoring(.sleeping(.remainPaused))
      return [.clearRecognitionEvidence]

    case (.monitoring(.awaitingAuthorization), .camera(.systemWillSleep)),
      (.monitoring(.unavailable), .camera(.systemWillSleep)):
      state = .monitoring(.sleeping(.requestAuthorization))
      return [.clearRecognitionEvidence]

    case (
      .monitoring(.releasing(.sleeping(let action, wakeReceived: false))),
      .camera(.systemDidWake)
    ):
      state = .monitoring(
        .releasing(.sleeping(action, wakeReceived: true))
      )
      return []

    case (
      .monitoring(.releasing(.sleeping(let action, wakeReceived: false))),
      .camera(.released)
    ):
      state = .monitoring(.sleeping(action))
      return []

    case (
      .monitoring(.releasing(.sleeping(let action, wakeReceived: true))),
      .camera(.released)
    ),
      (
        .monitoring(.sleeping(let action)),
        .camera(.systemDidWake)
      ):
      return resumeAfterSleep(action)

    case (
      .monitoring(.releasing(.sleeping(_, wakeReceived: let wakeReceived))),
      .pauseMonitoringRequested
    ):
      state = .monitoring(
        .releasing(.sleeping(.presentPaused, wakeReceived: wakeReceived))
      )
      return []

    case (.monitoring(.sleeping), .pauseMonitoringRequested):
      state = .monitoring(.sleeping(.presentPaused))
      return []

    case (.monitoring(.awaitingAuthorization), .pauseMonitoringRequested),
      (.monitoring(.unavailable), .pauseMonitoringRequested):
      state = .monitoring(.paused)
      return [
        .clearRecognitionEvidence,
        .presentMenu(.pausedMonitoring),
      ]

    case (.monitoring(.active), .pauseMonitoringRequested),
      (.monitoring(.startingCapture), .pauseMonitoringRequested),
      (.monitoring(.rebuildingCapture), .pauseMonitoringRequested):
      state = .monitoring(.releasing(.paused))
      return [
        .clearRecognitionEvidence,
        .camera(.stopAndReleaseCamera),
      ]

    case (.monitoring(.interrupted), .pauseMonitoringRequested):
      state = .monitoring(.releasing(.paused))
      return [.camera(.stopAndReleaseCamera)]

    case (
      .monitoring(.releasing(.paused)),
      .camera(.released)
    ):
      state = .monitoring(.paused)
      return [.presentMenu(.pausedMonitoring)]

    case (
      .monitoring(.releasing(.unavailable(let reason))),
      .camera(.released)
    ):
      state = .monitoring(.unavailable(reason))
      return []

    case (
      .monitoring(.releasing(.unavailable)),
      .pauseMonitoringRequested
    ):
      state = .monitoring(.releasing(.paused))
      return []

    case (.monitoring(.paused), .resumeMonitoringRequested):
      state = .monitoring(.awaitingAuthorization)
      return [
        .presentMenu(.awaitingCameraAuthorization),
        .camera(.requestAuthorization),
      ]

    case (.checkingPersonalRecognizer, .personalRecognizerChecked(.missing)):
      state = .setupRequired
      return [.presentMenu(.setupRequired)]

    case (.setupRequired, .poseDatasetImportRequested),
      (.poseDatasetReady, .poseDatasetImportRequested):
      state = .choosingPoseDatasetFolder
      return [
        .presentPoseDatasetImport(.choosingFolder),
        .selectPoseDatasetFolder,
      ]

    case (
      .choosingPoseDatasetFolder,
      .poseDatasetFolderSelectionCompleted(.selected(let path))
    ):
      state = .validatingPoseDataset
      return [
        .presentPoseDatasetImport(.validating(nil)),
        .preparePoseDataset(at: path),
      ]

    case (
      .choosingPoseDatasetFolder,
      .poseDatasetFolderSelectionCompleted(.cancelled)
    ):
      state = .setupRequired
      return [.presentPoseDatasetImport(nil)]

    case (
      .validatingPoseDataset,
      .poseDatasetPreparationProgressed(let progress)
    ):
      return [.presentPoseDatasetImport(.validating(progress))]

    case (
      .validatingPoseDataset,
      .poseDatasetPreparationCompleted(.succeeded(let input))
    ):
      validatedTrainingInput = input
      state = .poseDatasetReady(input)
      return [.presentPoseDatasetImport(.ready(input))]

    case (.poseDatasetReady(let input), .recognizerTrainingRequested):
      let context = RecognizerTrainingContext(
        input: input,
        priorState: .setupRequired
      )
      state = .trainingRecognizer(context)
      return [
        .presentRecognizerTraining(.training(nil)),
        .startRecognizerTraining(input),
      ]

    case (.monitoring(.active), .recognizerTrainingRequested):
      guard let input = validatedTrainingInput else { return [] }
      let context = RecognizerTrainingContext(
        input: input,
        priorState: .activeMonitoring
      )
      state = .suspendingRecognizerTraining(context)
      return [
        .presentRecognizerTraining(.preparing),
        .clearRecognitionEvidence,
        .camera(.stopAndReleaseCamera),
      ]

    case (.monitoring(.paused), .recognizerTrainingRequested):
      guard let input = validatedTrainingInput else { return [] }
      let context = RecognizerTrainingContext(
        input: input,
        priorState: .pausedMonitoring
      )
      state = .trainingRecognizer(context)
      return [
        .presentRecognizerTraining(.training(nil)),
        .startRecognizerTraining(input),
      ]

    case (
      .suspendingRecognizerTraining(let context),
      .camera(.released)
    ):
      state = .trainingRecognizer(context)
      return [
        .presentRecognizerTraining(.training(nil)),
        .startRecognizerTraining(context.input),
      ]

    case (
      .suspendingRecognizerTraining(let context),
      .recognizerTrainingCancellationRequested
    ):
      state = .cancellingRecognizerTrainingBeforeStart(context)
      return [.presentRecognizerTraining(.cancelling)]

    case (
      .cancellingRecognizerTrainingBeforeStart(let context),
      .camera(.released)
    ):
      return restoreAfterRecognizerTraining(context, outcome: .cancelled)

    case (
      .trainingRecognizer,
      .recognizerTrainingProgressed(let progress)
    ):
      return [.presentRecognizerTraining(.training(progress))]

    case (
      .trainingRecognizer(let context),
      .recognizerTrainingCancellationRequested
    ):
      state = .cancellingRecognizerTraining(context)
      return [
        .presentRecognizerTraining(.cancelling),
        .cancelRecognizerTraining,
      ]

    case (
      .cancellingRecognizerTraining(let context),
      .recognizerTrainingCompleted
    ):
      return restoreAfterRecognizerTraining(context, outcome: .cancelled)

    case (
      .trainingRecognizer(let context),
      .recognizerTrainingCompleted(.succeeded(let artifact))
    ):
      state = .savingPersonalRecognizer(context)
      return [
        .presentRecognizerTraining(.saving),
        .savePersonalRecognizerCandidate(artifact),
      ]

    case (
      .trainingRecognizer(let context),
      .recognizerTrainingCompleted(.failed(let failure))
    ):
      return restoreAfterRecognizerTraining(
        context,
        outcome: .failed(.training(failure))
      )

    case (
      .trainingRecognizer(let context),
      .recognizerTrainingCompleted(.cancelled)
    ):
      return restoreAfterRecognizerTraining(context, outcome: .cancelled)

    case (
      .savingPersonalRecognizer(let context),
      .personalRecognizerCandidateSaveCompleted(.succeeded(let candidate))
    ):
      state = .replacingPersonalRecognizer(context)
      return [
        .presentRecognizerTraining(.replacing),
        .replacePersonalRecognizer(candidate),
      ]

    case (
      .savingPersonalRecognizer(let context),
      .personalRecognizerCandidateSaveCompleted(.failed(let failure))
    ):
      return restoreAfterRecognizerTraining(
        context,
        outcome: .failed(.candidateSave(failure))
      )

    case (
      .replacingPersonalRecognizer(let context),
      .personalRecognizerReplacementCompleted(.succeeded)
    ):
      return restoreAfterRecognizerTraining(context, outcome: .succeeded)

    case (
      .replacingPersonalRecognizer(let context),
      .personalRecognizerReplacementCompleted(.failed(let failure))
    ):
      return restoreAfterRecognizerTraining(
        context,
        outcome: .failed(.modelReplacement(failure))
      )

    case (
      .validatingPoseDataset,
      .poseDatasetPreparationCompleted(.failed(let failure))
    ):
      state = .setupRequired
      return [.presentPoseDatasetImport(.failed(failure))]

    case (.suspendingRecognizerTraining, .quitRequested),
      (
        .cancellingRecognizerTrainingBeforeStart,
        .quitRequested
      ):
      state = .terminatingAfterRecognizerTrainingCameraRelease
      primaryWorkflowState = .idle
      return []

    case (
      .terminatingAfterRecognizerTrainingCameraRelease,
      .camera(.released)
    ):
      state = .terminated
      return [.terminateApplication]

    case (.terminatingAfterRecognizerTrainingCameraRelease, .quitRequested):
      return []

    case (.trainingRecognizer, .quitRequested):
      state = .terminated
      primaryWorkflowState = .idle
      return [.cancelRecognizerTraining, .terminateApplication]

    case (
      .cancellingRecognizerTraining,
      .quitRequested
    ), (.savingPersonalRecognizer, .quitRequested),
      (.replacingPersonalRecognizer, .quitRequested):
      state = .terminated
      primaryWorkflowState = .idle
      return [.terminateApplication]

    case (.monitoring(.active), .quitRequested),
      (.monitoring(.startingCapture), .quitRequested),
      (.monitoring(.interrupted), .quitRequested),
      (.monitoring(.rebuildingCapture), .quitRequested):
      state = .monitoring(.releasing(.terminated))
      primaryWorkflowState = .idle
      return [
        .clearRecognitionEvidence,
        .camera(.stopAndReleaseCamera),
      ]

    case (.monitoring(.releasing(.paused)), .quitRequested),
      (.monitoring(.releasing(.sleeping)), .quitRequested),
      (.monitoring(.releasing(.unavailable)), .quitRequested):
      state = .monitoring(.releasing(.terminated))
      primaryWorkflowState = .idle
      return []

    case (
      .monitoring(.releasing(.terminated)),
      .camera(.released)
    ):
      state = .terminated
      return [.terminateApplication]

    case (.monitoring(.releasing(.terminated)), .quitRequested):
      return []

    case (.awaitingLaunch, .quitRequested),
      (.configuringMenuBarApplication, .quitRequested),
      (.checkingPersonalRecognizer, .quitRequested),
      (.monitoring(.awaitingAuthorization), .quitRequested),
      (.monitoring(.sleeping), .quitRequested),
      (.monitoring(.paused), .quitRequested),
      (.monitoring(.unavailable), .quitRequested),
      (.setupRequired, .quitRequested),
      (.choosingPoseDatasetFolder, .quitRequested),
      (.validatingPoseDataset, .quitRequested),
      (.poseDatasetReady, .quitRequested):
      state = .terminated
      primaryWorkflowState = .idle
      return [.terminateApplication]

    default:
      return handlePrimaryWorkflow(event)
    }
  }

  private func handleMonitoringPoseDataset(_ event: AppEvent) -> Effects? {
    guard case .monitoring = state else { return nil }

    switch (monitoringPoseDatasetState, event) {
    case (.idle, .poseDatasetImportRequested),
      (.ready, .poseDatasetImportRequested):
      switch state {
      case .monitoring(.active), .monitoring(.paused):
        break
      default:
        return []
      }
      validatedTrainingInput = nil
      monitoringPoseDatasetState = .choosingFolder
      return [
        .presentPoseDatasetImport(.choosingFolder),
        .selectPoseDatasetFolder,
      ]

    case (
      .choosingFolder,
      .poseDatasetFolderSelectionCompleted(.selected(let path))
    ):
      monitoringPoseDatasetState = .validating
      return [
        .presentPoseDatasetImport(.validating(nil)),
        .preparePoseDataset(at: path),
      ]

    case (
      .choosingFolder,
      .poseDatasetFolderSelectionCompleted(.cancelled)
    ):
      monitoringPoseDatasetState = .idle
      return [.presentPoseDatasetImport(nil)]

    case (
      .validating,
      .poseDatasetPreparationProgressed(let progress)
    ):
      return [.presentPoseDatasetImport(.validating(progress))]

    case (
      .validating,
      .poseDatasetPreparationCompleted(.succeeded(let input))
    ):
      validatedTrainingInput = input
      monitoringPoseDatasetState = .ready
      return [.presentPoseDatasetImport(.ready(input))]

    case (
      .validating,
      .poseDatasetPreparationCompleted(.failed(let failure))
    ):
      monitoringPoseDatasetState = .idle
      return [.presentPoseDatasetImport(.failed(failure))]

    default:
      switch event {
      case .poseDatasetImportRequested,
        .poseDatasetFolderSelectionCompleted,
        .poseDatasetPreparationProgressed,
        .poseDatasetPreparationCompleted:
        return monitoringPoseDatasetState == .idle ? nil : []
      default:
        return nil
      }
    }
  }

  private func restoreAfterRecognizerTraining(
    _ context: RecognizerTrainingContext,
    outcome: RecognizerTrainingOutcome
  ) -> Effects {
    var effects: Effects
    switch outcome {
    case .succeeded:
      effects = [
        .clearRecognitionEvidence,
        .presentRecognizerTraining(.succeeded),
      ]
    case .cancelled:
      effects = [.presentRecognizerTraining(.cancelled)]
    case .failed(let failure):
      effects = [.presentRecognizerTraining(.failed(failure))]
    }

    switch context.priorState {
    case .activeMonitoring:
      state = .monitoring(.awaitingAuthorization)
      effects.append(.presentMenu(.awaitingCameraAuthorization))
      effects.append(.camera(.requestAuthorization))
    case .pausedMonitoring:
      state = .monitoring(.paused)
      effects.append(.presentMenu(.pausedMonitoring))
    case .setupRequired:
      if case .succeeded = outcome {
        state = .monitoring(.awaitingAuthorization)
        effects.append(.presentMenu(.awaitingCameraAuthorization))
        effects.append(.camera(.requestAuthorization))
      } else {
        state = .poseDatasetReady(context.input)
      }
    }
    return effects
  }

  private func releaseCameraAfterAuthorizationFailure(
    _ reason: CameraUnavailableReason
  ) -> Effects {
    state = .monitoring(.releasing(.unavailable(reason)))
    return [
      .clearRecognitionEvidence,
      .camera(.stopAndReleaseCamera),
      .presentMenu(.cameraUnavailable(reason)),
    ]
  }

  private func resumeAfterSleep(_ action: WakeAction) -> Effects {
    switch action {
    case .startCapture:
      state = .monitoring(.startingCapture)
      return [.camera(.startBuiltInCamera)]
    case .requestAuthorization:
      state = .monitoring(.awaitingAuthorization)
      return [
        .presentMenu(.awaitingCameraAuthorization),
        .camera(.requestAuthorization),
      ]
    case .remainPaused:
      state = .monitoring(.paused)
      return []
    case .presentPaused:
      state = .monitoring(.paused)
      return [.presentMenu(.pausedMonitoring)]
    }
  }

  private func handlePrimaryWorkflow(_ event: AppEvent) -> Effects {
    switch (primaryWorkflowState, event) {
    case (.idle, .primaryWorkflowRequested):
      guard case .monitoring(.active) = state else { return [] }
      primaryWorkflowState = .loadingConfiguration
      return [.loadWorkflowConfiguration]

    case (
      .loadingConfiguration,
      .workflowConfigurationLoadCompleted(.loaded(let configuration))
    ):
      primaryWorkflowState = .resolvingGhostty(configuration)
      return [.resolveGhostty]

    case (
      .loadingConfiguration,
      .workflowConfigurationLoadCompleted(.failed(let failure))
    ):
      primaryWorkflowState = .idle
      return [.primaryWorkflowFailed(.configuration(failure))]

    case (
      .resolvingGhostty(let configuration),
      .ghosttyResolutionCompleted(.found(let ghostty))
    ):
      if let versionFailure = GhosttyVersionPolicy.failure(for: ghostty.version) {
        primaryWorkflowState = .idle
        return [.primaryWorkflowFailed(versionFailure)]
      }

      if ghostty.isRunning {
        primaryWorkflowState = .ensuringDefaultHerdrSession(configuration)
        return [.ensureDefaultHerdrSession]
      }

      primaryWorkflowState = .launchingGhostty(configuration)
      return [.launchGhostty(at: ghostty.path)]

    case (.resolvingGhostty, .ghosttyResolutionCompleted(.notInstalled)):
      primaryWorkflowState = .idle
      return [.primaryWorkflowFailed(.ghosttyNotInstalled)]

    case (.launchingGhostty(let configuration), .ghosttyLaunchCompleted(.succeeded)):
      primaryWorkflowState = .ensuringDefaultHerdrSession(configuration)
      return [.ensureDefaultHerdrSession]

    case (.launchingGhostty, .ghosttyLaunchCompleted(.failed)):
      primaryWorkflowState = .idle
      return [.primaryWorkflowFailed(.ghosttyLaunchFailed)]

    case (
      .ensuringDefaultHerdrSession(let configuration),
      .defaultHerdrSessionEnsureCompleted(.ready(let session))
    ):
      primaryWorkflowState = .queryingHerdrAgents(
        PrimaryWorkflowContext(
          configuration: configuration,
          defaultHerdrSession: session
        )
      )
      return [.queryHerdrAgents]

    case (
      .queryingHerdrAgents(let context),
      .herdrAgentQueryCompleted(.agents(let agents))
    ):
      guard
        let agent = Self.leadingPiAgent(
          in: agents,
          workspacePath: context.configuration.workspacePath
        )
      else {
        primaryWorkflowState = .idle
        return [.primaryWorkflowNoMatchingAgent(context)]
      }
      primaryWorkflowState = .focusingHerdrAgent(context, agent)
      return [.focusHerdrAgent(paneID: agent.paneID)]

    case (.queryingHerdrAgents, .herdrAgentQueryCompleted(.herdrUnavailable)):
      primaryWorkflowState = .idle
      return [.primaryWorkflowFailed(.herdrUnavailable)]

    case (.queryingHerdrAgents, .herdrAgentQueryCompleted(.malformedOutput)):
      primaryWorkflowState = .idle
      return [.primaryWorkflowFailed(.malformedHerdrOutput)]

    case (
      .focusingHerdrAgent(let context, let agent),
      .herdrAgentFocusCompleted(.succeeded)
    ):
      primaryWorkflowState = .idle
      return [
        .primaryWorkflowLeadingPiAgentFocused(
          LeadingPiAgentContext(workflow: context, agent: agent)
        )
      ]

    case (.focusingHerdrAgent, .herdrAgentFocusCompleted(.failed)):
      primaryWorkflowState = .idle
      return [.primaryWorkflowFailed(.herdrUnavailable)]

    case (
      .ensuringDefaultHerdrSession,
      .defaultHerdrSessionEnsureCompleted(.automationFailed(let failure))
    ):
      primaryWorkflowState = .idle
      switch failure {
      case .denied:
        return [.primaryWorkflowFailed(.ghosttyAutomationDenied)]
      case .unavailable:
        return [.primaryWorkflowFailed(.ghosttyAutomationUnavailable)]
      }

    case (.ensuringDefaultHerdrSession, .defaultHerdrSessionEnsureCompleted(.herdrUnavailable)):
      primaryWorkflowState = .idle
      return [.primaryWorkflowFailed(.herdrUnavailable)]

    default:
      return []
    }
  }

  private static func leadingPiAgent(
    in agents: [HerdrAgent],
    workspacePath: String
  ) -> HerdrAgent? {
    let workspacePath = canonicalPath(workspacePath)
    return agents.first { agent in
      guard agent.agent == "pi" else { return false }
      return [agent.cwd, agent.foregroundCwd]
        .compactMap { $0 }
        .contains { canonicalPath($0) == workspacePath }
    }
  }

  private static func canonicalPath(_ path: String) -> String {
    let expandedPath = (path as NSString).expandingTildeInPath
    return URL(fileURLWithPath: expandedPath)
      .standardizedFileURL
      .resolvingSymlinksInPath()
      .path
  }
}
