import Foundation
import SiglaunchCore
import XCTest

@testable import SiglaunchApp

@MainActor
final class HerdrAgentAdapterTests: XCTestCase {
  func testQueryExecutesAgentListAndPreservesHerdrOrder() async {
    let output = #"""
      {
        "id": "cli:agent:list",
        "result": {
          "agents": [
            {
              "agent": "pi",
              "cwd": "/workspace/first",
              "foreground_cwd": null,
              "pane_id": "pane-first"
            },
            {
              "agent": "pi",
              "cwd": "/workspace/second",
              "foreground_cwd": "/workspace/foreground",
              "pane_id": "pane-second"
            }
          ],
          "type": "agent_list"
        }
      }
      """#
    let runner = StubHerdrCommandRunner(
      executions: [
        HerdrCommandExecution(
          terminationStatus: 0,
          standardOutput: Data(output.utf8)
        )
      ]
    )
    let adapter = HerdrAgentAdapter(
      executablePathProvider: { "/usr/local/bin/herdr" },
      commandRunner: runner
    )

    let result = await query(using: adapter)

    XCTAssertEqual(
      result,
      .agents([
        HerdrAgent(
          paneID: "pane-first",
          agent: "pi",
          cwd: "/workspace/first",
          foregroundCwd: nil
        ),
        HerdrAgent(
          paneID: "pane-second",
          agent: "pi",
          cwd: "/workspace/second",
          foregroundCwd: "/workspace/foreground"
        ),
      ])
    )
    let commands = await runner.observedCommands()
    XCTAssertEqual(
      commands,
      [
        HerdrCommand(
          executablePath: "/usr/local/bin/herdr",
          arguments: ["agent", "list"]
        )
      ]
    )
  }

  func testQueryRejectsMalformedHerdrOutputAndMalformedEntries() async {
    let malformedOutputs = [
      "not-json",
      #"{"result":{"agents":[{"agent":"pi","cwd":"/workspace","foreground_cwd":null}],"type":"agent_list"}}"#,
      #"{"result":{"agents":[{"agent":1,"cwd":"/workspace","foreground_cwd":null,"pane_id":"pane"}],"type":"agent_list"}}"#,
      #"{"result":{"agents":[{"agent":"pi","foreground_cwd":null,"pane_id":"pane"}],"type":"agent_list"}}"#,
      #"{"result":{"agents":[{"agent":"pi","cwd":"/workspace","foreground_cwd":1,"pane_id":"pane"}],"type":"agent_list"}}"#,
      #"{"result":{"agents":[],"type":"workspace_list"}}"#,
    ]

    for output in malformedOutputs {
      let runner = StubHerdrCommandRunner(
        executions: [
          HerdrCommandExecution(
            terminationStatus: 0,
            standardOutput: Data(output.utf8)
          )
        ]
      )
      let adapter = HerdrAgentAdapter(
        executablePathProvider: { "/usr/local/bin/herdr" },
        commandRunner: runner
      )

      let result = await query(using: adapter)
      XCTAssertEqual(result, .malformedOutput, "output: \(output)")
    }
  }

  func testQueryMapsExecutableAndCommandFailuresToHerdrUnavailable() async {
    let missingExecutableRunner = StubHerdrCommandRunner(executions: [])
    let missingExecutableAdapter = HerdrAgentAdapter(
      executablePathProvider: { nil },
      commandRunner: missingExecutableRunner
    )
    let missingExecutableResult = await query(using: missingExecutableAdapter)
    let missingExecutableCommands = await missingExecutableRunner.observedCommands()
    XCTAssertEqual(missingExecutableResult, .herdrUnavailable)
    XCTAssertEqual(missingExecutableCommands, [])

    let failedExecutions: [HerdrCommandExecution?] = [
      nil,
      HerdrCommandExecution(
        terminationStatus: 1,
        standardOutput: Data(#"{"error":{"code":"server_unavailable"}}"#.utf8)
      ),
    ]
    for execution in failedExecutions {
      let runner = StubHerdrCommandRunner(executions: [execution])
      let adapter = HerdrAgentAdapter(
        executablePathProvider: { "/usr/local/bin/herdr" },
        commandRunner: runner
      )
      let result = await query(using: adapter)
      XCTAssertEqual(result, .herdrUnavailable)
    }
  }

  func testFocusExecutesPaneTargetAndMapsCommandResult() async {
    let runner = StubHerdrCommandRunner(
      executions: [
        HerdrCommandExecution(terminationStatus: 0, standardOutput: Data())
      ]
    )
    let adapter = HerdrAgentAdapter(
      executablePathProvider: { "/usr/local/bin/herdr" },
      commandRunner: runner
    )

    let result = await focus("pane-leading-pi", using: adapter)
    let commands = await runner.observedCommands()
    XCTAssertEqual(result, .succeeded)
    XCTAssertEqual(
      commands,
      [
        HerdrCommand(
          executablePath: "/usr/local/bin/herdr",
          arguments: ["agent", "focus", "pane-leading-pi"]
        )
      ]
    )

    let failedExecutions: [HerdrCommandExecution?] = [
      nil,
      HerdrCommandExecution(terminationStatus: 1, standardOutput: Data()),
    ]
    for execution in failedExecutions {
      let failingRunner = StubHerdrCommandRunner(executions: [execution])
      let failingAdapter = HerdrAgentAdapter(
        executablePathProvider: { "/usr/local/bin/herdr" },
        commandRunner: failingRunner
      )
      let result = await focus("pane", using: failingAdapter)
      XCTAssertEqual(result, .failed)
    }
  }

  func testLiveHerdrFocusesWorkspaceLeadingPiAgentWhenOptedIn() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["SIGLAUNCH_RUN_HERDR_FOCUS_SMOKE"] == "1" else {
      throw XCTSkip(
        "Set SIGLAUNCH_RUN_HERDR_FOCUS_SMOKE=1 to modify live Herdr focus."
      )
    }
    let workspacePath =
      environment["SIGLAUNCH_HERDR_FOCUS_WORKSPACE"]
      ?? FileManager.default.currentDirectoryPath
    let adapter = HerdrAgentAdapter()
    let queryResult = await query(using: adapter)

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
          WorkflowConfiguration(workspacePath: workspacePath, piCommand: ["pi"])
        )
      ),
      .ghosttyResolutionCompleted(
        .found(
          GhosttyApplication(
            path: "/Applications/Ghostty.app",
            version: "1.3.0",
            isRunning: true
          )
        )
      ),
      .defaultHerdrSessionEnsureCompleted(.ready(.reused)),
    ] {
      _ = coordinator.handle(event)
    }

    guard
      case .focusHerdrAgent(let paneID) = coordinator.handle(
        .herdrAgentQueryCompleted(queryResult)
      ).first
    else {
      return XCTFail("No Pi Agent matches Workspace \(workspacePath).")
    }

    let focusResult = await focus(paneID, using: adapter)
    XCTAssertEqual(focusResult, .succeeded)
  }

  private func query(using adapter: HerdrAgentAdapter) async -> HerdrAgentQueryResult {
    await withCheckedContinuation { continuation in
      adapter.queryAgents { result in
        continuation.resume(returning: result)
      }
    }
  }

  private func focus(
    _ paneID: String,
    using adapter: HerdrAgentAdapter
  ) async -> HerdrAgentFocusResult {
    await withCheckedContinuation { continuation in
      adapter.focusAgent(paneID: paneID) { result in
        continuation.resume(returning: result)
      }
    }
  }
}

private actor StubHerdrCommandRunner: HerdrCommandRunning {
  private var executions: [HerdrCommandExecution?]
  private var commands: [HerdrCommand] = []

  init(executions: [HerdrCommandExecution?]) {
    self.executions = executions
  }

  func run(_ command: HerdrCommand) async -> HerdrCommandExecution? {
    commands.append(command)
    return executions.removeFirst()
  }

  func observedCommands() -> [HerdrCommand] {
    commands
  }
}
