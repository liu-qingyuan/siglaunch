import SiglaunchCore
import XCTest

final class LaunchCoordinatorTests: XCTestCase {
  private typealias Step = (name: String, event: AppEvent, effects: Effects)

  func testLaunchWithoutPersonalRecognizerPresentsSetupRequired() {
    let coordinator = LaunchCoordinator()
    let steps: [Step] = [
      (
        "launch configures a menu-bar-only application",
        .appLaunched,
        [.configureMenuBarApplication]
      ),
      (
        "a duplicate launch does not repeat configuration",
        .appLaunched,
        []
      ),
      (
        "configuration completion checks for a Personal Recognizer",
        .menuBarApplicationConfigurationCompleted(.succeeded),
        [.checkPersonalRecognizer]
      ),
      (
        "a duplicate configuration result does not repeat the check",
        .menuBarApplicationConfigurationCompleted(.succeeded),
        []
      ),
      (
        "a missing Personal Recognizer presents Setup Required",
        .personalRecognizerChecked(.missing),
        [.presentMenu(.setupRequired)]
      ),
      (
        "menu presentation completion has no further effects",
        .menuPresented(.setupRequired),
        []
      ),
      (
        "a duplicate result does not repeat menu presentation",
        .personalRecognizerChecked(.missing),
        []
      ),
    ]

    assertEffects(steps, from: coordinator)
  }

  func testEveryMenuBarConfigurationResultContinuesRecognizerCheck() {
    let results: [MenuBarApplicationConfigurationResult] = [.succeeded, .failed]

    for result in results {
      let coordinator = makeCoordinator(after: [.appLaunched])
      XCTAssertEqual(
        coordinator.handle(.menuBarApplicationConfigurationCompleted(result)),
        [.checkPersonalRecognizer],
        "configuration result: \(result)"
      )
    }
  }

  func testAvailablePersonalRecognizerPresentsReadyWithoutClaimingMonitoring() {
    let coordinator = makeCoordinator(
      after: [
        .appLaunched,
        .menuBarApplicationConfigurationCompleted(.succeeded),
      ]
    )
    let steps: [Step] = [
      (
        "availability presents a truthful pre-monitoring status",
        .personalRecognizerChecked(.available),
        [.presentMenu(.personalRecognizerReady)]
      ),
      (
        "menu presentation completion has no further effects",
        .menuPresented(.personalRecognizerReady),
        []
      ),
      (
        "a stale missing result cannot replace availability",
        .personalRecognizerChecked(.missing),
        []
      ),
    ]

    assertEffects(steps, from: coordinator)
  }

  func testQuitTerminatesApplicationOnceFromEveryReachableMenuState() {
    let cases: [(name: String, priorEvents: [AppEvent])] = [
      ("configuring the menu-bar application", [.appLaunched]),
      (
        "checking Personal Recognizer",
        [
          .appLaunched,
          .menuBarApplicationConfigurationCompleted(.succeeded),
        ]
      ),
      (
        "Personal Recognizer ready",
        [
          .appLaunched,
          .menuBarApplicationConfigurationCompleted(.succeeded),
          .personalRecognizerChecked(.available),
          .menuPresented(.personalRecognizerReady),
        ]
      ),
      (
        "Setup Required",
        [
          .appLaunched,
          .menuBarApplicationConfigurationCompleted(.succeeded),
          .personalRecognizerChecked(.missing),
          .menuPresented(.setupRequired),
        ]
      ),
    ]

    for testCase in cases {
      let coordinator = makeCoordinator(after: testCase.priorEvents)
      XCTAssertEqual(
        coordinator.handle(.quitRequested),
        [.terminateApplication],
        testCase.name
      )
      XCTAssertEqual(
        coordinator.handle(.quitRequested),
        [],
        "\(testCase.name) should terminate only once"
      )
    }
  }

  private func assertEffects(_ steps: [Step], from coordinator: LaunchCoordinator) {
    for step in steps {
      XCTAssertEqual(coordinator.handle(step.event), step.effects, step.name)
    }
  }

  private func makeCoordinator(after events: [AppEvent]) -> LaunchCoordinator {
    let coordinator = LaunchCoordinator()
    for event in events {
      _ = coordinator.handle(event)
    }
    return coordinator
  }
}
