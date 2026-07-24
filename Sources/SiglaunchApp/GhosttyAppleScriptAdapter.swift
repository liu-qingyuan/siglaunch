import Foundation
import SiglaunchCore

protocol HerdrClientProcessProbing {
  func isClientRunning(executablePath: String, sessionToken: String) -> Bool
}

struct SystemHerdrClientProcessProbe: HerdrClientProcessProbing {
  typealias ProcessOutput = ([String]) -> String?

  private let processOutput: ProcessOutput

  init() {
    processOutput = Self.runPS
  }

  init(processOutput: @escaping ProcessOutput) {
    self.processOutput = processOutput
  }

  func isClientRunning(executablePath: String, sessionToken: String) -> Bool {
    guard
      let listing = processOutput(["-axww", "-o", "pid=,args="])
    else { return false }

    let executableName = URL(fileURLWithPath: executablePath).lastPathComponent
    let clientArguments = [
      executablePath,
      executableName,
      "-\(executablePath)",
      "-\(executableName)",
    ]
    let marker = "SIGLAUNCH_HERDR_SESSION_TOKEN=\(sessionToken)"
    for rawLine in listing.split(whereSeparator: { $0.isNewline }) {
      let line = rawLine.drop(while: { $0.isWhitespace })
      guard
        let separator = line.firstIndex(where: { $0.isWhitespace }),
        !line[..<separator].isEmpty
      else { continue }

      let processID = String(line[..<separator])
      let arguments = String(line[separator...].drop(while: { $0.isWhitespace }))
      guard clientArguments.contains(arguments) else { continue }
      guard
        let environment = processOutput([
          "-Eww", "-p", processID, "-o", "command=",
        ])
      else { continue }
      if environment.split(whereSeparator: { $0.isWhitespace }).contains(Substring(marker)) {
        return true
      }
    }
    return false
  }

  private static func runPS(arguments: [String]) -> String? {
    let process = Process()
    let standardOutput = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = arguments
    process.standardOutput = standardOutput
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      return nil
    }
    let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: output, encoding: .utf8)
  }
}

@MainActor
final class GhosttyAppleScriptAdapter {
  private struct ManagedSession {
    let terminalID: String
    let token: String
  }

  private enum ScriptExecution {
    case values([String])
    case automationFailed(GhosttyAutomationFailure)
  }

  private static let terminalIDKey = "Siglaunch.defaultHerdrTerminalID"
  private static let sessionTokenKey = "Siglaunch.defaultHerdrSessionToken"

  private let executableResolver: HerdrExecutableResolver
  private let defaults: UserDefaults
  private let processProbe: any HerdrClientProcessProbing
  private let sessionTokenGenerator: () -> String

  init(
    executableResolver: HerdrExecutableResolver = HerdrExecutableResolver(),
    defaults: UserDefaults = .standard,
    processProbe: any HerdrClientProcessProbing = SystemHerdrClientProcessProbe(),
    sessionTokenGenerator: @escaping () -> String = { UUID().uuidString }
  ) {
    self.executableResolver = executableResolver
    self.defaults = defaults
    self.processProbe = processProbe
    self.sessionTokenGenerator = sessionTokenGenerator
  }

  func ensureDefaultHerdrSession(
    completion: @escaping @MainActor @Sendable (DefaultHerdrSessionEnsureResult) -> Void
  ) {
    guard let executablePath = executableResolver.resolve() else {
      completion(.herdrUnavailable)
      return
    }

    let reusableSession = reusableSession(executablePath: executablePath)
    if reusableSession == nil {
      clearStoredSession()
    }
    let launchSessionToken = sessionTokenGenerator()
    guard
      UUID(uuidString: launchSessionToken) != nil,
      let source = Self.source(
        herdrExecutablePath: executablePath,
        knownTerminalID: reusableSession?.terminalID,
        launchSessionToken: launchSessionToken
      )
    else {
      completion(.automationFailed(.unavailable))
      return
    }

    switch execute(source) {
    case .values(let values):
      guard
        values.count == 2,
        UUID(uuidString: values[1]) != nil
      else {
        completion(.automationFailed(.unavailable))
        return
      }
      switch values[0] {
      case "reused":
        guard
          let reusableSession,
          values[1] == reusableSession.terminalID
        else {
          completion(.automationFailed(.unavailable))
          return
        }
        storeSession(reusableSession)
        completion(.ready(.reused))
      case "pending":
        let session = ManagedSession(
          terminalID: values[1],
          token: launchSessionToken
        )
        storeSession(session)
        waitForHerdr(
          session: session,
          executablePath: executablePath,
          completion: completion
        )
      default:
        completion(.automationFailed(.unavailable))
      }
    case .automationFailed(let failure):
      completion(.automationFailed(failure))
    }
  }

