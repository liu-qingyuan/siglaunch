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

public enum RecognitionFrameRate: Int, CaseIterable, Equatable, Sendable {
  case fps10 = 10
  case fps15 = 15
  case fps30 = 30

  public static let defaultValue: RecognitionFrameRate = .fps15
}

public struct RecognitionLifecycleID: Equatable, Hashable, Sendable {
  public let rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }
}

public struct RecognitionFrameReference: Equatable, Hashable, Sendable {
  public let lifecycleID: RecognitionLifecycleID
  public let sequenceNumber: UInt64

  public init(lifecycleID: RecognitionLifecycleID, sequenceNumber: UInt64) {
    self.lifecycleID = lifecycleID
    self.sequenceNumber = sequenceNumber
  }
}

public struct RecognitionFrameRateSelection: Equatable, Sendable {
  public let lifecycleID: RecognitionLifecycleID
  public let targetFrameRate: RecognitionFrameRate
  public let actualFramesPerSecond: Double

  public init(
    lifecycleID: RecognitionLifecycleID,
    targetFrameRate: RecognitionFrameRate,
    actualFramesPerSecond: Double
  ) {
    self.lifecycleID = lifecycleID
    self.targetFrameRate = targetFrameRate
    self.actualFramesPerSecond = actualFramesPerSecond
  }
}

public enum DiagnosticHandDetection: Equatable, Sendable {
  case detected
  case notDetected
  case analysisFailed
}

public struct DiagnosticGestureResult: Equatable, Sendable {
  public let handDetection: DiagnosticHandDetection
  public let recognizedJointCount: Int
  public let extendedFingerCount: Int
  public let isOpenPalm: Bool

  public init(
    handDetection: DiagnosticHandDetection,
    recognizedJointCount: Int,
    extendedFingerCount: Int,
    isOpenPalm: Bool
  ) {
    self.handDetection = handDetection
    self.recognizedJointCount = recognizedJointCount
    self.extendedFingerCount = extendedFingerCount
    self.isOpenPalm = isOpenPalm
  }
}

public struct PersonalRecognizerClassification: Equatable, Sendable {
  public let label: String
  public let confidence: Double

  public init(label: String, confidence: Double) {
    self.label = label
    self.confidence = confidence
  }
}

public enum PersonalRecognizerInferenceResult: Equatable, Sendable {
  case classified([PersonalRecognizerClassification])
  case noHandDetected
  case failed
}

public struct DomainExpansionRecognitionPolicy: Equatable, Sendable {
  public let targetLabel: String
  public let minimumConfidence: Double
  public let evidenceWindowSize: Int
  public let requiredPoseMatchCount: Int

  public init(
    targetLabel: String,
    minimumConfidence: Double,
    evidenceWindowSize: Int,
    requiredPoseMatchCount: Int
  ) {
    precondition(!targetLabel.isEmpty)
    precondition((0...1).contains(minimumConfidence))
    precondition(evidenceWindowSize > 0)
    precondition((1...evidenceWindowSize).contains(requiredPoseMatchCount))
    self.targetLabel = targetLabel
    self.minimumConfidence = minimumConfidence
    self.evidenceWindowSize = evidenceWindowSize
    self.requiredPoseMatchCount = requiredPoseMatchCount
  }

  public static let standard = DomainExpansionRecognitionPolicy(
    targetLabel: "domain_expansion",
    minimumConfidence: 0.75,
    evidenceWindowSize: 5,
    requiredPoseMatchCount: 3
  )

  public func topClassification(
    in classifications: [PersonalRecognizerClassification]
  ) -> PersonalRecognizerClassification? {
    classifications.reduce(nil) { currentTop, candidate in
      guard
        candidate.confidence.isFinite,
        (0...1).contains(candidate.confidence)
      else {
        return currentTop
      }
      guard let currentTop else { return candidate }
      return candidate.confidence > currentTop.confidence
        ? candidate
        : currentTop
    }
  }

  public func isPoseMatch(
    _ classification: PersonalRecognizerClassification
  ) -> Bool {
    classification.label == targetLabel
      && classification.confidence >= minimumConfidence
  }
}

public struct RecognitionDiagnosticsSession: Equatable, Sendable {
  public let policy: DomainExpansionRecognitionPolicy
  public let targetFrameRate: RecognitionFrameRate
  public let captureFramesPerSecond: Double?

  public init(
    policy: DomainExpansionRecognitionPolicy,
    targetFrameRate: RecognitionFrameRate,
    captureFramesPerSecond: Double?
  ) {
    self.policy = policy
    self.targetFrameRate = targetFrameRate
    self.captureFramesPerSecond = captureFramesPerSecond
  }
}

public struct RecognitionDiagnosticsFrame: Equatable, Sendable {
  public let frame: RecognitionFrameReference
  public let policy: DomainExpansionRecognitionPolicy
  public let topClassification: PersonalRecognizerClassification?
  public let isPoseMatch: Bool?
  public let poseMatchCount: Int
  public let targetFrameRate: RecognitionFrameRate
  public let captureFramesPerSecond: Double?
  public let completedRecognitionFramesPerSecond: Double

  public init(
    frame: RecognitionFrameReference,
    policy: DomainExpansionRecognitionPolicy,
    topClassification: PersonalRecognizerClassification?,
    isPoseMatch: Bool?,
    poseMatchCount: Int,
    targetFrameRate: RecognitionFrameRate,
    captureFramesPerSecond: Double?,
    completedRecognitionFramesPerSecond: Double
  ) {
    precondition((0...policy.evidenceWindowSize).contains(poseMatchCount))
    self.frame = frame
    self.policy = policy
    self.topClassification = topClassification
    self.isPoseMatch = isPoseMatch
    self.poseMatchCount = poseMatchCount
    self.targetFrameRate = targetFrameRate
    self.captureFramesPerSecond = captureFramesPerSecond
    self.completedRecognitionFramesPerSecond = completedRecognitionFramesPerSecond
  }

