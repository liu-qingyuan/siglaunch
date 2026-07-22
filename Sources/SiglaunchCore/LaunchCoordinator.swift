import Foundation

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
  case menuPresented(MenuPresentation)
  case primaryWorkflowRequested
  case workflowConfigurationLoadCompleted(WorkflowConfigurationLoadResult)
  case ghosttyResolutionCompleted(GhosttyResolutionResult)
  case ghosttyLaunchCompleted(GhosttyLaunchResult)
  case defaultHerdrSessionEnsureCompleted(DefaultHerdrSessionEnsureResult)
  case herdrAgentQueryCompleted(HerdrAgentQueryResult)
  case herdrAgentFocusCompleted(HerdrAgentFocusResult)
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
  case queryHerdrAgents
  case focusHerdrAgent(paneID: String)
  case primaryWorkflowNoMatchingAgent(PrimaryWorkflowContext)
  case primaryWorkflowLeadingPiAgentFocused(LeadingPiAgentContext)
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
    case queryingHerdrAgents(PrimaryWorkflowContext)
    case focusingHerdrAgent(PrimaryWorkflowContext, HerdrAgent)
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
