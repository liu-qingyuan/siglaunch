import Foundation
import SiglaunchCore
import XCTest

@testable import SiglaunchApp

@MainActor
final class PersonalRecognizerStoreTests: XCTestCase {
  func testSavesValidatedCandidatesAndAtomicallyReplacesActiveModel() async throws {
    let workspace = try TemporaryRecognizerWorkspace()
    let store = makeStore(root: workspace.root)

    let firstArtifact = try workspace.makeArtifact(named: "first", contents: "old-model")
    let firstSave = await store.saveCandidate(
      from: RecognizerTrainingArtifact(path: firstArtifact.path)
    )
    guard case .succeeded(let firstCandidate) = firstSave else {
      return XCTFail("expected first candidate, got \(firstSave)")
    }
    let firstReplacement = await store.replaceActiveModel(with: firstCandidate)
    XCTAssertEqual(firstReplacement, .succeeded)
    XCTAssertEqual(try workspace.activeModelContents(), "old-model")
    XCTAssertEqual(store.availability, .available)

    let secondArtifact = try workspace.makeArtifact(named: "second", contents: "new-model")
    let secondSave = await store.saveCandidate(
      from: RecognizerTrainingArtifact(path: secondArtifact.path)
    )
    guard case .succeeded(let secondCandidate) = secondSave else {
      return XCTFail("expected second candidate, got \(secondSave)")
    }
    let secondReplacement = await store.replaceActiveModel(with: secondCandidate)
    XCTAssertEqual(secondReplacement, .succeeded)
    XCTAssertEqual(try workspace.activeModelContents(), "new-model")
    XCTAssertFalse(FileManager.default.fileExists(atPath: firstArtifact.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: secondArtifact.path))
  }

  func testReplacementFailurePreservesOldActiveModel() async throws {
    let workspace = try TemporaryRecognizerWorkspace()
    let initialStore = makeStore(root: workspace.root)
    let oldArtifact = try workspace.makeArtifact(named: "old", contents: "old-model")
    guard
      case .succeeded(let oldCandidate) = await initialStore.saveCandidate(
        from: RecognizerTrainingArtifact(path: oldArtifact.path)
      )
    else {
      return XCTFail("expected initial candidate")
    }
    let initialReplacement = await initialStore.replaceActiveModel(with: oldCandidate)
    XCTAssertEqual(initialReplacement, .succeeded)

    let failingStore = makeStore(
      root: workspace.root,
      atomicReplace: { activeURL, candidateURL, backupName in
        _ = try FileManager.default.replaceItemAt(
          activeURL,
          withItemAt: candidateURL,
          backupItemName: backupName,
          options: [.withoutDeletingBackupItem]
        )
        throw TestFailure.atomicReplace
      }
    )
    let newArtifact = try workspace.makeArtifact(named: "new", contents: "new-model")
    guard
      case .succeeded(let newCandidate) = await failingStore.saveCandidate(
        from: RecognizerTrainingArtifact(path: newArtifact.path)
      )
    else {
      return XCTFail("expected replacement candidate")
    }

    let failedReplacement = await failingStore.replaceActiveModel(
      with: newCandidate
    )
    XCTAssertEqual(failedReplacement, .failed(.replacementFailed))
    XCTAssertEqual(try workspace.activeModelContents(), "old-model")
    XCTAssertEqual(failingStore.availability, .available)
  }

  func testSaveFailuresNeverModifyActiveModel() async throws {
    let workspace = try TemporaryRecognizerWorkspace()
    try workspace.installActiveModel(contents: "old-model")
    let artifact = try workspace.makeArtifact(named: "candidate", contents: "new-model")
    let store = PersonalRecognizerStore(
      rootDirectory: workspace.root,
      compileModel: { _ in throw TestFailure.compilation },
      validateModel: { _ in },
      identifier: { UUID().uuidString }
    )

    let result = await store.saveCandidate(
      from: RecognizerTrainingArtifact(path: artifact.path)
    )
    XCTAssertEqual(result, .failed(.compilationFailed))
    XCTAssertEqual(try workspace.activeModelContents(), "old-model")
    XCTAssertEqual(store.availability, .available)
  }

  private func makeStore(
    root: URL,
    atomicReplace: PersonalRecognizerStore.AtomicReplace? = nil
  ) -> PersonalRecognizerStore {
    PersonalRecognizerStore(
      rootDirectory: root,
      compileModel: { artifactURL in
        let compiledURL =
          root
          .appendingPathComponent("compiled-\(UUID().uuidString)", isDirectory: true)
          .appendingPathExtension("mlmodelc")
        try FileManager.default.createDirectory(
          at: compiledURL,
          withIntermediateDirectories: true
        )
        let contents = try String(contentsOf: artifactURL, encoding: .utf8)
        try contents.write(
          to: compiledURL.appendingPathComponent("model.marker"),
          atomically: true,
          encoding: .utf8
        )
        return compiledURL
      },
      validateModel: { modelURL in
        guard
          FileManager.default.fileExists(
            atPath: modelURL.appendingPathComponent("model.marker").path
          )
        else {
          throw TestFailure.validation
        }
      },
      identifier: { UUID().uuidString },
      atomicReplace: atomicReplace
    )
  }
}

private enum TestFailure: Error {
  case atomicReplace
  case compilation
  case validation
}

private final class TemporaryRecognizerWorkspace {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("Siglaunch-PersonalRecognizerStoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
  }

  deinit {
    try? FileManager.default.removeItem(at: root)
  }

  func makeArtifact(named name: String, contents: String) throws -> URL {
    let url = root.appendingPathComponent(name).appendingPathExtension("mlmodel")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  func installActiveModel(contents: String) throws {
    let activeURL = root.appendingPathComponent(
      "PersonalRecognizer.mlmodelc",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: activeURL,
      withIntermediateDirectories: true
    )
    try contents.write(
      to: activeURL.appendingPathComponent("model.marker"),
      atomically: true,
      encoding: .utf8
    )
  }

  func activeModelContents() throws -> String {
    try String(
      contentsOf:
        root
        .appendingPathComponent("PersonalRecognizer.mlmodelc", isDirectory: true)
        .appendingPathComponent("model.marker"),
      encoding: .utf8
    )
  }
}
