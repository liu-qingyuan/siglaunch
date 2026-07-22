import AppKit
import Foundation
import SiglaunchCore

struct HerdrExecutableResolver {
  private let fileManager: FileManager
  private let environment: [String: String]
  private let homeDirectory: URL

  init(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) {
    self.fileManager = fileManager
    self.environment = environment
    self.homeDirectory = homeDirectory
  }

  func resolve() -> String? {
    var candidates: [URL] = []
    if let path = environment["PATH"] {
      candidates.append(
        contentsOf: path.split(separator: ":").compactMap { directory in
          guard directory.first == "/" else { return nil }
          return URL(fileURLWithPath: String(directory), isDirectory: true)
            .appendingPathComponent("herdr", isDirectory: false)
        }
      )
    }
    candidates.append(
      homeDirectory
        .appendingPathComponent(".local/bin", isDirectory: true)
        .appendingPathComponent("herdr", isDirectory: false)
    )
    candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/herdr"))
    candidates.append(URL(fileURLWithPath: "/usr/local/bin/herdr"))

    var checkedPaths: Set<String> = []
    for candidate in candidates {
      let resolvedURL = candidate.standardizedFileURL.resolvingSymlinksInPath()
      guard checkedPaths.insert(resolvedURL.path).inserted else { continue }

      var isDirectory: ObjCBool = false
      guard
        fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
        !isDirectory.boolValue,
        fileManager.isExecutableFile(atPath: resolvedURL.path)
      else {
        continue
      }
      return resolvedURL.path
    }
    return nil
  }
}

@MainActor
protocol GhosttyPlatformAdapting: AnyObject {
  func resolve() -> GhosttyResolutionResult
  func launch(
    at path: String,
    completion: @escaping @MainActor @Sendable (GhosttyLaunchResult) -> Void
  )
  func ensureDefaultHerdrSession(
    completion: @escaping @MainActor @Sendable (DefaultHerdrSessionEnsureResult) -> Void
  )
}

@MainActor
final class GhosttyPlatformAdapter: GhosttyPlatformAdapting {
  static let bundleIdentifier = "com.mitchellh.ghostty"

  private let workspace: NSWorkspace
  private let automation: GhosttyAppleScriptAdapter

  init(
    workspace: NSWorkspace = .shared,
    automation: GhosttyAppleScriptAdapter = GhosttyAppleScriptAdapter()
  ) {
    self.workspace = workspace
    self.automation = automation
  }

  func resolve() -> GhosttyResolutionResult {
    let runningApplications = NSRunningApplication.runningApplications(
      withBundleIdentifier: Self.bundleIdentifier
    )
    let runningApplication =
      runningApplications.first(where: \.isActive) ?? runningApplications.first
    if let runningURL = runningApplication?.bundleURL {
      return descriptor(for: runningURL, isRunning: true)
    }

    guard
      let applicationURL = workspace.urlForApplication(
        withBundleIdentifier: Self.bundleIdentifier
      )
    else {
      return .notInstalled
    }
    return descriptor(for: applicationURL, isRunning: !runningApplications.isEmpty)
  }

  private func descriptor(for applicationURL: URL, isRunning: Bool) -> GhosttyResolutionResult {
    let version =
      Bundle(url: applicationURL)?
      .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return .found(
      GhosttyApplication(
        path: applicationURL.path,
        version: version,
        isRunning: isRunning
      )
    )
  }

  func launch(
    at path: String,
    completion: @escaping @MainActor @Sendable (GhosttyLaunchResult) -> Void
  ) {
    if let runningApplication = NSRunningApplication.runningApplications(
      withBundleIdentifier: Self.bundleIdentifier
    ).first {
      runningApplication.activate(options: [.activateAllWindows])
      completion(.succeeded)
      return
    }

    let applicationURL = URL(fileURLWithPath: path, isDirectory: true)
    guard FileManager.default.fileExists(atPath: applicationURL.path) else {
      completion(.failed)
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    workspace.openApplication(at: applicationURL, configuration: configuration) {
      _, error in
      let result: GhosttyLaunchResult = error == nil ? .succeeded : .failed
      Task { @MainActor in
        completion(result)
      }
    }
  }

  func ensureDefaultHerdrSession(
    completion: @escaping @MainActor @Sendable (DefaultHerdrSessionEnsureResult) -> Void
  ) {
    automation.ensureDefaultHerdrSession(completion: completion)
  }
}
