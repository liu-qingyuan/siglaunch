import CoreML
import Foundation
import SiglaunchCore

@MainActor
protocol PersonalRecognizerStoring: AnyObject {
  var availability: PersonalRecognizerAvailability { get }

  func saveCandidate(
    from artifact: RecognizerTrainingArtifact
  ) async -> PersonalRecognizerCandidateSaveResult

  func replaceActiveModel(
    with candidate: PersonalRecognizerCandidate
  ) async -> PersonalRecognizerReplacementResult
}

@MainActor
final class PersonalRecognizerStore: PersonalRecognizerStoring {
  typealias CompileModel = (URL) async throws -> URL
  typealias ValidateModel = (URL) async throws -> Void
  typealias AtomicReplace = (_ activeURL: URL, _ candidateURL: URL, _ backupName: String) throws ->
    Void

  private let fileManager: FileManager
  private let rootDirectory: URL
  private let compileModel: CompileModel
  private let validateModel: ValidateModel
  private let identifier: () -> String
  private let atomicReplace: AtomicReplace

  private var activeModelURL: URL {
    rootDirectory.appendingPathComponent(
      "PersonalRecognizer.mlmodelc",
      isDirectory: true
    )
  }

  private var candidatesDirectory: URL {
    rootDirectory.appendingPathComponent("Candidates", isDirectory: true)
  }

  init(
    fileManager: FileManager = .default,
    rootDirectory: URL? = nil,
    compileModel: CompileModel? = nil,
    validateModel: ValidateModel? = nil,
    identifier: @escaping () -> String = { UUID().uuidString },
    atomicReplace: AtomicReplace? = nil
  ) {
    self.fileManager = fileManager
    self.rootDirectory =
      rootDirectory
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Siglaunch", isDirectory: true)
    self.compileModel = compileModel ?? { try await MLModel.compileModel(at: $0) }
    self.validateModel =
      validateModel ?? {
        _ = try await MLModel.load(contentsOf: $0)
      }
    self.identifier = identifier
    self.atomicReplace =
      atomicReplace ?? { activeURL, candidateURL, backupName in
        _ = try fileManager.replaceItemAt(
          activeURL,
          withItemAt: candidateURL,
          backupItemName: backupName,
          options: [.withoutDeletingBackupItem]
        )
      }
  }

  var availability: PersonalRecognizerAvailability {
    fileManager.fileExists(atPath: activeModelURL.path) ? .available : .missing
  }

  func saveCandidate(
    from artifact: RecognizerTrainingArtifact
  ) async -> PersonalRecognizerCandidateSaveResult {
    let artifactURL = URL(fileURLWithPath: artifact.path)
    guard fileManager.fileExists(atPath: artifactURL.path) else {
      return .failed(.artifactUnavailable)
    }
    defer { try? fileManager.removeItem(at: artifactURL) }

    do {
      try fileManager.createDirectory(
        at: candidatesDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      return .failed(.storageUnavailable)
    }

    let compiledURL: URL
    do {
      compiledURL = try await compileModel(artifactURL)
    } catch {
      return .failed(.compilationFailed)
    }
    defer {
      if compiledURL.standardizedFileURL != artifactURL.standardizedFileURL {
        try? fileManager.removeItem(at: compiledURL)
      }
    }

    do {
      try await validateModel(compiledURL)
    } catch {
      return .failed(.modelValidationFailed)
    }

    let candidateIdentifier = identifier()
    guard Self.isSafeIdentifier(candidateIdentifier) else {
      return .failed(.storageUnavailable)
    }
    let candidateURL = candidateModelURL(identifier: candidateIdentifier)
    let stagingURL =
      candidatesDirectory
      .appendingPathComponent(".\(candidateIdentifier).staging", isDirectory: true)
      .appendingPathExtension("mlmodelc")
    try? fileManager.removeItem(at: stagingURL)
    try? fileManager.removeItem(at: candidateURL)

    do {
      try fileManager.copyItem(at: compiledURL, to: stagingURL)
    } catch {
      try? fileManager.removeItem(at: stagingURL)
      return .failed(.storageUnavailable)
    }

    do {
      try await validateModel(stagingURL)
    } catch {
      try? fileManager.removeItem(at: stagingURL)
      return .failed(.modelValidationFailed)
    }

    do {
      try fileManager.moveItem(at: stagingURL, to: candidateURL)
    } catch {
      try? fileManager.removeItem(at: stagingURL)
      try? fileManager.removeItem(at: candidateURL)
      return .failed(.storageUnavailable)
    }

    return .succeeded(
      PersonalRecognizerCandidate(identifier: candidateIdentifier)
    )
  }

  func replaceActiveModel(
    with candidate: PersonalRecognizerCandidate
  ) async -> PersonalRecognizerReplacementResult {
    guard Self.isSafeIdentifier(candidate.identifier) else {
      return .failed(.candidateUnavailable)
    }
    let candidateURL = candidateModelURL(identifier: candidate.identifier)
    guard fileManager.fileExists(atPath: candidateURL.path) else {
      return .failed(.candidateUnavailable)
    }

    do {
      try await validateModel(candidateURL)
    } catch {
      try? fileManager.removeItem(at: candidateURL)
      return .failed(.candidateUnavailable)
    }

    guard fileManager.fileExists(atPath: activeModelURL.path) else {
      do {
        try fileManager.moveItem(at: candidateURL, to: activeModelURL)
        return .succeeded
      } catch {
        try? fileManager.removeItem(at: candidateURL)
        return .failed(.replacementFailed)
      }
    }

    let backupName = ".PersonalRecognizer-\(UUID().uuidString).backup.mlmodelc"
    let backupURL = rootDirectory.appendingPathComponent(
      backupName,
      isDirectory: true
    )
    do {
      try atomicReplace(activeModelURL, candidateURL, backupName)
      try? fileManager.removeItem(at: backupURL)
      return .succeeded
    } catch {
      restoreActiveModel(from: backupURL)
      try? fileManager.removeItem(at: candidateURL)
      return .failed(.replacementFailed)
    }
  }

  private func restoreActiveModel(from backupURL: URL) {
    guard fileManager.fileExists(atPath: backupURL.path) else { return }
    guard fileManager.fileExists(atPath: activeModelURL.path) else {
      try? fileManager.moveItem(at: backupURL, to: activeModelURL)
      return
    }

    do {
      _ = try fileManager.replaceItemAt(
        activeModelURL,
        withItemAt: backupURL,
        backupItemName: nil,
        options: []
      )
    } catch {
      let displacedURL = rootDirectory.appendingPathComponent(
        ".failed-replacement-\(UUID().uuidString).mlmodelc",
        isDirectory: true
      )
      do {
        try fileManager.moveItem(at: activeModelURL, to: displacedURL)
        do {
          try fileManager.moveItem(at: backupURL, to: activeModelURL)
          try? fileManager.removeItem(at: displacedURL)
        } catch {
          try? fileManager.moveItem(at: displacedURL, to: activeModelURL)
        }
      } catch {
        return
      }
    }
  }

  private func candidateModelURL(identifier: String) -> URL {
    candidatesDirectory
      .appendingPathComponent(identifier, isDirectory: true)
      .appendingPathExtension("mlmodelc")
  }

  private static func isSafeIdentifier(_ identifier: String) -> Bool {
    !identifier.isEmpty
      && !identifier.contains("/")
      && !identifier.contains("\\")
      && identifier != "."
      && identifier != ".."
  }
}
