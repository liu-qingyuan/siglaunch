import Foundation
import XCTest

final class InstallSiglaunchTests: XCTestCase {
  func testInstallsReleaseBundleWithRequiredMetadata() throws {
    let fixture = try InstallFixture(testCase: self)

    let result = try fixture.runInstaller()

    XCTAssertEqual(result.status, 0, result.standardError)
    XCTAssertEqual(
      try String(
        contentsOf: fixture.destination
          .appendingPathComponent("Contents/MacOS/Siglaunch"),
        encoding: .utf8
      ),
      "fake release executable\n"
    )
    XCTAssertTrue(
      FileManager.default.isExecutableFile(
        atPath: fixture.destination
          .appendingPathComponent("Contents/MacOS/Siglaunch").path
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: fixture.destination.appendingPathComponent("Contents/Resources").path
      )
    )

    let metadata = try fixture.installedMetadata()
    XCTAssertEqual(metadata["CFBundleExecutable"] as? String, "Siglaunch")
    XCTAssertEqual(metadata["CFBundlePackageType"] as? String, "APPL")
    XCTAssertEqual(
      metadata["CFBundleIdentifier"] as? String,
      "com.liuqingyuan.siglaunch"
    )
    XCTAssertEqual(metadata["CFBundleShortVersionString"] as? String, "0.1.0")
    XCTAssertEqual(metadata["CFBundleVersion"] as? String, "1")
    XCTAssertEqual(metadata["LSMinimumSystemVersion"] as? String, "13.0")
    XCTAssertEqual(metadata["LSUIElement"] as? Bool, true)
    XCTAssertNotNil(metadata["NSCameraUsageDescription"] as? String)

    let toolLog = try fixture.toolLog()
    XCTAssertTrue(toolLog.contains("swift build --package-path"), toolLog)
    XCTAssertTrue(toolLog.contains("--configuration release"), toolLog)
    XCTAssertTrue(toolLog.contains("--product Siglaunch"), toolLog)
    XCTAssertTrue(
      toolLog.contains(
        "codesign --force --options runtime --sign "
          + "Developer ID Application: Fixture (S3YCJDN4GX)"
      ),
      toolLog
    )
    XCTAssertTrue(toolLog.contains("codesign --verify --deep --strict"), toolLog)
    let signingLine = try XCTUnwrap(
      toolLog.split(separator: "\n").first { $0.hasPrefix("codesign --force") }
    )
    XCTAssertTrue(signingLine.hasSuffix(".app"), String(signingLine))
  }

  func testBuildAndRunningProcessPreflightPreserveExistingApp() throws {
    let cases = [
      (
        environment: ["SIGLAUNCH_TEST_SWIFT_STATUS": "70"],
        message: "release build failed"
      ),
      (
        environment: ["SIGLAUNCH_TEST_PGREP_STATUS": "0"],
        message: "Siglaunch is running"
      ),
      (
        environment: ["SIGLAUNCH_TEST_PGREP_STATUS": "2"],
        message: "could not determine whether Siglaunch is running"
      ),
    ]

    for testCase in cases {
      let fixture = try InstallFixture(testCase: self)
      try fixture.installExistingBundle(marker: "previous app")

      let result = try fixture.runInstaller(environment: testCase.environment)

      XCTAssertNotEqual(result.status, 0)
      XCTAssertTrue(result.standardError.contains(testCase.message), result.standardError)
      XCTAssertEqual(try fixture.existingMarker(), "previous app")
      XCTAssertFalse(
        try fixture.toolLog().split(separator: "\n").contains {
          $0.hasPrefix("codesign ")
        }
      )
      XCTAssertTrue(try fixture.siblingArtifacts().isEmpty)
    }
  }

