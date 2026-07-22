import AppKit
import Combine
import CoreML
import CreateML
import Foundation
import SiglaunchCore
import XCTest

@testable import SiglaunchApp

final class RecognizerTrainingAdapterTests: XCTestCase {
  func testStratifiedSplitPreservesValidatedSampleLabels() throws {
    let input = makeTrainingInput(samplesPerLabel: 10)

    let split = try CreateMLRecognizerTrainingAdapter.stratifiedSplit(
      input,
      trainingProportion: 0.8,
      seed: 7
    )

    XCTAssertEqual(Set(split.training.keys), Set(PoseDatasetLabel.allCases))
    XCTAssertEqual(Set(split.validation.keys), Set(PoseDatasetLabel.allCases))

    for label in PoseDatasetLabel.allCases {
      let original = Set(
        input.samples
          .filter { $0.label == label }
          .map { URL(fileURLWithPath: $0.imagePath) }
      )
      let training = Set(split.training[label, default: []])
      let validation = Set(split.validation[label, default: []])

      XCTAssertEqual(training.count, 8, "training count for \(label)")
      XCTAssertEqual(validation.count, 2, "validation count for \(label)")
      XCTAssertTrue(training.isDisjoint(with: validation))
      XCTAssertEqual(training.union(validation), original)
    }
  }

  @MainActor
  func testCancellationCompletesFromJobTerminalAndIgnoresLaterProgress() async throws {
    let workspace = try CreateMLTestWorkspace()
    let input = try workspace.makeTrainingInput(samplesPerLabel: 10)
    let jobProgress = Progress(totalUnitCount: 10)
    let resultSubject = PassthroughSubject<TrainedRecognizerModel, any Error>()
    var cancellationCount = 0
    let trainer = CreateMLRecognizerTrainingAdapter(
      outputDirectory: workspace.artifactsDirectory,
      startJob: { _, _ in
        RecognizerTrainingJobHandle(
          progress: jobProgress,
          result: resultSubject.eraseToAnyPublisher(),
          cancel: { cancellationCount += 1 }
        )
      }
    )
    let finished = expectation(description: "cancelled job returned terminal event")
    var result: RecognizerTrainingResult?
    var progressValues: [RecognizerTrainingProgress] = []

    trainer.start(
      with: input,
      progress: { progressValues.append($0) },
      completion: {
        result = $0
        finished.fulfill()
      }
    )
    trainer.cancel()

    XCTAssertNil(result, "cancel must wait for the MLJob terminal result")
    XCTAssertEqual(cancellationCount, 1)
    jobProgress.completedUnitCount = 5
    resultSubject.send(completion: .failure(CancellationError()))
    await fulfillment(of: [finished], timeout: 1)
    XCTAssertEqual(result, .cancelled)

    let countAfterCancellation = progressValues.count
    jobProgress.completedUnitCount = 9
    await Task.yield()
    XCTAssertEqual(progressValues.count, countAfterCancellation)
  }

  @MainActor
  func testCancellationIgnoresClassifierValueUntilPublisherFinishes() async throws {
    let workspace = try CreateMLTestWorkspace()
    let input = try workspace.makeTrainingInput(samplesPerLabel: 10)
    let resultSubject = PassthroughSubject<TrainedRecognizerModel, any Error>()
    let trainer = CreateMLRecognizerTrainingAdapter(
      outputDirectory: workspace.artifactsDirectory,
      startJob: { _, _ in
        RecognizerTrainingJobHandle(
          progress: Progress(totalUnitCount: 10),
          result: resultSubject.eraseToAnyPublisher(),
          cancel: {}
        )
      }
    )
    let completedBeforeTerminal = expectation(
      description: "cancellation did not complete from classifier value"
    )
    completedBeforeTerminal.isInverted = true
    let finished = expectation(description: "publisher terminal completed cancellation")
    let observation = CancellationTestObservation()

    trainer.start(
      with: input,
      progress: { _ in },
      completion: {
        observation.result = $0
        if observation.terminalWasSent {
          finished.fulfill()
        } else {
          completedBeforeTerminal.fulfill()
        }
      }
    )
    trainer.cancel()
    resultSubject.send(
      TrainedRecognizerModel(write: { _ in observation.modelWriteCount += 1 })
    )
    await fulfillment(of: [completedBeforeTerminal], timeout: 0.05)

    observation.terminalWasSent = true
    resultSubject.send(completion: .finished)
    await fulfillment(of: [finished], timeout: 1)
    XCTAssertEqual(observation.result, .cancelled)
    XCTAssertEqual(observation.modelWriteCount, 0)
  }

