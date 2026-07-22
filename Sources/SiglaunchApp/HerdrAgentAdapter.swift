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
}

@MainActor
final class HerdrAgentAdapter: HerdrAgentAdapting {
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

  convenience init(
    executableResolver: HerdrExecutableResolver = HerdrExecutableResolver(),
    commandRunner: any HerdrCommandRunning = FoundationHerdrCommandRunner()
  ) {
    self.init(
      executablePathProvider: { executableResolver.resolve() },
      commandRunner: commandRunner
    )
  }

  init(
    executablePathProvider: @escaping () -> String?,
    commandRunner: any HerdrCommandRunning
  ) {
    self.executablePathProvider = executablePathProvider
    self.commandRunner = commandRunner
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
