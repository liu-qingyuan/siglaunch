import Foundation
import SiglaunchCore

struct HerdrCommand: Equatable, Sendable {
  let executablePath: String
  let arguments: [String]
}

struct HerdrCommandExecution: Equatable, Sendable {
  let terminationStatus: Int32
  let standardOutput: Data
}

protocol HerdrCommandRunning: Sendable {
  func run(_ command: HerdrCommand) async -> HerdrCommandExecution?
}

struct FoundationHerdrCommandRunner: HerdrCommandRunning {
  func run(_ command: HerdrCommand) async -> HerdrCommandExecution? {
    await Task.detached(priority: .userInitiated) {
      let process = Process()
      let standardOutput = Pipe()
      process.executableURL = URL(fileURLWithPath: command.executablePath)
      process.arguments = command.arguments
      process.standardInput = FileHandle.nullDevice
      process.standardOutput = standardOutput
      process.standardError = FileHandle.nullDevice

      do {
        try process.run()
      } catch {
        return nil
      }

      let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      return HerdrCommandExecution(
        terminationStatus: process.terminationStatus,
        standardOutput: output
      )
    }.value
  }
}

@MainActor
protocol HerdrAgentAdapting: AnyObject {
  func queryAgents(
    completion: @escaping @MainActor @Sendable (HerdrAgentQueryResult) -> Void
  )
  func focusAgent(
    paneID: String,
    completion: @escaping @MainActor @Sendable (HerdrAgentFocusResult) -> Void
  )
  func startPiAgent(
    workspacePath: String,
    command: [String],
    completion: @escaping @MainActor @Sendable (HerdrAgentStartResult) -> Void
  )
}

@MainActor
final class HerdrAgentAdapter: HerdrAgentAdapting {
  private enum AgentStartContract {
    case legacy
    case livePane
  }

  private struct HerdrVersion {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: Substring) {
      let components = value.split(
        separator: ".",
        omittingEmptySubsequences: false
      )
      guard
        components.count == 3,
        let major = Self.coreNumber(components[0]),
        let minor = Self.coreNumber(components[1]),
        let patch = Self.coreNumber(components[2])
      else {
        return nil
      }
      self.major = major
      self.minor = minor
      self.patch = patch
    }

    func isAtLeast(major: Int, minor: Int, patch: Int) -> Bool {
      if self.major != major { return self.major > major }
      if self.minor != minor { return self.minor > minor }
      return self.patch >= patch
    }