  func testUpdateActivatesVerifiedBundleAndRemovesSiblingBackup() throws {
    let fixture = try InstallFixture(testCase: self)
    try fixture.installExistingBundle(marker: "previous app")

    let result = try fixture.runInstaller()

    XCTAssertEqual(result.status, 0, result.standardError)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.destination.appendingPathComponent("marker").path
      )
    )
    XCTAssertEqual(
      try String(
        contentsOf: fixture.destination
          .appendingPathComponent("Contents/MacOS/Siglaunch"),
        encoding: .utf8
      ),
      "fake release executable\n"
    )
    XCTAssertTrue(try fixture.siblingArtifacts().isEmpty)

    let logLines = try fixture.toolLog().split(separator: "\n")
    let verificationIndex = try XCTUnwrap(
      logLines.firstIndex { $0.hasPrefix("codesign --verify --deep --strict") }
    )
    let firstMoveIndex = try XCTUnwrap(
      logLines.firstIndex { $0.hasPrefix("mv ") }
    )
    XCTAssertLessThan(verificationIndex, firstMoveIndex)
  }

  func testBackupFailureLeavesExistingDestinationUntouched() throws {
    let fixture = try InstallFixture(testCase: self)
    try fixture.installExistingBundle(marker: "previous app")

    let result = try fixture.runInstaller(
      environment: ["SIGLAUNCH_TEST_FAIL_BACKUP": "1"]
    )

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(
      result.standardError.contains("could not move the existing Siglaunch.app"),
      result.standardError
    )
    XCTAssertEqual(try fixture.existingMarker(), "previous app")
    XCTAssertTrue(try fixture.siblingArtifacts().isEmpty)
  }

  func testActivationFailureRestoresPreviousAppAndCleansSiblings() throws {
    let fixture = try InstallFixture(testCase: self)
    try fixture.installExistingBundle(marker: "previous app")

    let result = try fixture.runInstaller(
      environment: ["SIGLAUNCH_TEST_FAIL_ACTIVATION": "1"]
    )

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(
      result.standardError.contains("could not activate the verified Siglaunch.app"),
      result.standardError
    )
    XCTAssertTrue(
      result.standardError.contains("restored the previous Siglaunch.app"),
      result.standardError
    )
    XCTAssertEqual(try fixture.existingMarker(), "previous app")
    XCTAssertTrue(try fixture.siblingArtifacts().isEmpty)
  }

  func testInstallDoesNotTouchApplicationSupportData() throws {
    let fixture = try InstallFixture(testCase: self)
    let sentinel = try fixture.writeApplicationSupportSentinel("personal data")

    let result = try fixture.runInstaller(
      environment: ["HOME": fixture.fakeHome.path]
    )

    XCTAssertEqual(result.status, 0, result.standardError)
    XCTAssertEqual(
      try String(contentsOf: sentinel, encoding: .utf8),
      "personal data"
    )
  }

  func testSigningAndStrictVerificationFailuresPreserveExistingApp() throws {
    let cases = [
      (
        environment: ["SIGLAUNCH_TEST_SIGN_STATUS": "71"],
        message: "Developer ID signing failed"
      ),
      (
        environment: ["SIGLAUNCH_TEST_VERIFY_STATUS": "72"],
        message: "strict signature verification failed"
      ),
    ]

    for testCase in cases {
      let fixture = try InstallFixture(testCase: self)
      try fixture.installExistingBundle(marker: "previous app")

      let result = try fixture.runInstaller(environment: testCase.environment)

      XCTAssertNotEqual(result.status, 0)
      XCTAssertTrue(result.standardError.contains(testCase.message), result.standardError)
      XCTAssertEqual(try fixture.existingMarker(), "previous app")
      XCTAssertTrue(try fixture.siblingArtifacts().isEmpty)
    }
  }

  func testDestinationPreflightRejectsMissingParentAndSymlinkTarget() throws {
    let missingParentFixture = try InstallFixture(testCase: self)
    try missingParentFixture.removeDestinationParent()

    let missingParentResult = try missingParentFixture.runInstaller()

    XCTAssertNotEqual(missingParentResult.status, 0)
    XCTAssertTrue(
      missingParentResult.standardError.contains("destination parent does not exist"),
      missingParentResult.standardError
    )
    XCTAssertTrue(try missingParentFixture.siblingArtifacts(parentMayBeMissing: true).isEmpty)

    let symlinkFixture = try InstallFixture(testCase: self)
    let externalMarker = try symlinkFixture.installSymlinkDestination(
      marker: "external app"
    )

    let symlinkResult = try symlinkFixture.runInstaller()

    XCTAssertNotEqual(symlinkResult.status, 0)
    XCTAssertTrue(
      symlinkResult.standardError.contains("non-symlink App Bundle directory"),
      symlinkResult.standardError
    )
    XCTAssertEqual(try String(contentsOf: externalMarker, encoding: .utf8), "external app")
    XCTAssertTrue(try symlinkFixture.siblingArtifacts().isEmpty)
  }

  func testIdentityToolFailureStopsBeforeTargetReplacement() throws {
    let fixture = try InstallFixture(testCase: self)
    try fixture.installExistingBundle(marker: "previous app")

    let result = try fixture.runInstaller(
      environment: ["SIGLAUNCH_TEST_SECURITY_STATUS": "75"]
    )

    XCTAssertNotEqual(result.status, 0)
    XCTAssertTrue(
      result.standardError.contains("could not query codesigning identities"),
      result.standardError
    )
    XCTAssertEqual(try fixture.existingMarker(), "previous app")
    XCTAssertFalse(
      try fixture.toolLog().split(separator: "\n").contains {
        $0.hasPrefix("codesign ")
      }
    )
    XCTAssertTrue(try fixture.siblingArtifacts().isEmpty)
  }

  func testLiveApplicationsInstallLaunchQuitAndRelaunchWhenExplicitlyAuthorized() throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["SIGLAUNCH_RUN_INSTALL_SMOKE"] == "1" else {
      throw XCTSkip(
        "Set SIGLAUNCH_RUN_INSTALL_SMOKE=1 and the explicit confirmation to replace the live App."
      )
    }
    guard
      environment["SIGLAUNCH_CONFIRM_APPLICATIONS_INSTALL"]
        == "replace /Applications/Siglaunch.app"
    else {
      throw XCTSkip(
        "Set SIGLAUNCH_CONFIRM_APPLICATIONS_INSTALL='replace /Applications/Siglaunch.app' to authorize replacement."
      )
    }

    let installer = repositoryRoot.appendingPathComponent("scripts/install-siglaunch")
    let installation = try runProcess(executable: installer)
    XCTAssertEqual(installation.status, 0, installation.standardError)
    guard installation.status == 0 else { return }

    defer {
      _ = try? runProcess(
        executable: URL(fileURLWithPath: "/usr/bin/osascript"),
        arguments: [
          "-e",
          "tell application id \"com.liuqingyuan.siglaunch\" to quit",
        ]
      )
    }

    let firstOpen = try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/open"),
      arguments: ["-a", "Siglaunch"]
    )
    XCTAssertEqual(firstOpen.status, 0, firstOpen.standardError)
    let firstLaunch = try waitForSiglaunchProcessCount(1)

    let repeatedOpen = try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/open"),
      arguments: ["-a", "Siglaunch"]
    )
    XCTAssertEqual(repeatedOpen.status, 0, repeatedOpen.standardError)
    Thread.sleep(forTimeInterval: 1)
    XCTAssertEqual(try siglaunchProcessIdentifiers(), firstLaunch)

    try quitInstalledSiglaunch()
    _ = try waitForSiglaunchProcessCount(0)

    let secondOpen = try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/open"),
      arguments: ["-a", "Siglaunch"]
    )
    XCTAssertEqual(secondOpen.status, 0, secondOpen.standardError)
    _ = try waitForSiglaunchProcessCount(1)
    try quitInstalledSiglaunch()
    _ = try waitForSiglaunchProcessCount(0)
  }

  func testRequiresExactlyOneMatchingDeveloperIDIdentityBeforeReplacement() throws {
    let cases = [
      (
        output: """
          1) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Developer ID Application: Other Team (AAAAAAAAAA)"
             1 valid identities found
        """,
        message: "no valid Developer ID Application identity"
      ),
      (
        output: """
          1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Developer ID Application: First (S3YCJDN4GX)"
          2) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Developer ID Application: Second (S3YCJDN4GX)"
             2 valid identities found
        """,
        message: "found 2 valid Developer ID Application identities"
      ),
    ]

    for testCase in cases {
      let fixture = try InstallFixture(testCase: self)
      try fixture.installExistingBundle(marker: "previous app")
      try fixture.setSecurityOutput(testCase.output)

      let result = try fixture.runInstaller()

      XCTAssertNotEqual(result.status, 0)
      XCTAssertTrue(result.standardError.contains(testCase.message), result.standardError)
      XCTAssertEqual(try fixture.existingMarker(), "previous app")
      XCTAssertFalse(
        try fixture.toolLog().split(separator: "\n").contains {
          $0.hasPrefix("codesign ")
        }
      )
      XCTAssertTrue(try fixture.siblingArtifacts().isEmpty)
    }
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func quitInstalledSiglaunch() throws {
    let result = try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/osascript"),
      arguments: [
        "-e",
        "tell application id \"com.liuqingyuan.siglaunch\" to quit",
      ]
    )
    XCTAssertEqual(result.status, 0, result.standardError)
  }

  private func waitForSiglaunchProcessCount(
    _ expectedCount: Int,
    timeout: TimeInterval = 15
  ) throws -> [String] {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      let identifiers = try siglaunchProcessIdentifiers()
      if identifiers.count == expectedCount {
        return identifiers
      }
      Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline

    throw InstallTestError.processCountTimeout(expectedCount)
  }

  private func siglaunchProcessIdentifiers() throws -> [String] {
    let result = try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/pgrep"),
      arguments: ["-x", "Siglaunch"]
    )
    if result.status == 1 {
      return []
    }
    guard result.status == 0 else {
      throw InstallTestError.processQueryFailed(result.standardError)
    }
    return result.standardOutput.split(whereSeparator: \.isNewline).map(String.init)
  }

  private func runProcess(
    executable: URL,
    arguments: [String] = []
  ) throws -> InstallResult {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = repositoryRoot
    process.standardOutput = standardOutput
    process.standardError = standardError
    try process.run()
    process.waitUntilExit()
    return InstallResult(
      status: process.terminationStatus,
      standardOutput: String(
        decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
      ),
      standardError: String(
        decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
      )
    )
  }
}