  static func source(
    herdrExecutablePath: String,
    knownTerminalID: String?,
    launchSessionToken: String
  ) -> String? {
    guard
      let commandLiteral = appleScriptLiteral(herdrExecutablePath),
      let terminalIDLiteral = appleScriptLiteral(knownTerminalID ?? ""),
      let sessionMarkerLiteral = appleScriptLiteral(
        "SIGLAUNCH_HERDR_SESSION_TOKEN=\(launchSessionToken)"
      )
    else {
      return nil
    }

    return #"""
      tell application id "com.mitchellh.ghostty"
        set knownTerminalID to \#(terminalIDLiteral)
        if knownTerminalID is not "" then
          repeat with candidateTerminal in terminals
            if (id of candidateTerminal) is knownTerminalID then
              focus candidateTerminal
              return {"reused", knownTerminalID}
            end if
          end repeat
        end if

        set sessionConfiguration to new surface configuration
        set command of sessionConfiguration to \#(commandLiteral)
        set environment variables of sessionConfiguration to {\#(sessionMarkerLiteral)}
        set wait after command of sessionConfiguration to false
        if (count of windows) > 0 then
          set createdTab to new tab in front window with configuration sessionConfiguration
          set createdTerminal to terminal 1 of createdTab
        else
          set createdWindow to new window with configuration sessionConfiguration
          set createdTerminal to terminal 1 of createdWindow
        end if
        set createdTerminalID to id of createdTerminal
        return {"pending", createdTerminalID}
      end tell
      """#
  }

  static func readinessSource(terminalID: String) -> String? {
    guard let terminalIDLiteral = appleScriptLiteral(terminalID) else { return nil }

    return #"""
      tell application id "com.mitchellh.ghostty"
        set expectedTerminalID to \#(terminalIDLiteral)
        repeat with candidateTerminal in terminals
          if (id of candidateTerminal) is expectedTerminalID then
            focus candidateTerminal
            return {"present", expectedTerminalID}
          end if
        end repeat
        return {"missing", expectedTerminalID}
      end tell
      """#
  }

  static func automationFailure(
    from errorInfo: NSDictionary
  ) -> GhosttyAutomationFailure {
    let errorNumber = (errorInfo["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue
    let message = (errorInfo["NSAppleScriptErrorMessage"] as? String) ?? ""
    if errorNumber == -1743,
      !message.localizedCaseInsensitiveContains("macos-applescript")
    {
      return .denied
    }
    return .unavailable
  }

  private func reusableSession(executablePath: String) -> ManagedSession? {
    guard
      let terminalID = defaults.string(forKey: Self.terminalIDKey),
      UUID(uuidString: terminalID) != nil,
      let token = defaults.string(forKey: Self.sessionTokenKey),
      UUID(uuidString: token) != nil,
      processProbe.isClientRunning(
        executablePath: executablePath,
        sessionToken: token
      )
    else {
      return nil
    }
    return ManagedSession(terminalID: terminalID, token: token)
  }

  private func storeSession(_ session: ManagedSession) {
    defaults.set(session.terminalID, forKey: Self.terminalIDKey)
    defaults.set(session.token, forKey: Self.sessionTokenKey)
  }

  private func clearStoredSession() {
    defaults.removeObject(forKey: Self.terminalIDKey)
    defaults.removeObject(forKey: Self.sessionTokenKey)
  }

  private func waitForHerdr(
    session: ManagedSession,
    executablePath: String,
    completion: @escaping @MainActor @Sendable (DefaultHerdrSessionEnsureResult) -> Void
  ) {
    Task { @MainActor in
      for _ in 0..<10 {
        do {
          try await Task.sleep(for: .milliseconds(500))
        } catch {
          clearStoredSession()
          completion(.herdrUnavailable)
          return
        }

        guard let source = Self.readinessSource(terminalID: session.terminalID) else {
          clearStoredSession()
          completion(.automationFailed(.unavailable))
          return
        }
        switch execute(source) {
        case .values(let values):
          guard values.count == 2, values[1] == session.terminalID else {
            clearStoredSession()
            completion(.automationFailed(.unavailable))
            return
          }
          switch values[0] {
          case "present":
            guard
              processProbe.isClientRunning(
                executablePath: executablePath,
                sessionToken: session.token
              )
            else { continue }
            storeSession(session)
            completion(.ready(.started))
            return
          case "missing":
            clearStoredSession()
            completion(.herdrUnavailable)
            return
          default:
            clearStoredSession()
            completion(.automationFailed(.unavailable))
            return
          }
        case .automationFailed(let failure):
          clearStoredSession()
          completion(.automationFailed(failure))
          return
        }
      }
      clearStoredSession()
      completion(.herdrUnavailable)
    }
  }

  private func execute(_ source: String) -> ScriptExecution {
    guard let script = NSAppleScript(source: source) else {
      return .automationFailed(.unavailable)
    }

    var errorInfo: NSDictionary?
    let result = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
      return .automationFailed(Self.automationFailure(from: errorInfo))
    }

    var values: [String] = []
    if result.numberOfItems > 0 {
      for index in 1...result.numberOfItems {
        guard let value = result.atIndex(index)?.stringValue else {
          return .automationFailed(.unavailable)
        }
        values.append(value)
      }
    }
    return .values(values)
  }

  private static func appleScriptLiteral(_ value: String) -> String? {
    guard !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
      return nil
    }
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}
