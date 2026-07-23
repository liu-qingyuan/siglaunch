import Foundation
import SiglaunchCore
import XCTest

@testable import SiglaunchApp

@MainActor
final class GhosttyAppleScriptAdapterTests: XCTestCase {
  func testReusesHerdrBeforeLaunchingDirectlyInExistingGhosttyWindow() throws {
    let executablePath = "/tmp/Herdr Install/herdr"
    let source = try XCTUnwrap(
      GhosttyAppleScriptAdapter.source(
        herdrExecutablePath: executablePath,
        knownTerminalID: "terminal-id"
      )
    )
    let normalizedSource = source.lowercased()

    XCTAssertTrue(normalizedSource.contains("id of candidateterminal"))
    XCTAssertTrue(normalizedSource.contains("return {\"reused\", knownterminalid}"))
    XCTAssertTrue(normalizedSource.contains("name of candidateterminal"))
    XCTAssertTrue(normalizedSource.contains("terminalname starts with \"herdr\""))
    XCTAssertTrue(normalizedSource.contains("terminalname is \"👻\""))
    XCTAssertTrue(normalizedSource.contains("focus candidateterminal"))
    XCTAssertTrue(
      normalizedSource.contains(
        "set command of sessionconfiguration to \"\(executablePath.lowercased())\""
      )
    )
    XCTAssertTrue(
      normalizedSource.contains("set wait after command of sessionconfiguration to false")
    )
    XCTAssertTrue(
      normalizedSource.contains(
        "new tab in front window with configuration sessionconfiguration"
      )
    )
    XCTAssertTrue(normalizedSource.contains("new window with configuration sessionconfiguration"))
    XCTAssertTrue(normalizedSource.contains("return {\"pending\", createdterminalid}"))
    XCTAssertEqual(source.components(separatedBy: executablePath).count - 1, 1)

    let readinessSource = try XCTUnwrap(
      GhosttyAppleScriptAdapter.readinessSource(
        terminalID: "00000000-0000-0000-0000-000000000000"
      )
    ).lowercased()
    XCTAssertTrue(readinessSource.contains("id of candidateterminal"))
    XCTAssertTrue(readinessSource.contains("return {\"ready\", expectedterminalid}"))
    XCTAssertFalse(readinessSource.contains("name of candidateterminal"))

    let scripts = normalizedSource + readinessSource
    XCTAssertFalse(scripts.contains("environment variables"))
    XCTAssertFalse(scripts.contains("siglaunch_herdr_path"))
    XCTAssertFalse(scripts.contains("exec"))
    XCTAssertFalse(scripts.contains("input text"))
    XCTAssertFalse(scripts.contains("send key"))
    XCTAssertFalse(scripts.contains("keystroke"))
    XCTAssertFalse(scripts.contains("do shell script"))
  }

  func testHerdrResolverRequiresAnExecutableAbsolutePath() throws {
    let homeDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let binDirectory = homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
    try FileManager.default.createDirectory(
      at: binDirectory,
      withIntermediateDirectories: true
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: homeDirectory)
    }

    let executableURL = binDirectory.appendingPathComponent("herdr", isDirectory: false)
    try Data().write(to: executableURL)
    let resolver = HerdrExecutableResolver(
      environment: ["PATH": "relative/bin"],
      homeDirectory: homeDirectory
    )
    XCTAssertNil(resolver.resolve())

    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executableURL.path
    )
    XCTAssertEqual(resolver.resolve(), executableURL.path)
  }

  func testMapsAutomationPermissionAndAvailabilityFailuresSeparately() {
    XCTAssertEqual(
      GhosttyAppleScriptAdapter.automationFailure(
        from: [
          "NSAppleScriptErrorNumber": -1743,
          "NSAppleScriptErrorMessage": "Not authorized to send Apple events to Ghostty.",
        ]
      ),
      .denied
    )
    XCTAssertEqual(
      GhosttyAppleScriptAdapter.automationFailure(
        from: [
          "NSAppleScriptErrorNumber": -1743,
          "NSAppleScriptErrorMessage":
            "AppleScript is disabled by the macos-applescript configuration.",
        ]
      ),
      .unavailable
    )
    XCTAssertEqual(
      GhosttyAppleScriptAdapter.automationFailure(
        from: ["NSAppleScriptErrorNumber": -1708]
      ),
      .unavailable
    )
  }

  func testLiveGhosttyEnsuresDefaultHerdrSessionWhenOptedIn() async throws {
    guard ProcessInfo.processInfo.environment["SIGLAUNCH_RUN_GHOSTTY_SMOKE"] == "1" else {
      throw XCTSkip("Set SIGLAUNCH_RUN_GHOSTTY_SMOKE=1 to modify live Ghostty state.")
    }

    let platformAdapter = GhosttyPlatformAdapter()
    let resolution = platformAdapter.resolve()
    guard case .found(let ghostty) = resolution else {
      return XCTFail("Ghostty is not installed.")
    }

    let coordinator = makeCoordinatorResolvingGhostty()
    let resolutionEffects = coordinator.handle(.ghosttyResolutionCompleted(resolution))
    if resolutionEffects == [.launchGhostty(at: ghostty.path)] {
      let launchResult = await withCheckedContinuation { continuation in
        platformAdapter.launch(at: ghostty.path) { result in
          continuation.resume(returning: result)
        }
      }
      guard launchResult == .succeeded else {
        return XCTFail("Ghostty could not be launched.")
      }
    } else {
      guard resolutionEffects == [.ensureDefaultHerdrSession] else {
        return XCTFail("The installed Ghostty must satisfy the 1.3.0+ contract.")
      }
    }

    let sessionResult = await withCheckedContinuation { continuation in
      platformAdapter.ensureDefaultHerdrSession { result in
        continuation.resume(returning: result)
      }
    }
    guard case .ready = sessionResult else {
      return XCTFail("Ghostty AppleScript could not ensure the default Herdr Session.")
    }
  }

  private func makeCoordinatorResolvingGhostty() -> LaunchCoordinator {
    let coordinator = LaunchCoordinator()
    for event in [
      AppEvent.appLaunched,
      .menuBarApplicationConfigurationCompleted(.succeeded),
      .personalRecognizerChecked(.available),
      .camera(.authorizationChanged(.authorized)),
      .camera(
        .captureStartCompleted(
          lifecycleID: RecognitionLifecycleID(rawValue: 1),
          result: .succeeded
        )
      ),
      .menuPresented(.activeMonitoring),
      .primaryWorkflowRequested,
      .workflowConfigurationLoadCompleted(
        .loaded(
          WorkflowConfiguration(
            workspacePath: "/tmp/siglaunch-ghostty-smoke",
            piCommand: ["pi"]
          )
        )
      ),
    ] {
      _ = coordinator.handle(event)
    }
    return coordinator
  }
}
