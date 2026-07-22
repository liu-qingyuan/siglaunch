import Foundation
import SiglaunchCore

protocol WorkflowConfigurationLoading {
  func load() -> WorkflowConfigurationLoadResult
}

final class WorkflowConfigurationStore: WorkflowConfigurationLoading {
  static var defaultConfigurationURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support", isDirectory: true)
      .appendingPathComponent("Siglaunch", isDirectory: true)
      .appendingPathComponent("workflow.json", isDirectory: false)
  }

  private let configurationURL: URL

  init(configurationURL: URL = WorkflowConfigurationStore.defaultConfigurationURL) {
    self.configurationURL = configurationURL
  }

  func load() -> WorkflowConfigurationLoadResult {
    let data: Data
    do {
      data = try Data(contentsOf: configurationURL)
    } catch {
      return .failed(.unavailable)
    }

    let value: Any
    do {
      value = try JSONSerialization.jsonObject(with: data)
    } catch {
      return .failed(.malformed)
    }

    guard
      let root = value as? [String: Any],
      Set(root.keys) == ["workspace", "pi"],
      let workspace = root["workspace"] as? [String: Any],
      Set(workspace.keys) == ["path"],
      let workspacePath = workspace["path"] as? String,
      let pi = root["pi"] as? [String: Any],
      Set(pi.keys) == ["command"],
      let piCommand = pi["command"] as? [String]
    else {
      return .failed(.invalidStructure)
    }

    guard !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .failed(.emptyWorkspacePath)
    }
    guard !piCommand.isEmpty else {
      return .failed(.emptyPiCommand)
    }

    return .loaded(
      WorkflowConfiguration(
        workspacePath: workspacePath,
        piCommand: piCommand
      )
    )
  }
}
