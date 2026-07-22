import Foundation
import SiglaunchCore
import XCTest

@testable import SiglaunchApp

final class WorkflowConfigurationStoreTests: XCTestCase {
  func testLoadsExactStructuredWorkspaceAndPiCommand() throws {
    let configurationURL = try writeConfiguration(
      """
      {
        "workspace": {"path": "/Users/developer/work/siglaunch"},
        "pi": {"command": ["pi", "--model", "gpt-5"]}
      }
      """
    )

    XCTAssertEqual(
      WorkflowConfigurationStore(configurationURL: configurationURL).load(),
      .loaded(
        WorkflowConfiguration(
          workspacePath: "/Users/developer/work/siglaunch",
          piCommand: ["pi", "--model", "gpt-5"]
        )
      )
    )
  }

  func testRejectsUnavailableMalformedAndNonExactConfiguration() throws {
    let unavailableURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("workflow.json")
    XCTAssertEqual(
      WorkflowConfigurationStore(configurationURL: unavailableURL).load(),
      .failed(.unavailable)
    )

    let cases: [(contents: String, failure: WorkflowConfigurationFailure)] = [
      ("not json", .malformed),
      ("[]", .invalidStructure),
      ("{}", .invalidStructure),
      (
        """
        {"workspace":{"path":"/workspace"},"pi":{"command":["pi"]},"extra":true}
        """,
        .invalidStructure
      ),
      (
        """
        {"workspace":{"path":"/workspace","extra":true},"pi":{"command":["pi"]}}
        """,
        .invalidStructure
      ),
      (
        """
        {"workspace":{"path":"/workspace"},"pi":{"command":["pi"],"extra":true}}
        """,
        .invalidStructure
      ),
      (
        """
        {"workspace":{"path":42},"pi":{"command":["pi"]}}
        """,
        .invalidStructure
      ),
      (
        """
        {"workspace":{"path":"/workspace"},"pi":{"command":"pi --model gpt-5"}}
        """,
        .invalidStructure
      ),
      (
        """
        {"workspace":{"path":"/workspace"},"pi":{"command":["pi",42]}}
        """,
        .invalidStructure
      ),
      (
        """
        {"workspace":{"path":"  "},"pi":{"command":["pi"]}}
        """,
        .emptyWorkspacePath
      ),
      (
        """
        {"workspace":{"path":"/workspace"},"pi":{"command":[]}}
        """,
        .emptyPiCommand
      ),
    ]

    for testCase in cases {
      let configurationURL = try writeConfiguration(testCase.contents)
      XCTAssertEqual(
        WorkflowConfigurationStore(configurationURL: configurationURL).load(),
        .failed(testCase.failure),
        testCase.contents
      )
    }
  }

  private func writeConfiguration(_ contents: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directory)
    }

    let url = directory.appendingPathComponent("workflow.json")
    try Data(contents.utf8).write(to: url)
    return url
  }
}