  @MainActor
  func testLiveCreateMLArtifactCompilesAndReloadsWhenOptedIn() async throws {
    guard
      ProcessInfo.processInfo.environment["SIGLAUNCH_RUN_CREATE_ML_SMOKE"] == "1"
    else {
      throw XCTSkip(
        "Set SIGLAUNCH_RUN_CREATE_ML_SMOKE=1 to run local Create ML training."
      )
    }

    let workspace = try CreateMLTestWorkspace()
    let input = try workspace.makeTrainingInput(samplesPerLabel: 10)
    let trainer = CreateMLRecognizerTrainingAdapter(
      outputDirectory: workspace.artifactsDirectory
    )
    let finished = expectation(description: "Create ML training finished")
    var trainingResult: RecognizerTrainingResult?
    var progressValues: [RecognizerTrainingProgress] = []

    trainer.start(
      with: input,
      progress: { progressValues.append($0) },
      completion: { result in
        trainingResult = result
        finished.fulfill()
      }
    )
    await fulfillment(of: [finished], timeout: 900)

    guard case .succeeded(let artifact) = trainingResult else {
      return XCTFail(
        "expected trained artifact, got \(String(describing: trainingResult))"
      )
    }
    XCTAssertFalse(progressValues.isEmpty)

    let store = PersonalRecognizerStore(rootDirectory: workspace.modelStoreDirectory)
    let saveResult = await store.saveCandidate(from: artifact)
    guard case .succeeded(let candidate) = saveResult else {
      return XCTFail("expected compiled candidate, got \(saveResult)")
    }
    let replacementResult = await store.replaceActiveModel(with: candidate)
    XCTAssertEqual(replacementResult, .succeeded)

    let activeModelURL = workspace.modelStoreDirectory.appendingPathComponent(
      "PersonalRecognizer.mlmodelc",
      isDirectory: true
    )
    _ = try await MLModel.load(contentsOf: activeModelURL)
  }

  private func makeTrainingInput(samplesPerLabel: Int) -> PoseDatasetTrainingInput {
    let root = "/tmp/normalized"
    let samples = PoseDatasetLabel.allCases.flatMap { label in
      (0..<samplesPerLabel).map { index in
        PoseDatasetSample(
          label: label,
          imagePath: "\(root)/unexpected-directory-\(index)/\(label.rawValue).png"
        )
      }
    }
    let labelSummary = PoseDatasetLabelSummary(
      validImageCount: samplesPerLabel,
      handlessImageCount: 0,
      unreadableImageCount: 0
    )
    return PoseDatasetTrainingInput(
      directoryPath: root,
      samples: samples,
      summary: PoseDatasetSummary(
        domainExpansion: labelSummary,
        other: labelSummary
      )
    )!
  }
}

private final class CreateMLTestWorkspace {
  let root: URL
  let artifactsDirectory: URL
  let modelStoreDirectory: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("Siglaunch-CreateMLTests-\(UUID().uuidString)")
    artifactsDirectory = root.appendingPathComponent("artifacts", isDirectory: true)
    modelStoreDirectory = root.appendingPathComponent("models", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
  }

  deinit {
    try? FileManager.default.removeItem(at: root)
  }

  func makeTrainingInput(samplesPerLabel: Int) throws -> PoseDatasetTrainingInput {
    let datasetDirectory = root.appendingPathComponent("normalized", isDirectory: true)
    var samples: [PoseDatasetSample] = []

    for label in PoseDatasetLabel.allCases {
      let labelDirectory = datasetDirectory.appendingPathComponent(
        label.rawValue,
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: labelDirectory,
        withIntermediateDirectories: true
      )
      for index in 0..<samplesPerLabel {
        let imageURL =
          labelDirectory
          .appendingPathComponent("\(index)")
          .appendingPathExtension("png")
        try makeImage(label: label, index: index).write(to: imageURL)
        samples.append(
          PoseDatasetSample(label: label, imagePath: imageURL.path)
        )
      }
    }

    let summary = PoseDatasetLabelSummary(
      validImageCount: samplesPerLabel,
      handlessImageCount: 0,
      unreadableImageCount: 0
    )
    return PoseDatasetTrainingInput(
      directoryPath: datasetDirectory.path,
      samples: samples,
      summary: PoseDatasetSummary(
        domainExpansion: summary,
        other: summary
      )
    )!
  }

  private func makeImage(label: PoseDatasetLabel, index: Int) throws -> Data {
    let width = 224
    let height = 224
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw CreateMLTestImageError.renderingFailed
    }

    let background: NSColor = label == .domainExpansion ? .systemRed : .systemBlue
    context.setFillColor(background.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(NSColor.white.cgColor)
    context.fill(
      CGRect(
        x: 12 + index * 3,
        y: 24 + index * 2,
        width: 48,
        height: 96
      )
    )
    guard let image = context.makeImage() else {
      throw CreateMLTestImageError.renderingFailed
    }
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
      throw CreateMLTestImageError.renderingFailed
    }
    return data
  }
}

@MainActor
private final class CancellationTestObservation {
  var terminalWasSent = false
  var modelWriteCount = 0
  var result: RecognizerTrainingResult?
}

private enum CreateMLTestImageError: Error {
  case renderingFailed
}
