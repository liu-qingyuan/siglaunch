public struct RecognizerTrainingProgress: Equatable, Sendable {
  public let completedUnitCount: Int64
  public let totalUnitCount: Int64

  public init(completedUnitCount: Int64, totalUnitCount: Int64) {
    self.completedUnitCount = completedUnitCount
    self.totalUnitCount = totalUnitCount
  }

  public var fractionCompleted: Double {
    guard totalUnitCount > 0 else { return 0 }
    return min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
  }
}

public struct RecognizerTrainingArtifact: Equatable, Sendable {
  public let path: String

  public init(path: String) {
    self.path = path
  }
}

public struct PersonalRecognizerCandidate: Equatable, Sendable {
  public let identifier: String

  public init(identifier: String) {
    self.identifier = identifier
  }
}

public enum RecognizerTrainingAdapterFailure: Equatable, Sendable {
  case invalidTrainingInput
  case trainingFailed
  case outputUnavailable
}

public enum RecognizerTrainingResult: Equatable, Sendable {
  case succeeded(RecognizerTrainingArtifact)
  case failed(RecognizerTrainingAdapterFailure)
  case cancelled
}

public enum PersonalRecognizerCandidateSaveFailure: Equatable, Sendable {
  case artifactUnavailable
  case storageUnavailable
  case compilationFailed
  case modelValidationFailed
}

public enum PersonalRecognizerCandidateSaveResult: Equatable, Sendable {
  case succeeded(PersonalRecognizerCandidate)
  case failed(PersonalRecognizerCandidateSaveFailure)
}

public enum PersonalRecognizerReplacementFailure: Equatable, Sendable {
  case candidateUnavailable
  case replacementFailed
}

public enum PersonalRecognizerReplacementResult: Equatable, Sendable {
  case succeeded
  case failed(PersonalRecognizerReplacementFailure)
}

public enum RecognizerTrainingFailure: Equatable, Sendable {
  case training(RecognizerTrainingAdapterFailure)
  case candidateSave(PersonalRecognizerCandidateSaveFailure)
  case modelReplacement(PersonalRecognizerReplacementFailure)
}

public enum RecognizerTrainingPresentation: Equatable, Sendable {
  case preparing
  case training(RecognizerTrainingProgress?)
  case cancelling
  case saving
  case replacing
  case succeeded
  case cancelled
  case failed(RecognizerTrainingFailure)
}
