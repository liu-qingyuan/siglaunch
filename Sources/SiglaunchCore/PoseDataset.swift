public enum PoseDatasetLabel: String, CaseIterable, Equatable, Hashable, Sendable {
  case domainExpansion = "domain_expansion"
  case other
}

public struct PoseDatasetLabelSummary: Equatable, Sendable {
  public let validImageCount: Int
  public let handlessImageCount: Int
  public let unreadableImageCount: Int

  public init(
    validImageCount: Int,
    handlessImageCount: Int,
    unreadableImageCount: Int
  ) {
    self.validImageCount = validImageCount
    self.handlessImageCount = handlessImageCount
    self.unreadableImageCount = unreadableImageCount
  }
}

public struct PoseDatasetSummary: Equatable, Sendable {
  public let domainExpansion: PoseDatasetLabelSummary
  public let other: PoseDatasetLabelSummary

  public init(
    domainExpansion: PoseDatasetLabelSummary,
    other: PoseDatasetLabelSummary
  ) {
    self.domainExpansion = domainExpansion
    self.other = other
  }

  public func summary(for label: PoseDatasetLabel) -> PoseDatasetLabelSummary {
    switch label {
    case .domainExpansion:
      domainExpansion
    case .other:
      other
    }
  }
}

public struct PoseDatasetSample: Equatable, Sendable {
  public let label: PoseDatasetLabel
  public let imagePath: String

  public init(label: PoseDatasetLabel, imagePath: String) {
    self.label = label
    self.imagePath = imagePath
  }
}

public struct PoseDatasetTrainingInput: Equatable, Sendable {
  public static let minimumValidImageCountPerLabel = 10

  public let directoryPath: String
  public let samples: [PoseDatasetSample]
  public let summary: PoseDatasetSummary

  public init?(
    directoryPath: String,
    samples: [PoseDatasetSample],
    summary: PoseDatasetSummary
  ) {
    for label in PoseDatasetLabel.allCases {
      let sampleCount = samples.lazy.filter { $0.label == label }.count
      guard
        sampleCount >= Self.minimumValidImageCountPerLabel,
        sampleCount == summary.summary(for: label).validImageCount
      else {
        return nil
      }
    }

    self.directoryPath = directoryPath
    self.samples = samples
    self.summary = summary
  }
}

public enum PoseDatasetDirectoryFailure: Equatable, Sendable {
  case missing
  case notDirectory
  case unreadable
}

public enum PoseDatasetImportFailure: Equatable, Sendable {
  case rootDirectoryUnavailable(PoseDatasetDirectoryFailure)
  case labelDirectoryUnavailable(
    label: PoseDatasetLabel,
    reason: PoseDatasetDirectoryFailure
  )
  case insufficientValidImages(
    summary: PoseDatasetSummary,
    minimumPerLabel: Int
  )
  case preparationFailed(summary: PoseDatasetSummary)
  case outputUnavailable
}

public enum PoseDatasetFolderSelectionResult: Equatable, Sendable {
  case selected(path: String)
  case cancelled
}

public struct PoseDatasetPreparationProgress: Equatable, Sendable {
  public let label: PoseDatasetLabel
  public let processedImageCount: Int
  public let totalImageCount: Int

  public init(
    label: PoseDatasetLabel,
    processedImageCount: Int,
    totalImageCount: Int
  ) {
    self.label = label
    self.processedImageCount = processedImageCount
    self.totalImageCount = totalImageCount
  }
}

public enum PoseDatasetPreparationResult: Equatable, Sendable {
  case succeeded(PoseDatasetTrainingInput)
  case failed(PoseDatasetImportFailure)
}

public enum PoseDatasetImportPresentation: Equatable, Sendable {
  case choosingFolder
  case validating(PoseDatasetPreparationProgress?)
  case failed(PoseDatasetImportFailure)
  case ready(PoseDatasetTrainingInput)
}
