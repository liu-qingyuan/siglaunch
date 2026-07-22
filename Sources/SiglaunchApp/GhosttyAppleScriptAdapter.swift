import Foundation
import SiglaunchCore

@MainActor
final class GhosttyAppleScriptAdapter {
  private enum ScriptExecution {
    case values([String])
    case automationFailed(GhosttyAutomationFailure)
  }

  private static let terminalIDKey = "Siglaunch.defaultHerdrTerminalID"

  private let executableResolver: HerdrExecutableResolver
  private let defaults: UserDefaults

  init(
    executableResolver: HerdrExecutableResolver = HerdrExecutableResolver(),
    defaults: UserDefaults = .standard
  ) {
    self.executableResolver = executableResolver
    self.defaults = defaults
  }

  func ensureDefaultHerdrSession(
    completion: @escaping @MainActor @Sendable (DefaultHerdrSessionEnsureResult) -> Void
  ) {
    guard let executablePath = executableResolver.resolve() else {
      completion(.herdrUnavailable)
      return
    }
    guard
      let source = Self.source(
        herdrExecutablePath: executablePath,
        knownTerminalID: knownTerminalID
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
        defaults.set(values[1], forKey: Self.terminalIDKey)
        completion(.ready(.reused))
      case "pending":
        defaults.set(values[1], forKey: Self.terminalIDKey)
        waitForHerdr(terminalID: values[1], completion: completion)
      default:
        completion(.automationFailed(.unavailable))
      }
    case .automationFailed(let failure):
      completion(.automationFailed(failure))
    }
  }

  static func source(
    herdrExecutablePath: String,
    knownTerminalID: String?
  ) -> String? {
    guard
      let environmentLiteral = appleScriptLiteral(
        "SIGLAUNCH_HERDR_PATH=\(herdrExecutablePath)"
      ),
      let terminalIDLiteral = appleScriptLiteral(knownTerminalID ?? "")
    else {
      return nil
    }

    return #"""
      tell application id "com.mitchellh.ghostty"
        -- A title alone cannot distinguish default and named Herdr Sessions.
        set knownTerminalID to \#(terminalIDLiteral)
        if knownTerminalID is not "" then
          repeat with candidateTerminal in terminals
            if (id of candidateTerminal) is knownTerminalID then
              if (name of candidateTerminal) is "herdr" then
                focus candidateTerminal
                return {"reused", knownTerminalID}
              end if
              return {"pending", knownTerminalID}
            end if
          end repeat
        end if

        set sessionConfiguration to new surface configuration
        set environment variables of sessionConfiguration to {\#(environmentLiteral)}
        set command of sessionConfiguration to "exec \"$SIGLAUNCH_HERDR_PATH\""
        set wait after command of sessionConfiguration to true
        set createdWindow to new window with configuration sessionConfiguration
        set createdTerminal to terminal 1 of createdWindow
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
            if (name of candidateTerminal) is "herdr" then
              return {"ready", expectedTerminalID}
            end if
            return {"waiting", expectedTerminalID}
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

  private var knownTerminalID: String? {
    guard
      let value = defaults.string(forKey: Self.terminalIDKey),
      UUID(uuidString: value) != nil
    else {
      return nil
    }
    return value
  }

  private func waitForHerdr(
    terminalID: String,
    completion: @escaping @MainActor @Sendable (DefaultHerdrSessionEnsureResult) -> Void
  ) {
    Task { @MainActor in
      for _ in 0..<50 {
        do {
          try await Task.sleep(for: .milliseconds(100))
        } catch {
          completion(.herdrUnavailable)
          return
        }

        guard let source = Self.readinessSource(terminalID: terminalID) else {
          completion(.automationFailed(.unavailable))
          return
        }
        switch execute(source) {
        case .values(let values):
          guard values.count == 2, values[1] == terminalID else {
            completion(.automationFailed(.unavailable))
            return
          }
          switch values[0] {
          case "ready":
            defaults.set(terminalID, forKey: Self.terminalIDKey)
            completion(.ready(.started))
            return
          case "waiting":
            continue
          case "missing":
            defaults.removeObject(forKey: Self.terminalIDKey)
            completion(.herdrUnavailable)
            return
          default:
            completion(.automationFailed(.unavailable))
            return
          }
        case .automationFailed(let failure):
          completion(.automationFailed(failure))
          return
        }
      }
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