private enum InstallTestError: Error {
  case processCountTimeout(Int)
  case processQueryFailed(String)
}

private struct InstallResult {
  let status: Int32
  let standardOutput: String
  let standardError: String
}

private final class InstallFixture {
  let root: URL
  let destination: URL
  let fakeHome: URL

  private let repositoryRoot: URL
  private let toolsDirectory: URL
  private let releaseBinDirectory: URL
  private let logURL: URL
  private let securityOutputURL: URL
  private let activationFailureMarkerURL: URL

  init(testCase: XCTestCase) throws {
    repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let applicationsDirectory = root.appendingPathComponent(
      "Applications",
      isDirectory: true
    )
    destination = applicationsDirectory.appendingPathComponent(
      "Siglaunch.app",
      isDirectory: true
    )
    fakeHome = root.appendingPathComponent("home", isDirectory: true)
    toolsDirectory = root.appendingPathComponent("tools", isDirectory: true)
    releaseBinDirectory = root.appendingPathComponent("release", isDirectory: true)
    logURL = root.appendingPathComponent("tools.log")
    securityOutputURL = root.appendingPathComponent("security-output.txt")
    activationFailureMarkerURL = root.appendingPathComponent("activation-failed")

    try FileManager.default.createDirectory(
      at: applicationsDirectory,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: toolsDirectory,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: releaseBinDirectory,
      withIntermediateDirectories: true
    )
    try Data("fake release executable\n".utf8).write(
      to: releaseBinDirectory.appendingPathComponent("Siglaunch")
    )
    try setSecurityOutput(
      """
        1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Developer ID Application: Fixture (S3YCJDN4GX)"
           1 valid identities found
      """
    )
    try writeTool(
      named: "swift",
      contents: """
        #!/bin/bash
        set -eu
        printf 'swift %s\\n' "$*" >> "$SIGLAUNCH_TEST_TOOL_LOG"
        if [[ "${SIGLAUNCH_TEST_SWIFT_STATUS:-0}" -ne 0 ]]; then
          exit "$SIGLAUNCH_TEST_SWIFT_STATUS"
        fi
        case " $* " in
          *" --show-bin-path "*) printf '%s\\n' "$SIGLAUNCH_TEST_RELEASE_BIN" ;;
        esac
        """
    )
    try writeTool(
      named: "security",
      contents: """
        #!/bin/bash
        set -eu
        printf 'security %s\\n' "$*" >> "$SIGLAUNCH_TEST_TOOL_LOG"
        if [[ "${SIGLAUNCH_TEST_SECURITY_STATUS:-0}" -ne 0 ]]; then
          exit "$SIGLAUNCH_TEST_SECURITY_STATUS"
        fi
        cat "$SIGLAUNCH_TEST_SECURITY_OUTPUT"
        """
    )
    try writeTool(
      named: "codesign",
      contents: """
        #!/bin/bash
        set -eu
        printf 'codesign %s\\n' "$*" >> "$SIGLAUNCH_TEST_TOOL_LOG"
        case "$1" in
          --force) exit "${SIGLAUNCH_TEST_SIGN_STATUS:-0}" ;;
          --verify) exit "${SIGLAUNCH_TEST_VERIFY_STATUS:-0}" ;;
        esac
        """
    )
    try writeTool(
      named: "pgrep",
      contents: """
        #!/bin/bash
        set -eu
        printf 'pgrep %s\\n' "$*" >> "$SIGLAUNCH_TEST_TOOL_LOG"
        exit "${SIGLAUNCH_TEST_PGREP_STATUS:-1}"
        """
    )
    try writeTool(
      named: "mv",
      contents: """
        #!/bin/bash
        set -eu
        printf 'mv %s\\n' "$*" >> "$SIGLAUNCH_TEST_TOOL_LOG"
        if [[ "${SIGLAUNCH_TEST_FAIL_BACKUP:-0}" == "1" \
          && "$1" == "$SIGLAUNCH_TEST_DESTINATION" \
          && "$2" == *".backup."* ]]; then
          exit 74
        fi
        if [[ "${SIGLAUNCH_TEST_FAIL_ACTIVATION:-0}" == "1" \
          && "$1" == *".staging."* \
          && "$2" == "$SIGLAUNCH_TEST_DESTINATION" \
          && ! -e "$SIGLAUNCH_TEST_ACTIVATION_FAILURE_MARKER" ]]; then
          /usr/bin/touch "$SIGLAUNCH_TEST_ACTIVATION_FAILURE_MARKER"
          exit 73
        fi
        exec /bin/mv "$@"
        """
    )

    testCase.addTeardownBlock { [root] in
      try? FileManager.default.removeItem(at: root)
    }
  }