    private static func coreNumber(_ value: Substring) -> Int? {
      guard
        !value.isEmpty,
        value.utf8.allSatisfy({ (48...57).contains($0) }),
        value.count == 1 || value.first != "0"
      else {
        return nil
      }
      return Int(value)
    }
  }

  private struct AgentStartEnvelope: Decodable {
    let result: Result

    struct Result: Decodable {
      let argv: [String]
      let type: String
    }
  }

  private struct WorkspaceCreateEnvelope: Decodable {
    let result: Result

    struct Result: Decodable {
      let rootPane: RootPane
      let type: String
      let workspace: Workspace

      private enum CodingKeys: String, CodingKey {
        case rootPane = "root_pane"
        case type
        case workspace
      }
    }

    struct RootPane: Decodable {
      let paneID: String

      private enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
      }
    }

    struct Workspace: Decodable {
      let workspaceID: String

      private enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
      }
    }
  }

  private struct AgentListEnvelope: Decodable {
    let result: Result

    struct Result: Decodable {
      let agents: [Agent]
      let type: String
    }

    struct Agent: Decodable {
      let paneID: String
      let agent: String
      let cwd: String?
      let foregroundCwd: String?

      private enum CodingKeys: String, CodingKey, CaseIterable {
        case paneID = "pane_id"
        case agent
        case cwd
        case foregroundCwd = "foreground_cwd"
      }

      init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        for key in CodingKeys.allCases {
          guard values.contains(key) else {
            throw DecodingError.keyNotFound(
              key,
              DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Missing required Herdr Agent field: \(key.stringValue)"
              )
            )
          }
        }

        paneID = try values.decode(String.self, forKey: .paneID)
        agent = try values.decode(String.self, forKey: .agent)
        cwd = try values.decodeIfPresent(String.self, forKey: .cwd)
        foregroundCwd = try values.decodeIfPresent(String.self, forKey: .foregroundCwd)

        guard
          !paneID.isEmpty,
          !agent.isEmpty,
          cwd?.isEmpty != true,
          foregroundCwd?.isEmpty != true
        else {
          throw DecodingError.dataCorruptedError(
            forKey: .paneID,
            in: values,
            debugDescription: "Herdr Agent fields cannot be empty"
          )
        }
      }
    }
  }

  private let executablePathProvider: () -> String?
  private let commandRunner: any HerdrCommandRunning
  private let agentNameProvider: () -> String

  convenience init(
    executableResolver: HerdrExecutableResolver = HerdrExecutableResolver(),
    commandRunner: any HerdrCommandRunning = FoundationHerdrCommandRunner()
  ) {
    self.init(
      executablePathProvider: { executableResolver.resolve() },
      commandRunner: commandRunner,
      agentNameProvider: Self.makeAgentName
    )
  }

  init(
    executablePathProvider: @escaping () -> String?,
    commandRunner: any HerdrCommandRunning,
    agentNameProvider: @escaping () -> String = HerdrAgentAdapter.makeAgentName
  ) {
    self.executablePathProvider = executablePathProvider
    self.commandRunner = commandRunner
    self.agentNameProvider = agentNameProvider
  }

  func queryAgents(
    completion: @escaping @MainActor @Sendable (HerdrAgentQueryResult) -> Void
  ) {
    guard let executablePath = executablePathProvider() else {
      completion(.herdrUnavailable)
      return
    }

    let command = HerdrCommand(
      executablePath: executablePath,
      arguments: ["agent", "list"]
    )
    Task {
      let execution = await commandRunner.run(command)
      completion(Self.queryResult(from: execution))
    }
  }

  func focusAgent(
    paneID: String,
    completion: @escaping @MainActor @Sendable (HerdrAgentFocusResult) -> Void
  ) {
    guard let executablePath = executablePathProvider() else {
      completion(.failed)
      return
    }

    let command = HerdrCommand(
      executablePath: executablePath,
      arguments: ["agent", "focus", paneID]
    )
    Task {
      let execution = await commandRunner.run(command)
      completion(execution?.terminationStatus == 0 ? .succeeded : .failed)
    }
  }

  func startPiAgent(
    workspacePath: String,
    command: [String],
    completion: @escaping @MainActor @Sendable (HerdrAgentStartResult) -> Void
  ) {
    guard let executablePath = executablePathProvider(), !command.isEmpty else {
      completion(.failed)
      return
    }

    Task {
      let versionExecution = await commandRunner.run(
        HerdrCommand(executablePath: executablePath, arguments: ["--version"])
      )
      guard let contract = Self.agentStartContract(from: versionExecution) else {
        completion(.failed)
        return
      }

      switch contract {
      case .legacy:
        let herdrCommand = HerdrCommand(
          executablePath: executablePath,
          arguments: [
            "agent", "start", agentNameProvider(),
            "--cwd", workspacePath,
            "--focus", "--",
          ] + command
        )
        let execution = await commandRunner.run(herdrCommand)
        completion(Self.startResult(from: execution, expectedCommand: command))
      case .livePane:
        guard command.first == "pi" else {
          completion(.failed)
          return
        }

        let workspaceExecution = await commandRunner.run(
          HerdrCommand(
            executablePath: executablePath,
            arguments: [
              "workspace", "create",
              "--cwd", workspacePath,
              "--focus",
            ]
          )
        )
        guard let workspace = Self.createdWorkspace(from: workspaceExecution) else {
          completion(.failed)
          return
        }

        let startExecution = await commandRunner.run(
          HerdrCommand(
            executablePath: executablePath,
            arguments: [
              "agent", "start", agentNameProvider(),
              "--kind", "pi",
              "--pane", workspace.paneID,
              "--",
            ] + command.dropFirst()
          )
        )
        let result = Self.startResult(
          from: startExecution,
          expectedCommand: command
        )
        if result == .failed {
          _ = await commandRunner.run(
            HerdrCommand(
              executablePath: executablePath,
              arguments: ["workspace", "close", workspace.workspaceID]
            )
          )
        }
        completion(result)
      }
    }
  }

  private static func agentStartContract(
    from execution: HerdrCommandExecution?
  ) -> AgentStartContract? {
    guard
      let execution,
      execution.terminationStatus == 0,
      let output = String(data: execution.standardOutput, encoding: .utf8)
    else {
      return nil
    }

    let fields = output.split(whereSeparator: { $0.isWhitespace })
    guard
      fields.count == 2,
      fields[0] == "herdr",
      let version = HerdrVersion(fields[1]),
      version.isAtLeast(major: 0, minor: 7, patch: 4)
    else {
      return nil
    }
    return version.isAtLeast(major: 0, minor: 7, patch: 5) ? .livePane : .legacy
  }

  private static func createdWorkspace(
    from execution: HerdrCommandExecution?
  ) -> (workspaceID: String, paneID: String)? {
    guard
      let execution,
      execution.terminationStatus == 0,
      let envelope = try? JSONDecoder().decode(
        WorkspaceCreateEnvelope.self,
        from: execution.standardOutput
      ),
      envelope.result.type == "workspace_created",
      !envelope.result.workspace.workspaceID.isEmpty,
      !envelope.result.rootPane.paneID.isEmpty
    else {
      return nil
    }
    return (
      workspaceID: envelope.result.workspace.workspaceID,
      paneID: envelope.result.rootPane.paneID
    )
  }

  private static func startResult(
    from execution: HerdrCommandExecution?,
    expectedCommand: [String]
  ) -> HerdrAgentStartResult {
    guard let execution, execution.terminationStatus == 0 else {
      return .failed
    }

    guard
      let envelope = try? JSONDecoder().decode(
        AgentStartEnvelope.self,
        from: execution.standardOutput
      ),
      envelope.result.type == "agent_started",
      envelope.result.argv == expectedCommand
    else {
      return .failed
    }
    return .succeeded
  }

  private nonisolated static func makeAgentName() -> String {
    let identifier = UUID().uuidString
      .replacingOccurrences(of: "-", with: "")
      .lowercased()
    return "siglaunch-\(identifier.prefix(22))"
  }

  private static func queryResult(
    from execution: HerdrCommandExecution?
  ) -> HerdrAgentQueryResult {
    guard let execution, execution.terminationStatus == 0 else {
      return .herdrUnavailable
    }

    do {
      let envelope = try JSONDecoder().decode(
        AgentListEnvelope.self,
        from: execution.standardOutput
      )
      guard envelope.result.type == "agent_list" else {
        return .malformedOutput
      }
      return .agents(
        envelope.result.agents.map { agent in
          HerdrAgent(
            paneID: agent.paneID,
            agent: agent.agent,
            cwd: agent.cwd,
            foregroundCwd: agent.foregroundCwd
          )
        }
      )
    } catch {
      return .malformedOutput
    }
  }
}