  public var isTriggerConditionSatisfied: Bool {
    poseMatchCount >= policy.requiredPoseMatchCount
  }
}

public struct DomainExpansionCandidateProgress: Equatable, Sendable {
  public let poseMatchCount: Int

  public init(poseMatchCount: Int) {
    precondition((1...2).contains(poseMatchCount))
    self.poseMatchCount = poseMatchCount
  }
}

/// Emitted only after every configured recognition stage finishes for a frame.
public struct RecognitionFrameCompletion: Equatable, Sendable {
  public let frame: RecognitionFrameReference
  public let diagnosticGesture: DiagnosticGestureResult
  public let personalRecognizerResult: PersonalRecognizerInferenceResult

  public init(
    frame: RecognitionFrameReference,
    diagnosticGesture: DiagnosticGestureResult,
    personalRecognizerResult: PersonalRecognizerInferenceResult
  ) {
    self.frame = frame
    self.diagnosticGesture = diagnosticGesture
    self.personalRecognizerResult = personalRecognizerResult
  }
}

public enum CameraEvent: Equatable, Sendable {
  case authorizationChanged(CameraAuthorizationStatus)
  case captureStartCompleted(
    lifecycleID: RecognitionLifecycleID,
    result: CameraCaptureStartResult
  )
  case recognitionFrameRateSelected(RecognitionFrameRateSelection)
  case released
  case captureInterrupted(lifecycleID: RecognitionLifecycleID)
  case captureInterruptionEnded(lifecycleID: RecognitionLifecycleID)
  case systemWillSleep
  case systemDidWake
  case cameraSwitchDetected
}

public enum CameraEffect: Equatable, Sendable {
  case requestAuthorization
  case startBuiltInCamera(
    targetFrameRate: RecognitionFrameRate,
    lifecycleID: RecognitionLifecycleID
  )
  case updateRecognitionFrameRate(
    targetFrameRate: RecognitionFrameRate,
    lifecycleID: RecognitionLifecycleID
  )
  case stopCapture
  case stopAndReleaseCamera
  case rebuildBuiltInCamera(
    targetFrameRate: RecognitionFrameRate,
    lifecycleID: RecognitionLifecycleID
  )
}

public enum RecognitionEffect: Equatable, Sendable {
  case analyzeFrame(RecognitionFrameReference)
  case discardFrame(RecognitionFrameReference)
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

public typealias PrimaryWorkflowAttemptID = UInt64

public enum HerdrAgentQueryPhase: Equatable, Sendable {
  case initial
  case postBootstrap
}

public enum HerdrAgentStartResult: Equatable, Sendable {
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
  case piStartFailed
}

public enum DomainExpansionHUDPresentationEffect: Equatable, Sendable {
  case showDomainExpansion
  case fade
  case showError(PrimaryWorkflowFailure)
  case dismiss
}

public enum DomainExpansionHUDPresentationEvent: Equatable, Sendable {
  case animationCompleted
  case presentationFailed(DomainExpansionHUDPresentationEffect)
  case dismissed
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

public enum AppEvent: Equatable, Sendable {
  case appLaunched
  case menuBarApplicationConfigurationCompleted(MenuBarApplicationConfigurationResult)
  case personalRecognizerChecked(PersonalRecognizerAvailability)
  case camera(CameraEvent)
  case recognitionFrameRateRequested(RecognitionFrameRate)
  case recognitionClockRead(TimeInterval)
  case recognitionFrameCaptured(RecognitionFrameReference)
  case recognitionFrameCompleted(RecognitionFrameCompletion)
  case recognitionDiagnosticsRequested
  case recognitionDiagnosticsClosed
  case menuPresented(MenuPresentation)
  case pauseMonitoringRequested
  case resumeMonitoringRequested
  case primaryWorkflowRequested
  case domainExpansionHUD(DomainExpansionHUDPresentationEvent)
  case workflowConfigurationLoadCompleted(WorkflowConfigurationLoadResult)
  case ghosttyResolutionCompleted(GhosttyResolutionResult)
  case ghosttyLaunchCompleted(GhosttyLaunchResult)
  case defaultHerdrSessionEnsureCompleted(DefaultHerdrSessionEnsureResult)
  case herdrAgentQueryCompleted(
    attemptID: PrimaryWorkflowAttemptID,
    phase: HerdrAgentQueryPhase,
    result: HerdrAgentQueryResult
  )
  case herdrAgentStartCompleted(HerdrAgentStartResult)
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
  case recognition(RecognitionEffect)
  case presentMenu(MenuPresentation)
  case openRecognitionDiagnostics(RecognitionDiagnosticsSession)
  case closeRecognitionDiagnostics
  case presentRecognitionDiagnosticsFrame(RecognitionDiagnosticsFrame)
  case clearRecognitionEvidence
  case presentDomainExpansionCandidateProgress(DomainExpansionCandidateProgress?)
  case presentDomainExpansionHUD(DomainExpansionHUDPresentationEffect)
  case loadWorkflowConfiguration
  case resolveGhostty
  case launchGhostty(at: String)
  case ensureDefaultHerdrSession
  case queryHerdrAgents(
    attemptID: PrimaryWorkflowAttemptID,
    phase: HerdrAgentQueryPhase
  )
  case startPiAgent(workspacePath: String, command: [String])
  case primaryWorkflowPiAgentPreserved
  case primaryWorkflowPiAgentStarted(PrimaryWorkflowContext)
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

