public enum PersonalRecognizerAvailability: Equatable, Sendable {
  case available
  case missing
}

public enum MenuBarApplicationConfigurationResult: Equatable, Sendable {
  case succeeded
  case failed
}

public enum AppEvent: Equatable, Sendable {
  case appLaunched
  case menuBarApplicationConfigurationCompleted(MenuBarApplicationConfigurationResult)
  case personalRecognizerChecked(PersonalRecognizerAvailability)
  case menuPresented(MenuPresentation)
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

  private var state: State = .awaitingLaunch

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
      return [.terminateApplication]

    default:
      return []
    }
  }
}
