@preconcurrency import Combine
@preconcurrency import CreateML
import Foundation
import SiglaunchCore

struct RecognizerTrainingSplit {
  let training: [PoseDatasetLabel: [URL]]
  let validation: [PoseDatasetLabel: [URL]]
}

struct TrainedRecognizerModel {
  let write: (URL) throws -> Void
}

struct RecognizerTrainingJobHandle {
  let progress: Progress
  let result: AnyPublisher<TrainedRecognizerModel, any Error>
  let cancel: () -> Void
}

private enum RecognizerTrainingSplitError: Error {
  case invalidProportion
  case invalidResult
}

@MainActor
protocol RecognizerTrainingAdapting: AnyObject {
  func start(
    with input: PoseDatasetTrainingInput,
    progress: @escaping @MainActor @Sendable (RecognizerTrainingProgress) -> Void,
    completion: @escaping @MainActor @Sendable (RecognizerTrainingResult) -> Void
  )

  func cancel()
}

@MainActor
final class CreateMLRecognizerTrainingAdapter: RecognizerTrainingAdapting {
  typealias StartJob = (
    _ trainingData: MLImageClassifier.DataSource,
    _ parameters: MLImageClassifier.ModelParameters
  ) throws -> RecognizerTrainingJobHandle

  private let fileManager: FileManager
  private let outputDirectory: URL
  private let identifier: () -> String
  private let startJob: StartJob
  private var activeJob: RecognizerTrainingJobHandle?
  private var activeTrainingID: Int?
  private var cancellationRequestedForTrainingID: Int?
  private var nextTrainingID = 0
  private var progressObservation: NSKeyValueObservation?
  private var resultCancellable: AnyCancellable?
  private var progressSink: (@MainActor @Sendable (RecognizerTrainingProgress) -> Void)?
  private var completionSink: (@MainActor @Sendable (RecognizerTrainingResult) -> Void)?

  init(
    fileManager: FileManager = .default,
    outputDirectory: URL? = nil,
    identifier: @escaping () -> String = { UUID().uuidString },
    startJob: StartJob? = nil
  ) {
    self.fileManager = fileManager
    self.outputDirectory =
      outputDirectory
      ?? fileManager.temporaryDirectory
      .appendingPathComponent("Siglaunch", isDirectory: true)
      .appendingPathComponent("Recognizer Training", isDirectory: true)
    self.identifier = identifier
    self.startJob =
      startJob ?? { trainingData, parameters in
        let job = try MLImageClassifier.train(
          trainingData: trainingData,
          parameters: parameters
        )
        return RecognizerTrainingJobHandle(
          progress: job.progress,
          result: job.result
            .map(Self.trainedModel)
            .eraseToAnyPublisher(),
          cancel: job.cancel
        )
      }
  }

  func start(
    with input: PoseDatasetTrainingInput,
    progress: @escaping @MainActor @Sendable (RecognizerTrainingProgress) -> Void,
    completion: @escaping @MainActor @Sendable (RecognizerTrainingResult) -> Void
  ) {
    guard activeJob == nil else {
      completion(.failed(.trainingFailed))
      return
    }
    guard input.samples.allSatisfy({ fileManager.isReadableFile(atPath: $0.imagePath) }) else {
      completion(.failed(.invalidTrainingInput))
      return
    }

    let split: RecognizerTrainingSplit
    do {
      split = try Self.stratifiedSplit(input)
    } catch {
      completion(.failed(.invalidTrainingInput))
      return
    }

    let parameters = MLImageClassifier.ModelParameters(
      validation: .dataSource(.filesByLabel(Self.filesByLabel(split.validation))),
      maxIterations: 25,
      augmentation: [.rotation, .exposure],
      algorithm: .transferLearning(
        featureExtractor: .scenePrint(revision: 1),
        classifier: .logisticRegressor
      )
    )

    do {
      let job = try startJob(
        .filesByLabel(Self.filesByLabel(split.training)),
        parameters
      )
      nextTrainingID += 1
      let trainingID = nextTrainingID
      activeJob = job
      activeTrainingID = trainingID
      cancellationRequestedForTrainingID = nil
      progressSink = progress
      completionSink = completion
      observe(job, trainingID: trainingID)
    } catch {
      completion(.failed(.trainingFailed))
    }
  }

  func cancel() {
    guard let activeJob, let activeTrainingID else { return }
    cancellationRequestedForTrainingID = activeTrainingID
    activeJob.cancel()
  }

