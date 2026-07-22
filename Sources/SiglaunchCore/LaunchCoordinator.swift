public enum PersonalRecognizerAvailability: Equatable, Sendable {
  case available
  case missing
}

public enum MenuBarApplicationConfigurationResult: Equatable, Sendable {
  case succeeded
  case failed
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
  case menuPresented(MenuPresentation)
  case primaryWorkflowRequested
  case workflowConfigurationLoadCompleted(WorkflowConfigurationLoadResult)
  case ghosttyResolutionCompleted(GhosttyResolutionResult)
  case ghosttyLaunchCompleted(GhosttyLaunchResult)
  case defaultHerdrSessionEnsureCompleted(DefaultHerdrSessionEnsureResult)
  case quitRequested
}

public enum MenuPresentation: Equatable, Sendable {
  case personalRecognizerReady
  case setupRequired
}

public enum AppEffect: Equatable, Sendable {
  case configureMenuBarApplication
  case checkPersonalRecognizer
  case presentMenu(MenuPresentation)
  case loadWorkflowConfiguration
  case resolveGhostty
  case launchGhostty(at: String)
  case ensureDefaultHerdrSession
  case primaryWorkflowGhosttyReady(PrimaryWorkflowContext)
  case primaryWorkflowFailed(PrimaryWorkflowFailure)
  case terminateApplication
}

public typealias Effects = [AppEffect]

public final class LaunchCoordinator {
  private enum State {
    case awaitingLaunch
    case configuringMenuBarApplication
    case checkingPersonalRecognizer
    case personalRecognizerAvailable
    case setupRequired
    case terminated
  }

  private enum PrimaryWorkflowState {
    case idle
    case loadingConfiguration
    case resolvingGhostty(WorkflowConfiguration)
    case launchingGhostty(WorkflowConfiguration)
    case ensuringDefaultHerdrSession(WorkflowConfiguration)
  }

  private var state: State = .awaitingLaunch
  private var primaryWorkflowState: PrimaryWorkflowState = .idle

  public init() {}

  public func handle(_ event: AppEvent) -> Effects {
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
      state = .personalRecognizerAvailable
      return [.presentMenu(.personalRecognizerReady)]

    case (.checkingPersonalRecognizer, .personalRecognizerChecked(.missing)):
      state = .setupRequired
      return [.presentMenu(.setupRequired)]

    case (.awaitingLaunch, .quitRequested),
      (.configuringMenuBarApplication, .quitRequested),
      (.checkingPersonalRecognizer, .quitRequested),
      (.personalRecognizerAvailable, .quitRequested),
      (.setupRequired, .quitRequested):
      state = .terminated
      primaryWorkflowState = .idle
      return [.terminateApplication]

    default:
      return handlePrimaryWorkflow(event)
    }
  }

  private func handlePrimaryWorkflow(_ event: AppEvent) -> Effects {
    switch (primaryWorkflowState, event) {
    case (.idle, .primaryWorkflowRequested):
      guard case .personalRecognizerAvailable = state else { return [] }
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
      primaryWorkflowState = .idle
      return [
        .primaryWorkflowGhosttyReady(
          PrimaryWorkflowContext(
            configuration: configuration,
            defaultHerdrSession: session
          )
        )
      ]

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

}
