import Foundation
import SiglaunchCore

@MainActor
struct PersonalRecognizerStore {
  private let fileManager: FileManager
  private let modelURL: URL

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
    modelURL = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)
      .appendingPathComponent("Siglaunch", isDirectory: true)
      .appendingPathComponent("PersonalRecognizer.mlmodelc", isDirectory: true)
  }

  var availability: PersonalRecognizerAvailability {
    fileManager.fileExists(atPath: modelURL.path) ? .available : .missing
  }
}