  nonisolated static func stratifiedSplit(
    _ input: PoseDatasetTrainingInput,
    trainingProportion: Double = 0.8,
    seed: Int = 8
  ) throws -> RecognizerTrainingSplit {
    guard trainingProportion > 0, trainingProportion < 1 else {
      throw RecognizerTrainingSplitError.invalidProportion
    }

    let sourceFiles = Dictionary(grouping: input.samples, by: \.label)
      .mapValues { samples in samples.map { URL(fileURLWithPath: $0.imagePath) } }
    let rawSplits = try MLImageClassifier.DataSource
      .filesByLabel(filesByLabel(sourceFiles))
      .stratifiedSplit(
        proportions: [trainingProportion, 1 - trainingProportion],
        seed: seed
      )
    guard rawSplits.count == 2 else {
      throw RecognizerTrainingSplitError.invalidResult
    }

    let training = try labeledFiles(from: rawSplits[0])
    let validation = try labeledFiles(from: rawSplits[1])
    guard
      Set(training.keys) == Set(PoseDatasetLabel.allCases),
      Set(validation.keys) == Set(PoseDatasetLabel.allCases),
      training.values.allSatisfy({ !$0.isEmpty }),
      validation.values.allSatisfy({ !$0.isEmpty })
    else {
      throw RecognizerTrainingSplitError.invalidResult
    }
    return RecognizerTrainingSplit(training: training, validation: validation)
  }

  private func observe(
    _ job: RecognizerTrainingJobHandle,
    trainingID: Int
  ) {
    progressObservation = job.progress.observe(
      \.fractionCompleted,
      options: [.initial, .new]
    ) { [weak self] progress, _ in
      let completedUnitCount = progress.completedUnitCount
      let totalUnitCount = progress.totalUnitCount
      Task { @MainActor [weak self] in
        self?.sendProgress(
          completedUnitCount: completedUnitCount,
          totalUnitCount: totalUnitCount,
          trainingID: trainingID
        )
      }
    }

    resultCancellable = job.result
      .receive(on: DispatchQueue.main)
      .sink(
        receiveCompletion: { [weak self] completion in
          Task { @MainActor [weak self] in
            switch completion {
            case .finished:
              self?.finishCancellationIfNeeded(trainingID: trainingID)
            case .failure:
              self?.finishJobFailure(trainingID: trainingID)
            }
          }
        },
        receiveValue: { [weak self] classifier in
          Task { @MainActor [weak self] in
            self?.receive(classifier, trainingID: trainingID)
          }
        }
      )
  }

  private func sendProgress(
    completedUnitCount: Int64,
    totalUnitCount: Int64,
    trainingID: Int
  ) {
    guard
      activeTrainingID == trainingID,
      cancellationRequestedForTrainingID != trainingID
    else {
      return
    }
    progressSink?(
      RecognizerTrainingProgress(
        completedUnitCount: completedUnitCount,
        totalUnitCount: totalUnitCount
      )
    )
  }

  private func finishCancellationIfNeeded(trainingID: Int) {
    guard cancellationRequestedForTrainingID == trainingID else { return }
    finish(.cancelled, trainingID: trainingID)
  }

  private func finishJobFailure(trainingID: Int) {
    let result: RecognizerTrainingResult =
      cancellationRequestedForTrainingID == trainingID
      ? .cancelled
      : .failed(.trainingFailed)
    finish(result, trainingID: trainingID)
  }

  private func receive(
    _ model: TrainedRecognizerModel,
    trainingID: Int
  ) {
    guard
      activeTrainingID == trainingID,
      cancellationRequestedForTrainingID != trainingID
    else {
      return
    }
    save(model, trainingID: trainingID)
  }

  private func save(
    _ model: TrainedRecognizerModel,
    trainingID: Int
  ) {
    let artifactURL =
      outputDirectory
      .appendingPathComponent(identifier())
      .appendingPathExtension("mlmodel")
    do {
      try fileManager.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
      )
      try model.write(artifactURL)
      finish(
        .succeeded(RecognizerTrainingArtifact(path: artifactURL.path)),
        trainingID: trainingID
      )
    } catch {
      try? fileManager.removeItem(at: artifactURL)
      finish(.failed(.outputUnavailable), trainingID: trainingID)
    }
  }

  private func finish(
    _ result: RecognizerTrainingResult,
    trainingID: Int
  ) {
    guard activeTrainingID == trainingID, let completionSink else { return }
    self.completionSink = nil
    progressSink = nil
    progressObservation = nil
    resultCancellable = nil
    activeJob = nil
    activeTrainingID = nil
    cancellationRequestedForTrainingID = nil
    completionSink(result)
  }

  nonisolated private static func trainedModel(
    _ classifier: MLImageClassifier
  ) -> TrainedRecognizerModel {
    TrainedRecognizerModel(write: { try classifier.write(to: $0) })
  }

  nonisolated private static func filesByLabel(
    _ files: [PoseDatasetLabel: [URL]]
  ) -> [String: [URL]] {
    Dictionary(uniqueKeysWithValues: files.map { ($0.key.rawValue, $0.value) })
  }

  nonisolated private static func labeledFiles(
    from files: [String: [URL]]
  ) throws -> [PoseDatasetLabel: [URL]] {
    var result: [PoseDatasetLabel: [URL]] = [:]
    for (label, urls) in files {
      guard let label = PoseDatasetLabel(rawValue: label) else {
        throw RecognizerTrainingSplitError.invalidResult
      }
      result[label] = urls
    }
    return result
  }
}