  func runInstaller(
    environment additionalEnvironment: [String: String] = [:]
  ) throws -> InstallResult {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = repositoryRoot.appendingPathComponent(
      "scripts/install-siglaunch"
    )
    process.arguments = ["--destination", destination.path]
    process.currentDirectoryURL = repositoryRoot
    process.standardOutput = standardOutput
    process.standardError = standardError
    var environment = ProcessInfo.processInfo.environment
    environment.merge(
      [
        "SIGLAUNCH_INSTALL_SWIFT_BIN":
          toolsDirectory
          .appendingPathComponent("swift").path,
        "SIGLAUNCH_INSTALL_SECURITY_BIN":
          toolsDirectory
          .appendingPathComponent("security").path,
        "SIGLAUNCH_INSTALL_CODESIGN_BIN":
          toolsDirectory
          .appendingPathComponent("codesign").path,
        "SIGLAUNCH_INSTALL_PGREP_BIN":
          toolsDirectory
          .appendingPathComponent("pgrep").path,
        "SIGLAUNCH_INSTALL_MV_BIN":
          toolsDirectory
          .appendingPathComponent("mv").path,
        "SIGLAUNCH_TEST_ACTIVATION_FAILURE_MARKER": activationFailureMarkerURL.path,
        "SIGLAUNCH_TEST_DESTINATION": destination.path,
        "SIGLAUNCH_TEST_RELEASE_BIN": releaseBinDirectory.path,
        "SIGLAUNCH_TEST_SECURITY_OUTPUT": securityOutputURL.path,
        "SIGLAUNCH_TEST_TOOL_LOG": logURL.path,
      ],
      uniquingKeysWith: { _, new in new }
    )
    environment.merge(additionalEnvironment, uniquingKeysWith: { _, new in new })
    process.environment = environment

    try process.run()
    process.waitUntilExit()

    return InstallResult(
      status: process.terminationStatus,
      standardOutput: String(
        decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
      ),
      standardError: String(
        decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
      )
    )
  }

