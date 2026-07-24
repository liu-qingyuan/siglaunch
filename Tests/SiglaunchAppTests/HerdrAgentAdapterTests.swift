import AppKit
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
      #"{"result":{"agents":[{"agent":"pi","cwd":"/valid","foreground_cwd":null,"pane_id":"valid"},{"agent":"pi","cwd":"/invalid","foreground_cwd":null}],"type":"agent_list"}}"#,
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

  func testStartPiExecutesLegacyStructuredArgvAndRequiresHerdrConfirmation() async {
    let command = [
      "/Applications/Pi CLI/bin/pi",
      "--model",
      "gpt 5",
      "",
      "$(touch /tmp/must-not-run)",
    ]
    let output =
      #"{"result":{"argv":["/Applications/Pi CLI/bin/pi","--model","gpt 5","","$(touch /tmp/must-not-run)"],"type":"agent_started"}}"#
    let runner = StubHerdrCommandRunner(
      executions: [
        HerdrCommandExecution(
          terminationStatus: 0,
          standardOutput: Data("herdr 0.7.4\n".utf8)
        ),
        HerdrCommandExecution(
          terminationStatus: 0,
          standardOutput: Data(output.utf8)
        ),
      ]
    )
    let adapter = HerdrAgentAdapter(
      executablePathProvider: { "/usr/local/bin/herdr" },
      commandRunner: runner,
      agentNameProvider: { "siglaunch-test" }
    )

    let result = await startPi(
      workspacePath: "/Users/developer/Workspaces/Primary Workspace",
      command: command,
      using: adapter
    )

    XCTAssertEqual(result, .succeeded)
    let commands = await runner.observedCommands()
    XCTAssertEqual(
      commands,
      [
        HerdrCommand(
          executablePath: "/usr/local/bin/herdr",
          arguments: ["--version"]
        ),
        HerdrCommand(
          executablePath: "/usr/local/bin/herdr",
          arguments: [
            "agent", "start", "siglaunch-test",
            "--cwd", "/Users/developer/Workspaces/Primary Workspace",
            "--focus", "--",
          ] + command
        ),
      ]
    )
  }

  func testStartPiExecutesLivePaneContractAndPreservesArguments() async {
    let workspaceOutput =
      #"{"result":{"root_pane":{"pane_id":"w3:p1"},"type":"workspace_created","workspace":{"workspace_id":"w3"}}}"#
    let startOutput =
      #"{"result":{"argv":["pi","--model","gpt 5","","$(touch /tmp/must-not-run)"],"type":"agent_started"}}"#
    let runner = StubHerdrCommandRunner(
      executions: [
        HerdrCommandExecution(
          terminationStatus: 0,
          standardOutput: Data("herdr 0.7.5\n".utf8)
        ),
        HerdrCommandExecution(
          terminationStatus: 0,
          standardOutput: Data(workspaceOutput.utf8)
        ),
        HerdrCommandExecution(
          terminationStatus: 0,
          standardOutput: Data(startOutput.utf8)
        ),
      ]
    )
    let adapter = HerdrAgentAdapter(
      executablePathProvider: { "/usr/local/bin/herdr" },
      commandRunner: runner,
      agentNameProvider: { "siglaunch-test" }
    )
    let command = [
      "pi",
      "--model",
      "gpt 5",
      "",
      "$(touch /tmp/must-not-run)",
    ]

    let result = await startPi(
      workspacePath: "/Users/developer/Workspaces/Primary Workspace",
      command: command,
      using: adapter
    )

    XCTAssertEqual(result, .succeeded)
    let commands = await runner.observedCommands()
    XCTAssertEqual(
      commands,
      [
        HerdrCommand(
          executablePath: "/usr/local/bin/herdr",
          arguments: ["--version"]
        ),
        HerdrCommand(
          executablePath: "/usr/local/bin/herdr",
          arguments: [
            "workspace", "create",
            "--cwd", "/Users/developer/Workspaces/Primary Workspace",
            "--focus",
          ]
        ),
        HerdrCommand(
          executablePath: "/usr/local/bin/herdr",
          arguments: [
            "agent", "start", "siglaunch-test",
            "--kind", "pi",
            "--pane", "w3:p1",
            "--",
          ] + command.dropFirst()
        ),
      ]
    )
  }

  func testStartPiRejectsUnavailableUnsupportedAndMalformedContracts() async {
    let failedVersionExecutions: [HerdrCommandExecution?] = [
      nil,
      HerdrCommandExecution(terminationStatus: 1, standardOutput: Data()),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data("not-a-version".utf8)
      ),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data("herdr 0.7.3\n".utf8)
      ),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data("herdr -\n".utf8)
      ),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data("herdr +\n".utf8)
      ),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data("herdr 0.7.5-preview\n".utf8)
      ),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data("herdr 0.7.5-\n".utf8)
      ),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data("herdr -0.7.5\n".utf8)
      ),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data("herdr 0.7.5+build\n".utf8)
      ),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data("herdr 00.7.5\n".utf8)
      ),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data("herdr version 0.7.5\n".utf8)
      ),
    ]

    for execution in failedVersionExecutions {
      let runner = StubHerdrCommandRunner(executions: [execution])
      let adapter = HerdrAgentAdapter(
        executablePathProvider: { "/usr/local/bin/herdr" },
        commandRunner: runner
      )
      let result = await startPi(
        workspacePath: "/workspace",
        command: ["pi"],
        using: adapter
      )
      let commands = await runner.observedCommands()
      XCTAssertEqual(result, .failed)
      XCTAssertEqual(
        commands,
        [HerdrCommand(executablePath: "/usr/local/bin/herdr", arguments: ["--version"])]
      )
    }

    let missingExecutableRunner = StubHerdrCommandRunner(executions: [])
    let missingExecutableAdapter = HerdrAgentAdapter(
      executablePathProvider: { nil },
      commandRunner: missingExecutableRunner
    )
    let missingExecutableResult = await startPi(
      workspacePath: "/workspace",
      command: ["pi"],
      using: missingExecutableAdapter
    )
    let missingExecutableCommands = await missingExecutableRunner.observedCommands()
    XCTAssertEqual(missingExecutableResult, .failed)
    XCTAssertEqual(missingExecutableCommands, [])
  }

  func testLegacyStartMapsRefusalAndUnconfirmedOutputToFailure() async {
    let failedStartExecutions: [HerdrCommandExecution?] = [
      nil,
      HerdrCommandExecution(
        terminationStatus: 1,
        standardOutput: Data(#"{"error":{"code":"agent_start_failed"}}"#.utf8)
      ),
      HerdrCommandExecution(terminationStatus: 0, standardOutput: Data()),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data(
          #"{"result":{"argv":["pi"],"type":"agent_list"}}"#.utf8
        )
      ),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data(
          #"{"result":{"argv":["different"],"type":"agent_started"}}"#.utf8
        )
      ),
      HerdrCommandExecution(
        terminationStatus: 0,
        standardOutput: Data("not-json".utf8)
      ),
    ]

    for execution in failedStartExecutions {
      let runner = StubHerdrCommandRunner(
        executions: [
          HerdrCommandExecution(
            terminationStatus: 0,
            standardOutput: Data("herdr 0.7.4\n".utf8)
          ),
          execution,
        ]
      )
      let adapter = HerdrAgentAdapter(
        executablePathProvider: { "/usr/local/bin/herdr" },
        commandRunner: runner,
        agentNameProvider: { "siglaunch-test" }
      )

      let result = await startPi(
        workspacePath: "/workspace",
        command: ["pi"],
        using: adapter
      )
      XCTAssertEqual(result, .failed)
    }
  }

  func testLivePaneContractRejectsExecutableSubstitutionBeforeCreatingWorkspace() async {
    let runner = StubHerdrCommandRunner(
      executions: [
        HerdrCommandExecution(
          terminationStatus: 0,
          standardOutput: Data("herdr 0.7.5\n".utf8)
        )
      ]
    )
    let adapter = HerdrAgentAdapter(
      executablePathProvider: { "/usr/local/bin/herdr" },
      commandRunner: runner
    )

    let result = await startPi(
      workspacePath: "/workspace",
      command: ["/custom/bin/pi", "--model", "gpt-5"],
      using: adapter
    )
    let commands = await runner.observedCommands()

    XCTAssertEqual(result, .failed)
    XCTAssertEqual(
      commands,
      [HerdrCommand(executablePath: "/usr/local/bin/herdr", arguments: ["--version"])]
    )
  }

  func testLivePaneStartFailureClosesCreatedWorkspace() async {
    let workspaceOutput =
      #"{"result":{"root_pane":{"pane_id":"w3:p1"},"type":"workspace_created","workspace":{"workspace_id":"w3"}}}"#
    let runner = StubHerdrCommandRunner(
      executions: [
        HerdrCommandExecution(
          terminationStatus: 0,
          standardOutput: Data("herdr 0.7.5\n".utf8)
        ),
        HerdrCommandExecution(
          terminationStatus: 0,
          standardOutput: Data(workspaceOutput.utf8)
        ),
        HerdrCommandExecution(
          terminationStatus: 1,
          standardOutput: Data(#"{"error":{"code":"agent_start_failed"}}"#.utf8)
        ),
        HerdrCommandExecution(
          terminationStatus: 0,
          standardOutput: Data(#"{"result":{"type":"ok"}}"#.utf8)
        ),
      ]
    )
    let adapter = HerdrAgentAdapter(
      executablePathProvider: { "/usr/local/bin/herdr" },
      commandRunner: runner,
      agentNameProvider: { "siglaunch-test" }
    )

    let result = await startPi(
      workspacePath: "/workspace",
      command: ["pi", "--model", "gpt-5"],
      using: adapter
    )
    let commands = await runner.observedCommands()

    XCTAssertEqual(result, .failed)
    XCTAssertEqual(
      commands.last,
      HerdrCommand(
        executablePath: "/usr/local/bin/herdr",
        arguments: ["workspace", "close", "w3"]
      )
    )
  }

  func testLiveHerdrQueryPreservesFrontmostApplicationAndStableSnapshotWhenOptedIn()
    async throws
  {
    let environment = ProcessInfo.processInfo.environment
    guard environment["SIGLAUNCH_RUN_HERDR_QUERY_SMOKE"] == "1" else {
      throw XCTSkip(
        "Set SIGLAUNCH_RUN_HERDR_QUERY_SMOKE=1 to run the read-only live query."
      )
    }

    let frontmostBefore = NSWorkspace.shared.frontmostApplication
    let processIdentifierBefore = frontmostBefore?.processIdentifier
    let bundleIdentifierBefore = frontmostBefore?.bundleIdentifier
    let adapter = HerdrAgentAdapter()
    let firstResult = await query(using: adapter)
    let secondResult = await query(using: adapter)
    let frontmostAfter = NSWorkspace.shared.frontmostApplication

    guard
      case .agents(let firstAgents) = firstResult,
      case .agents(let secondAgents) = secondResult
    else {
      return XCTFail(
        "Live Herdr queries must return fully decoded Agent snapshots: "
          + "\(firstResult), \(secondResult)"
      )
    }
    XCTAssertEqual(firstAgents, secondAgents)
    XCTAssertEqual(processIdentifierBefore, frontmostAfter?.processIdentifier)
    XCTAssertEqual(bundleIdentifierBefore, frontmostAfter?.bundleIdentifier)
  }

  func testLiveHerdrStartsConfiguredPiAgentWhenOptedIn() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["SIGLAUNCH_RUN_HERDR_START_SMOKE"] == "1" else {
      throw XCTSkip(
        "Set SIGLAUNCH_RUN_HERDR_START_SMOKE=1 to modify live Herdr Agent state."
      )
    }

    let workspacePath = try XCTUnwrap(
      environment["SIGLAUNCH_HERDR_START_WORKSPACE"],
      "Set SIGLAUNCH_HERDR_START_WORKSPACE to an intentionally prepared Workspace."
    )
    let commandJSON = try XCTUnwrap(
      environment["SIGLAUNCH_HERDR_START_COMMAND_JSON"],
      "Set SIGLAUNCH_HERDR_START_COMMAND_JSON to a JSON argv array."
    )
    let command = try JSONDecoder().decode([String].self, from: Data(commandJSON.utf8))
    XCTAssertFalse(command.isEmpty, "The live Pi command must not be empty.")

    let result = await startPi(
      workspacePath: workspacePath,
      command: command,
      using: HerdrAgentAdapter()
    )

    XCTAssertEqual(result, .succeeded)
  }

  private func query(using adapter: HerdrAgentAdapter) async -> HerdrAgentQueryResult {
    await withCheckedContinuation { continuation in
      adapter.queryAgents { result in
        continuation.resume(returning: result)
      }
    }
  }

  private func startPi(
    workspacePath: String,
    command: [String],
    using adapter: HerdrAgentAdapter
  ) async -> HerdrAgentStartResult {
    await withCheckedContinuation { continuation in
      adapter.startPiAgent(workspacePath: workspacePath, command: command) { result in
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
    guard !executions.isEmpty else { return nil }
    return executions.removeFirst()
  }

  func observedCommands() -> [HerdrCommand] {
    commands
  }
}