  private enum RecognitionDiagnosticsMonitoringIntent {
    case active
    case paused
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
    case checkingForPiAgent(PrimaryWorkflowAttemptID)
    case loadingConfiguration(PrimaryWorkflowAttemptID)
    case resolvingGhostty(PrimaryWorkflowAttemptID, WorkflowConfiguration)
    case launchingGhostty(PrimaryWorkflowAttemptID, WorkflowConfiguration)
    case ensuringDefaultHerdrSession(PrimaryWorkflowAttemptID, WorkflowConfiguration)
    case recheckingForPiAgent(PrimaryWorkflowAttemptID, PrimaryWorkflowContext)
    case startingPiAgent(PrimaryWorkflowAttemptID, PrimaryWorkflowContext)
  }

  private enum DomainExpansionTriggerState {
    case armed
    case locked(triggeredAt: TimeInterval, absenceSince: TimeInterval?)
  }

  private enum PrimaryWorkflowOutcome {
    case succeeded
    case failed(PrimaryWorkflowFailure)
  }

  private enum DomainExpansionHUDState {
    case idle
    case animating(PrimaryWorkflowOutcome?)
    case waitingForWorkflow
    case showingError
  }

  private var state: State = .awaitingLaunch
  private var primaryWorkflowState: PrimaryWorkflowState = .idle
  private var primaryWorkflowAttemptSequence: PrimaryWorkflowAttemptID = 0
  private var domainExpansionHUDState: DomainExpansionHUDState = .idle
  private var monitoringPoseDatasetState: MonitoringPoseDatasetState = .idle
  private var validatedTrainingInput: PoseDatasetTrainingInput?
  private var targetFrameRate: RecognitionFrameRate = .defaultValue
  private var recognitionLifecycleSequence: UInt64 = 0
  private var currentRecognitionLifecycleID: RecognitionLifecycleID?
  private var currentCameraLifecycleID: RecognitionLifecycleID?
  private var selectedCaptureFramesPerSecond: Double?
  private var inFlightRecognitionFrame: RecognitionFrameReference?
  private var pendingRecognitionFrame: RecognitionFrameReference?
  private var recognitionCompletionTimes: [TimeInterval] = []
  private var completedRecognitionFramesPerSecond: Double = 0
  private var recognitionTime: TimeInterval = 0
  private let domainExpansionPolicy = DomainExpansionRecognitionPolicy.standard
  private var domainExpansionEvidence: [Bool] = []
  private var domainExpansionCandidateProgress: DomainExpansionCandidateProgress?
  private var domainExpansionTriggerState: DomainExpansionTriggerState = .armed
  private var recognitionDiagnosticsMonitoringIntent: RecognitionDiagnosticsMonitoringIntent?
  private var recognitionDiagnosticsEvidence: [Bool] = []

  public init() {}