  func writeApplicationSupportSentinel(_ contents: String) throws -> URL {
    let directory =
      fakeHome
      .appendingPathComponent("Library/Application Support/Siglaunch", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let sentinel = directory.appendingPathComponent("sentinel")
    try Data(contents.utf8).write(to: sentinel)
    return sentinel
  }

  func setSecurityOutput(_ output: String) throws {
    try Data((output + "\n").utf8).write(to: securityOutputURL)
  }

  func removeDestinationParent() throws {
    try FileManager.default.removeItem(at: destination.deletingLastPathComponent())
  }

  func installSymlinkDestination(marker: String) throws -> URL {
    let externalBundle = root.appendingPathComponent("External.app", isDirectory: true)
    try FileManager.default.createDirectory(
      at: externalBundle,
      withIntermediateDirectories: true
    )
    let markerURL = externalBundle.appendingPathComponent("marker")
    try Data(marker.utf8).write(to: markerURL)
    try FileManager.default.createSymbolicLink(
      at: destination,
      withDestinationURL: externalBundle
    )
    return markerURL
  }

  func installExistingBundle(marker: String) throws {
    try FileManager.default.createDirectory(
      at: destination,
      withIntermediateDirectories: true
    )
    try Data(marker.utf8).write(to: destination.appendingPathComponent("marker"))
  }

  func existingMarker() throws -> String {
    try String(
      contentsOf: destination.appendingPathComponent("marker"),
      encoding: .utf8
    )
  }

  func siblingArtifacts(parentMayBeMissing: Bool = false) throws -> [String] {
    let parent = destination.deletingLastPathComponent()
    if parentMayBeMissing,
      !FileManager.default.fileExists(atPath: parent.path)
    {
      return []
    }
    return try FileManager.default.contentsOfDirectory(
      at: parent,
      includingPropertiesForKeys: nil
    )
    .map(\.lastPathComponent)
    .filter { $0.contains(".staging.") || $0.contains(".backup.") }
  }

  func installedMetadata() throws -> [String: Any] {
    let data = try Data(
      contentsOf: destination.appendingPathComponent("Contents/Info.plist")
    )
    return try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    )
  }

  func toolLog() throws -> String {
    try String(contentsOf: logURL, encoding: .utf8)
  }

  private func writeTool(named name: String, contents: String) throws {
    let url = toolsDirectory.appendingPathComponent(name)
    try Data((contents + "\n").utf8).write(to: url)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: url.path
    )
  }
}