  public func handle(_ event: AppEvent) -> Effects {
    if let effects = handleDomainExpansionHUD(event) {
      return effects
    }
    if let effects = handleMonitoringPoseDataset(event) {
      return effects
    }

    switch (state, event) {
    case (.monitoring(.active), .recognitionDiagnosticsRequested)
    where recognitionDiagnosticsMonitoringIntent == nil:
      recognitionDiagnosticsMonitoringIntent = .active
      recognitionDiagnosticsEvidence.removeAll()
      domainExpansionEvidence.removeAll()
      let progressEffects = updateDomainExpansionCandidateProgress(nil)
      return progressEffects + [
        .openRecognitionDiagnostics(
          RecognitionDiagnosticsSession(
            policy: domainExpansionPolicy,
            targetFrameRate: targetFrameRate,
            captureFramesPerSecond: selectedCaptureFramesPerSecond
          )
        )
      ]

    case (.monitoring(.paused), .recognitionDiagnosticsRequested)
    where recognitionDiagnosticsMonitoringIntent == nil:
      recognitionDiagnosticsMonitoringIntent = .paused
      recognitionDiagnosticsEvidence.removeAll()
      state = .monitoring(.awaitingAuthorization)
      return [
        .openRecognitionDiagnostics(
          RecognitionDiagnosticsSession(
            policy: domainExpansionPolicy,
            targetFrameRate: targetFrameRate,
            captureFramesPerSecond: nil
          )
        ),
        .camera(.requestAuthorization),
      ]

    case (_, .recognitionDiagnosticsClosed)
    where recognitionDiagnosticsMonitoringIntent == .paused:
      return closePausedMonitoringDiagnostics()

    case (_, .recognitionDiagnosticsClosed)
    where recognitionDiagnosticsMonitoringIntent == .active:
      recognitionDiagnosticsMonitoringIntent = nil
      recognitionDiagnosticsEvidence.removeAll()
      inFlightRecognitionFrame = nil
      pendingRecognitionFrame = nil
      return [.clearRecognitionEvidence, .closeRecognitionDiagnostics]

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
      return [.camera(nextStartBuiltInCameraEffect())]

    case (
      .monitoring(.awaitingAuthorization),
      .camera(.authorizationChanged(.notDetermined))
    ):
      return []

    case (.monitoring(.active), .camera(.authorizationChanged(.denied))),
      (.monitoring(.startingCapture), .camera(.authorizationChanged(.denied))),
      (.monitoring(.interrupted), .camera(.authorizationChanged(.denied))),
      (.monitoring(.rebuildingCapture), .camera(.authorizationChanged(.denied))):
      return releaseCameraBecauseUnavailable(.authorizationDenied)

    case (.monitoring(.active), .camera(.authorizationChanged(.restricted))),
      (.monitoring(.startingCapture), .camera(.authorizationChanged(.restricted))),
      (.monitoring(.interrupted), .camera(.authorizationChanged(.restricted))),
      (.monitoring(.rebuildingCapture), .camera(.authorizationChanged(.restricted))):
      return releaseCameraBecauseUnavailable(.authorizationRestricted)

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

    case (_, .camera(.recognitionFrameRateSelected(let selection))):
      guard
        isRecognitionCaptureState,
        selection.lifecycleID == currentRecognitionLifecycleID,
        selection.targetFrameRate == targetFrameRate,
        selection.actualFramesPerSecond > 0,
        selection.actualFramesPerSecond <= Double(targetFrameRate.rawValue) + 0.001
      else { return [] }
      selectedCaptureFramesPerSecond = selection.actualFramesPerSecond
      return []

    case (
      _,
      .camera(
        .captureStartCompleted(
          lifecycleID: let lifecycleID,
          result: let result
        )
      )
    ):
      return handleCaptureStartCompletion(
        lifecycleID: lifecycleID,
        result: result
      )

    case (_, .recognitionClockRead(let time)):
      guard time.isFinite, time >= 0 else { return [] }
      recognitionTime = time
      return []

    case (_, .recognitionFrameCaptured(let frame)):
      return handleCapturedRecognitionFrame(frame)

    case (_, .recognitionFrameCompleted(let completion)):
      return handleCompletedRecognitionFrame(completion)

    case (
      .monitoring(.active),
      .recognitionFrameRateRequested(let requestedFrameRate)
    ):
      guard requestedFrameRate != targetFrameRate else { return [] }
      targetFrameRate = requestedFrameRate
      let resetEffects = resetRecognitionPipelineEffects()
      return resetEffects + [.camera(nextUpdateRecognitionFrameRateEffect())]

    case (
      _,
      .camera(.captureInterrupted(lifecycleID: let lifecycleID))
    ):
      return handleCaptureInterruption(lifecycleID: lifecycleID)

    case (
      .monitoring(.interrupted),
      .camera(.captureInterruptionEnded(lifecycleID: let lifecycleID))
    ) where lifecycleID == currentCameraLifecycleID:
      state = .monitoring(.startingCapture)
      return [.camera(nextStartBuiltInCameraEffect())]

    case (.monitoring(.active), .camera(.cameraSwitchDetected)),
      (.monitoring(.startingCapture), .camera(.cameraSwitchDetected)),
      (.monitoring(.interrupted), .camera(.cameraSwitchDetected)):
      state = .monitoring(.rebuildingCapture)
      var effects =
        resetRecognitionPipelineEffects() + [
          .camera(nextRebuildBuiltInCameraEffect())
        ]
      if recognitionDiagnosticsMonitoringIntent != .paused {
        effects.append(.presentMenu(.captureInterrupted))
      }
      return effects

    case (.monitoring(.paused), .camera(.cameraSwitchDetected)),
      (.monitoring(.awaitingAuthorization), .camera(.cameraSwitchDetected)),
      (.monitoring(.unavailable), .camera(.cameraSwitchDetected)):
      return resetRecognitionPipelineEffects()

    case (.monitoring(.active), .camera(.systemWillSleep)),
      (.monitoring(.startingCapture), .camera(.systemWillSleep)),
      (.monitoring(.interrupted), .camera(.systemWillSleep)),
      (.monitoring(.rebuildingCapture), .camera(.systemWillSleep)):
      state = .monitoring(
        .releasing(.sleeping(.startCapture, wakeReceived: false))
      )
      var effects =
        resetRecognitionPipelineEffects() + [
          .camera(.stopAndReleaseCamera)
        ]
      if recognitionDiagnosticsMonitoringIntent != .paused {
        effects.append(.presentMenu(.captureInterrupted))
      }
      return effects

    case (.monitoring(.paused), .camera(.systemWillSleep)):
      state = .monitoring(.sleeping(.remainPaused))
      return resetRecognitionPipelineEffects()

    case (.monitoring(.awaitingAuthorization), .camera(.systemWillSleep)),
      (.monitoring(.unavailable), .camera(.systemWillSleep)):
      state = .monitoring(.sleeping(.requestAuthorization))
      return resetRecognitionPipelineEffects()

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
      return resetRecognitionPipelineEffects() + [
        .presentMenu(.pausedMonitoring)
      ]

    case (.monitoring(.active), .pauseMonitoringRequested),
      (.monitoring(.startingCapture), .pauseMonitoringRequested),
      (.monitoring(.rebuildingCapture), .pauseMonitoringRequested):
      state = .monitoring(.releasing(.paused))
      return resetRecognitionPipelineEffects() + [
        .camera(.stopAndReleaseCamera)
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
      return resetRecognitionPipelineEffects() + [
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
      guard
        recognitionDiagnosticsMonitoringIntent == nil,
        let input = validatedTrainingInput
      else { return [] }
      let context = RecognizerTrainingContext(
        input: input,
        priorState: .activeMonitoring
      )
      state = .suspendingRecognizerTraining(context)
      return [.presentRecognizerTraining(.preparing)]
        + resetRecognitionPipelineEffects()
        + [.camera(.stopAndReleaseCamera)]

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
      return endRecognitionDiagnosticsSession()
        + resetRecognitionPipelineEffects()
        + [.camera(.stopAndReleaseCamera)]

    case (.monitoring(.releasing(.paused)), .quitRequested),
      (.monitoring(.releasing(.sleeping)), .quitRequested),
      (.monitoring(.releasing(.unavailable)), .quitRequested):
      state = .monitoring(.releasing(.terminated))
      primaryWorkflowState = .idle
      return endRecognitionDiagnosticsSession()

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
      return endRecognitionDiagnosticsSession() + [.terminateApplication]

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
      effects =
        resetRecognitionPipelineEffects() + [
          .presentRecognizerTraining(.succeeded)
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

  private func releaseCameraBecauseUnavailable(
    _ reason: CameraUnavailableReason
  ) -> Effects {
    state = .monitoring(.releasing(.unavailable(reason)))
    return resetRecognitionPipelineEffects() + [
      .camera(.stopAndReleaseCamera),
      .presentMenu(.cameraUnavailable(reason)),
    ]
  }

  private func resumeAfterSleep(_ action: WakeAction) -> Effects {
    switch action {
    case .startCapture:
      state = .monitoring(.startingCapture)
      return [.camera(nextStartBuiltInCameraEffect())]
    case .requestAuthorization:
      state = .monitoring(.awaitingAuthorization)
      if recognitionDiagnosticsMonitoringIntent == .paused {
        return [.camera(.requestAuthorization)]
      }
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

  private func nextStartBuiltInCameraEffect() -> CameraEffect {
    .startBuiltInCamera(
      targetFrameRate: targetFrameRate,
      lifecycleID: beginRecognitionLifecycle()
    )
  }

  private func nextUpdateRecognitionFrameRateEffect() -> CameraEffect {
    .updateRecognitionFrameRate(
      targetFrameRate: targetFrameRate,
      lifecycleID: beginRecognitionLifecycle()
    )
  }

  private func nextRebuildBuiltInCameraEffect() -> CameraEffect {
    .rebuildBuiltInCamera(
      targetFrameRate: targetFrameRate,
      lifecycleID: beginRecognitionLifecycle()
    )
  }

  private func beginRecognitionLifecycle() -> RecognitionLifecycleID {
    resetRecognitionPipelineState()
    recognitionLifecycleSequence += 1
    let lifecycleID = RecognitionLifecycleID(
      rawValue: recognitionLifecycleSequence
    )
    currentRecognitionLifecycleID = lifecycleID
    currentCameraLifecycleID = lifecycleID
    return lifecycleID
  }

  private func resetRecognitionPipelineEffects() -> Effects {
    let progressEffects = clearDomainExpansionEvidence()
    resetRecognitionFrameProcessingState()
    return [.clearRecognitionEvidence] + progressEffects
  }

  private func resetRecognitionPipelineState() {
    resetRecognitionFrameProcessingState()
    _ = clearDomainExpansionEvidence()
  }

  private func resetRecognitionFrameProcessingState() {
    currentRecognitionLifecycleID = nil
    selectedCaptureFramesPerSecond = nil
    inFlightRecognitionFrame = nil
    pendingRecognitionFrame = nil
    recognitionCompletionTimes.removeAll()
    completedRecognitionFramesPerSecond = 0
  }

  private func clearDomainExpansionEvidence() -> Effects {
    domainExpansionEvidence.removeAll()
    if case .locked(let triggeredAt, _) = domainExpansionTriggerState {
      domainExpansionTriggerState = .locked(
        triggeredAt: triggeredAt,
        absenceSince: nil
      )
    }
    return updateDomainExpansionCandidateProgress(nil)
  }

  private var isRecognitionCaptureState: Bool {
    switch state {
    case .monitoring(.startingCapture),
      .monitoring(.active),
      .monitoring(.rebuildingCapture):
      true
    default:
      false
    }
  }

  private func handleCaptureInterruption(
    lifecycleID: RecognitionLifecycleID
  ) -> Effects {
    guard lifecycleID == currentCameraLifecycleID else { return [] }
    switch state {
    case .monitoring(.active),
      .monitoring(.startingCapture),
      .monitoring(.rebuildingCapture):
      state = .monitoring(.interrupted)
      var effects =
        resetRecognitionPipelineEffects() + [
          .camera(.stopCapture)
        ]
      if recognitionDiagnosticsMonitoringIntent != .paused {
        effects.append(.presentMenu(.captureInterrupted))
      }
      return effects
    default:
      return []
    }
  }

  private func handleCaptureStartCompletion(
    lifecycleID: RecognitionLifecycleID,
    result: CameraCaptureStartResult
  ) -> Effects {
    guard lifecycleID == currentCameraLifecycleID else { return [] }

    switch (state, result) {
    case (.monitoring(.startingCapture), .succeeded),
      (.monitoring(.rebuildingCapture), .succeeded):
      state = .monitoring(.active)
      if recognitionDiagnosticsMonitoringIntent == .paused {
        return []
      }
      return [.presentMenu(.activeMonitoring)]
    case (.monitoring(.active), .failed(let failure)):
      return releaseCameraBecauseUnavailable(.capture(failure))
    case (.monitoring(.startingCapture), .failed(let failure)),
      (.monitoring(.rebuildingCapture), .failed(let failure)):
      let reason = CameraUnavailableReason.capture(failure)
      state = .monitoring(.unavailable(reason))
      return resetRecognitionPipelineEffects() + [
        .presentMenu(.cameraUnavailable(reason))
      ]
    default:
      return []
    }
  }

  private func handleCapturedRecognitionFrame(
    _ frame: RecognitionFrameReference
  ) -> Effects {
    guard
      case .monitoring(.active) = state,
      frame.lifecycleID == currentRecognitionLifecycleID
    else {
      return [.recognition(.discardFrame(frame))]
    }

    guard let inFlightRecognitionFrame else {
      self.inFlightRecognitionFrame = frame
      return [.recognition(.analyzeFrame(frame))]
    }

    guard frame.sequenceNumber > inFlightRecognitionFrame.sequenceNumber else {
      return [.recognition(.discardFrame(frame))]
    }

    guard let pendingRecognitionFrame else {
      self.pendingRecognitionFrame = frame
      return []
    }

    guard frame.sequenceNumber > pendingRecognitionFrame.sequenceNumber else {
      return [.recognition(.discardFrame(frame))]
    }

    self.pendingRecognitionFrame = frame
    return [.recognition(.discardFrame(pendingRecognitionFrame))]
  }

  private func handleCompletedRecognitionFrame(
    _ completion: RecognitionFrameCompletion
  ) -> Effects {
    guard
      case .monitoring(.active) = state,
      completion.frame.lifecycleID == currentRecognitionLifecycleID,
      completion.frame == inFlightRecognitionFrame
    else { return [] }

    inFlightRecognitionFrame = nil
    let completionTime = recognitionTime
    recordRecognitionCompletion(at: completionTime)
    var effects: Effects
    if recognitionDiagnosticsMonitoringIntent != nil {
      var topClassification: PersonalRecognizerClassification?
      var isPoseMatch: Bool?
      if case .classified(let classifications) = completion.personalRecognizerResult,
        let top = domainExpansionPolicy.topClassification(in: classifications)
      {
        topClassification = top
        let poseMatch = domainExpansionPolicy.isPoseMatch(top)
        isPoseMatch = poseMatch
        recognitionDiagnosticsEvidence.append(poseMatch)
        if recognitionDiagnosticsEvidence.count > domainExpansionPolicy.evidenceWindowSize {
          recognitionDiagnosticsEvidence.removeFirst(
            recognitionDiagnosticsEvidence.count - domainExpansionPolicy.evidenceWindowSize
          )
        }
      }
      effects = [
        .presentRecognitionDiagnosticsFrame(
          RecognitionDiagnosticsFrame(
            frame: completion.frame,
            policy: domainExpansionPolicy,
            topClassification: topClassification,
            isPoseMatch: isPoseMatch,
            poseMatchCount: recognitionDiagnosticsEvidence.lazy.filter { $0 }.count,
            targetFrameRate: targetFrameRate,
            captureFramesPerSecond: selectedCaptureFramesPerSecond,
            completedRecognitionFramesPerSecond: completedRecognitionFramesPerSecond
          )
        )
      ]
    } else {
      effects = []
      switch completion.personalRecognizerResult {
      case .classified(let classifications):
        effects.append(
          contentsOf: handleDomainExpansionClassifications(
            classifications,
            at: completionTime
          )
        )
      case .noHandDetected:
        effects.append(contentsOf: handleDomainExpansionAbsence(at: completionTime))
      case .failed:
        interruptDomainExpansionAbsence()
      }
    }

    if let pendingRecognitionFrame {
      self.pendingRecognitionFrame = nil
      inFlightRecognitionFrame = pendingRecognitionFrame
      effects.append(.recognition(.analyzeFrame(pendingRecognitionFrame)))
    }
    return effects
  }

  private func endRecognitionDiagnosticsSession() -> Effects {
    guard recognitionDiagnosticsMonitoringIntent != nil else { return [] }
    recognitionDiagnosticsMonitoringIntent = nil
    recognitionDiagnosticsEvidence.removeAll()
    return [.closeRecognitionDiagnostics]
  }

  private func closePausedMonitoringDiagnostics() -> Effects {
    recognitionDiagnosticsMonitoringIntent = nil
    recognitionDiagnosticsEvidence.removeAll()
    let closeEffects: Effects = [.closeRecognitionDiagnostics]

    switch state {
    case .monitoring(.active),
      .monitoring(.startingCapture),
      .monitoring(.rebuildingCapture):
      state = .monitoring(.releasing(.paused))
      return closeEffects + resetRecognitionPipelineEffects() + [
        .camera(.stopAndReleaseCamera)
      ]
    case .monitoring(.interrupted):
      state = .monitoring(.releasing(.paused))
      return closeEffects + [.camera(.stopAndReleaseCamera)]
    case .monitoring(.awaitingAuthorization),
      .monitoring(.unavailable):
      state = .monitoring(.paused)
      return closeEffects + [.presentMenu(.pausedMonitoring)]
    case .monitoring(.releasing(.sleeping(_, let wakeReceived))):
      state = .monitoring(
        .releasing(.sleeping(.remainPaused, wakeReceived: wakeReceived))
      )
      return closeEffects
    case .monitoring(.sleeping):
      state = .monitoring(.sleeping(.remainPaused))
      return closeEffects
    case .monitoring(.releasing(.unavailable)):
      state = .monitoring(.releasing(.paused))
      return closeEffects
    default:
      return closeEffects
    }
  }

  private func recordRecognitionCompletion(at completionTime: TimeInterval) {
    if let previousTime = recognitionCompletionTimes.last,
      completionTime < previousTime
    {
      recognitionCompletionTimes.removeAll()
    }

    recognitionCompletionTimes.append(completionTime)
    let cutoff = completionTime - 1
    recognitionCompletionTimes.removeAll { $0 < cutoff }

    guard
      let first = recognitionCompletionTimes.first,
      let last = recognitionCompletionTimes.last,
      recognitionCompletionTimes.count > 1,
      last > first
    else {
      completedRecognitionFramesPerSecond = 0
      return
    }
    completedRecognitionFramesPerSecond =
      Double(recognitionCompletionTimes.count - 1) / (last - first)
  }

  private func handleDomainExpansionClassifications(
    _ classifications: [PersonalRecognizerClassification],
    at time: TimeInterval
  ) -> Effects {
    guard
      let topClassification = domainExpansionPolicy.topClassification(
        in: classifications
      )
    else {
      interruptDomainExpansionAbsence()
      return []
    }
    let isPoseMatch = domainExpansionPolicy.isPoseMatch(topClassification)

    switch domainExpansionTriggerState {
    case .armed:
      domainExpansionEvidence.append(isPoseMatch)
      if domainExpansionEvidence.count > domainExpansionPolicy.evidenceWindowSize {
        domainExpansionEvidence.removeFirst(
          domainExpansionEvidence.count - domainExpansionPolicy.evidenceWindowSize
        )
      }
      let poseMatchCount = domainExpansionEvidence.lazy.filter { $0 }.count
      guard poseMatchCount >= domainExpansionPolicy.requiredPoseMatchCount else {
        let progress =
          poseMatchCount > 0
          ? DomainExpansionCandidateProgress(poseMatchCount: poseMatchCount)
          : nil
        return updateDomainExpansionCandidateProgress(progress)
      }
      guard canStartPrimaryWorkflow else {
        return updateDomainExpansionCandidateProgress(
          DomainExpansionCandidateProgress(
            poseMatchCount: domainExpansionPolicy.requiredPoseMatchCount - 1
          )
        )
      }

      domainExpansionEvidence.removeAll()
      domainExpansionTriggerState = .locked(
        triggeredAt: time,
        absenceSince: nil
      )
      domainExpansionHUDState = .animating(nil)
      return updateDomainExpansionCandidateProgress(nil)
        + [.presentDomainExpansionHUD(.showDomainExpansion)]
        + startPrimaryWorkflow()

    case .locked(let triggeredAt, _):
      if isPoseMatch {
        domainExpansionTriggerState = .locked(
          triggeredAt: triggeredAt,
          absenceSince: nil
        )
        return []
      }
      return handleDomainExpansionAbsence(at: time)
    }
  }

  private func handleDomainExpansionAbsence(
    at time: TimeInterval
  ) -> Effects {
    guard
      case .locked(let triggeredAt, let absenceSince) =
        domainExpansionTriggerState
    else {
      return []
    }
    guard time >= triggeredAt else {
      domainExpansionTriggerState = .locked(
        triggeredAt: time,
        absenceSince: time
      )
      return []
    }
    guard let absenceSince, time >= absenceSince else {
      domainExpansionTriggerState = .locked(
        triggeredAt: triggeredAt,
        absenceSince: time
      )
      return []
    }
    guard time - absenceSince >= 1, time - triggeredAt >= 5 else {
      return []
    }
    domainExpansionTriggerState = .armed
    domainExpansionEvidence.removeAll()
    return []
  }

  private func interruptDomainExpansionAbsence() {
    guard case .locked(let triggeredAt, _) = domainExpansionTriggerState else {
      return
    }
    domainExpansionTriggerState = .locked(
      triggeredAt: triggeredAt,
      absenceSince: nil
    )
  }

  private func updateDomainExpansionCandidateProgress(
    _ progress: DomainExpansionCandidateProgress?
  ) -> Effects {
    guard progress != domainExpansionCandidateProgress else { return [] }
    domainExpansionCandidateProgress = progress
    return [.presentDomainExpansionCandidateProgress(progress)]
  }

  private var canStartPrimaryWorkflow: Bool {
    if case .idle = primaryWorkflowState {
      return true
    }
    return false
  }

  private func startPrimaryWorkflow() -> Effects {
    guard canStartPrimaryWorkflow else { return [] }
    primaryWorkflowAttemptSequence &+= 1
    let attemptID = primaryWorkflowAttemptSequence
    primaryWorkflowState = .checkingForPiAgent(attemptID)
    return [.queryHerdrAgents(attemptID: attemptID, phase: .initial)]
  }

  private func handleDomainExpansionHUD(_ event: AppEvent) -> Effects? {
    guard case .domainExpansionHUD(let presentationEvent) = event else {
      return nil
    }

    switch (domainExpansionHUDState, presentationEvent) {
    case (.animating(nil), .animationCompleted):
      domainExpansionHUDState = .waitingForWorkflow
      return []
    case (.animating(.some(.succeeded)), .animationCompleted):
      domainExpansionHUDState = .idle
      return [.presentDomainExpansionHUD(.fade)]
    case (.animating(.some(.failed(let failure))), .animationCompleted):
      domainExpansionHUDState = .showingError
      return [.presentDomainExpansionHUD(.showError(failure))]
    case (.showingError, .dismissed):
      domainExpansionHUDState = .idle
      return [.presentDomainExpansionHUD(.dismiss)]
    case (_, .presentationFailed):
      domainExpansionHUDState = .idle
      return []
    default:
      return []
    }
  }

  private func recordDomainExpansionHUDOutcome(
    _ outcome: PrimaryWorkflowOutcome
  ) -> Effects {
    switch domainExpansionHUDState {
    case .animating:
      domainExpansionHUDState = .animating(outcome)
      return []
    case .waitingForWorkflow:
      switch outcome {
      case .succeeded:
        domainExpansionHUDState = .idle
        return [.presentDomainExpansionHUD(.fade)]
      case .failed(let failure):
        domainExpansionHUDState = .showingError
        return [.presentDomainExpansionHUD(.showError(failure))]
      }
    case .idle, .showingError:
      return []
    }
  }

  private func failPrimaryWorkflow(_ failure: PrimaryWorkflowFailure) -> Effects {
    primaryWorkflowState = .idle
    return [.primaryWorkflowFailed(failure)]
      + recordDomainExpansionHUDOutcome(.failed(failure))
  }

  private func handlePrimaryWorkflow(_ event: AppEvent) -> Effects {
    switch (primaryWorkflowState, event) {
    case (.idle, .primaryWorkflowRequested):
      guard case .monitoring(.active) = state else { return [] }
      return startPrimaryWorkflow()

    case (
      .checkingForPiAgent(let activeAttemptID),
      .herdrAgentQueryCompleted(
        attemptID: let completionAttemptID,
        phase: .initial,
        result: .agents(let agents)
      )
    ) where activeAttemptID == completionAttemptID:
      if Self.containsPiAgent(in: agents) {
        primaryWorkflowState = .idle
        return [.primaryWorkflowPiAgentPreserved]
          + recordDomainExpansionHUDOutcome(.succeeded)
      }
      primaryWorkflowState = .loadingConfiguration(activeAttemptID)
      return [.loadWorkflowConfiguration]

    case (
      .checkingForPiAgent(let activeAttemptID),
      .herdrAgentQueryCompleted(
        attemptID: let completionAttemptID,
        phase: .initial,
        result: .herdrUnavailable
      )
    ) where activeAttemptID == completionAttemptID:
      primaryWorkflowState = .loadingConfiguration(activeAttemptID)
      return [.loadWorkflowConfiguration]

    case (
      .checkingForPiAgent(let activeAttemptID),
      .herdrAgentQueryCompleted(
        attemptID: let completionAttemptID,
        phase: .initial,
        result: .malformedOutput
      )
    ) where activeAttemptID == completionAttemptID:
      return failPrimaryWorkflow(.malformedHerdrOutput)

    case (
      .loadingConfiguration(let attemptID),
      .workflowConfigurationLoadCompleted(.loaded(let configuration))
    ):
      primaryWorkflowState = .resolvingGhostty(attemptID, configuration)
      return [.resolveGhostty]

    case (
      .loadingConfiguration,
      .workflowConfigurationLoadCompleted(.failed(let failure))
    ):
      return failPrimaryWorkflow(.configuration(failure))

    case (
      .resolvingGhostty(let attemptID, let configuration),
      .ghosttyResolutionCompleted(.found(let ghostty))
    ):
      if let versionFailure = GhosttyVersionPolicy.failure(for: ghostty.version) {
        return failPrimaryWorkflow(versionFailure)
      }

      if ghostty.isRunning {
        primaryWorkflowState = .ensuringDefaultHerdrSession(attemptID, configuration)
        return [.ensureDefaultHerdrSession]
      }

      primaryWorkflowState = .launchingGhostty(attemptID, configuration)
      return [.launchGhostty(at: ghostty.path)]

    case (.resolvingGhostty, .ghosttyResolutionCompleted(.notInstalled)):
      return failPrimaryWorkflow(.ghosttyNotInstalled)

    case (
      .launchingGhostty(let attemptID, let configuration),
      .ghosttyLaunchCompleted(.succeeded)
    ):
      primaryWorkflowState = .ensuringDefaultHerdrSession(attemptID, configuration)
      return [.ensureDefaultHerdrSession]

    case (.launchingGhostty, .ghosttyLaunchCompleted(.failed)):
      return failPrimaryWorkflow(.ghosttyLaunchFailed)

    case (
      .ensuringDefaultHerdrSession(let attemptID, let configuration),
      .defaultHerdrSessionEnsureCompleted(.ready(let session))
    ):
      primaryWorkflowState = .recheckingForPiAgent(
        attemptID,
        PrimaryWorkflowContext(
          configuration: configuration,
          defaultHerdrSession: session
        )
      )
      return [
        .queryHerdrAgents(attemptID: attemptID, phase: .postBootstrap)
      ]

    case (
      .recheckingForPiAgent(let activeAttemptID, let context),
      .herdrAgentQueryCompleted(
        attemptID: let completionAttemptID,
        phase: .postBootstrap,
        result: .agents(let agents)
      )
    ) where activeAttemptID == completionAttemptID:
      if Self.containsPiAgent(in: agents) {
        primaryWorkflowState = .idle
        return [.primaryWorkflowPiAgentPreserved]
          + recordDomainExpansionHUDOutcome(.succeeded)
      }
      primaryWorkflowState = .startingPiAgent(activeAttemptID, context)
      return [
        .startPiAgent(
          workspacePath: context.configuration.workspacePath,
          command: context.configuration.piCommand
        )
      ]

    case (
      .recheckingForPiAgent(let activeAttemptID, _),
      .herdrAgentQueryCompleted(
        attemptID: let completionAttemptID,
        phase: .postBootstrap,
        result: .herdrUnavailable
      )
    ) where activeAttemptID == completionAttemptID:
      return failPrimaryWorkflow(.herdrUnavailable)

    case (
      .recheckingForPiAgent(let activeAttemptID, _),
      .herdrAgentQueryCompleted(
        attemptID: let completionAttemptID,
        phase: .postBootstrap,
        result: .malformedOutput
      )
    ) where activeAttemptID == completionAttemptID:
      return failPrimaryWorkflow(.malformedHerdrOutput)

    case (
      .startingPiAgent(_, let context),
      .herdrAgentStartCompleted(.succeeded)
    ):
      primaryWorkflowState = .idle
      return [.primaryWorkflowPiAgentStarted(context)]
        + recordDomainExpansionHUDOutcome(.succeeded)

    case (.startingPiAgent, .herdrAgentStartCompleted(.failed)):
      return failPrimaryWorkflow(.piStartFailed)

    case (
      .ensuringDefaultHerdrSession,
      .defaultHerdrSessionEnsureCompleted(.automationFailed(let failure))
    ):
      switch failure {
      case .denied:
        return failPrimaryWorkflow(.ghosttyAutomationDenied)
      case .unavailable:
        return failPrimaryWorkflow(.ghosttyAutomationUnavailable)
      }

    case (.ensuringDefaultHerdrSession, .defaultHerdrSessionEnsureCompleted(.herdrUnavailable)):
      return failPrimaryWorkflow(.herdrUnavailable)

    default:
      return []
    }
  }

  private static func containsPiAgent(in agents: [HerdrAgent]) -> Bool {
    agents.contains { $0.agent == "pi" }
  }
}
