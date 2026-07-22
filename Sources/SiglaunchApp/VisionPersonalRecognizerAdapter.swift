import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation
import SiglaunchCore
import Vision

protocol PersonalRecognizerClassifying: AnyObject, Sendable {
  func classify(_ image: CGImage) throws -> [PersonalRecognizerClassification]
  func reset()
}

final class CoreMLPersonalRecognizerClassifier:
  PersonalRecognizerClassifying,
  @unchecked Sendable
{
  typealias LoadModel = (URL) throws -> VNCoreMLModel

  private enum ModelCache {
    case unloaded
    case loading
    case loaded(VNCoreMLModel)
    case unavailable
  }

  private let activeModelURL: URL
  private let loadModel: LoadModel
  private let lock = NSLock()
  private var modelCache: ModelCache = .unloaded
  private var modelGeneration: UInt64 = 0

  init(
    fileManager: FileManager = .default,
    rootDirectory: URL? = nil,
    loadModel: LoadModel? = nil
  ) {
    let rootDirectory =
      rootDirectory
      ?? PersonalRecognizerStorageLocation.defaultRootDirectory(
        fileManager: fileManager
      )
    activeModelURL = PersonalRecognizerStorageLocation.activeModelURL(
      in: rootDirectory
    )
    self.loadModel =
      loadModel ?? { url in
        let model = try MLModel(
          contentsOf: url,
          configuration: MLModelConfiguration()
        )
        return try VNCoreMLModel(for: model)
      }
  }

  func classify(
    _ image: CGImage
  ) throws -> [PersonalRecognizerClassification] {
    let request = VNCoreMLRequest(model: try model())
    request.imageCropAndScaleOption = .scaleFill
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
    try handler.perform([request])
    guard
      let observations = request.results as? [VNClassificationObservation],
      !observations.isEmpty
    else {
      throw PersonalRecognizerInferenceError.missingClassifications
    }
    return observations.map {
      PersonalRecognizerClassification(
        label: $0.identifier,
        confidence: Double($0.confidence)
      )
    }
  }

  func reset() {
    lock.lock()
    modelGeneration &+= 1
    modelCache = .unloaded
    lock.unlock()
  }

  private func model() throws -> VNCoreMLModel {
    let loadGeneration: UInt64
    lock.lock()
    switch modelCache {
    case .loaded(let model):
      lock.unlock()
      return model
    case .loading, .unavailable:
      lock.unlock()
      throw PersonalRecognizerInferenceError.modelUnavailable
    case .unloaded:
      loadGeneration = modelGeneration
      modelCache = .loading
      lock.unlock()
    }

    do {
      let visionModel = try loadModel(activeModelURL)
      lock.lock()
      if modelGeneration == loadGeneration {
        modelCache = .loaded(visionModel)
      }
      lock.unlock()
      return visionModel
    } catch {
      lock.lock()
      if modelGeneration == loadGeneration {
        modelCache = .unavailable
      }
      lock.unlock()
      throw error
    }
  }
}

final class VisionPersonalRecognizerAnalyzer:
  VisionDiagnosticAnalyzing,
  @unchecked Sendable
{
  private let diagnosticAnalyzer: VisionHandDiagnosticAnalyzer
  private let handCropPath: any DetectedHandCropNormalizing
  private let classifier: any PersonalRecognizerClassifying
  private let imageContext: CIContext

  init(
    diagnosticAnalyzer: VisionHandDiagnosticAnalyzer = VisionHandDiagnosticAnalyzer(),
    handCropPath: any DetectedHandCropNormalizing = VisionHandCropAdapter(),
    classifier: any PersonalRecognizerClassifying = CoreMLPersonalRecognizerClassifier(),
    imageContext: CIContext = CIContext()
  ) {
    self.diagnosticAnalyzer = diagnosticAnalyzer
    self.handCropPath = handCropPath
    self.classifier = classifier
    self.imageContext = imageContext
  }

  func makeAnalysis(
    pixelBuffer: CVPixelBuffer
  ) -> any VisionDiagnosticAnalysis {
    VisionPersonalRecognizerAnalysis(
      pixelBuffer: pixelBuffer,
      diagnosticAnalyzer: diagnosticAnalyzer,
      handCropPath: handCropPath,
      classifier: classifier,
      imageContext: imageContext
    )
  }

  func reset() {
    classifier.reset()
  }
}

private final class VisionPersonalRecognizerAnalysis:
  VisionDiagnosticAnalysis,
  @unchecked Sendable
{
  private let pixelBuffer: CVPixelBuffer
  private let diagnosticAnalyzer: VisionHandDiagnosticAnalyzer
  private let handCropPath: any DetectedHandCropNormalizing
  private let classifier: any PersonalRecognizerClassifying
  private let imageContext: CIContext
  private let request: VNDetectHumanHandPoseRequest
  private let cancellationLock = NSLock()
  private var isCancelled = false

  init(
    pixelBuffer: CVPixelBuffer,
    diagnosticAnalyzer: VisionHandDiagnosticAnalyzer,
    handCropPath: any DetectedHandCropNormalizing,
    classifier: any PersonalRecognizerClassifying,
    imageContext: CIContext
  ) {
    self.pixelBuffer = pixelBuffer
    self.diagnosticAnalyzer = diagnosticAnalyzer
    self.handCropPath = handCropPath
    self.classifier = classifier
    self.imageContext = imageContext
    request = VNDetectHumanHandPoseRequest()
    request.maximumHandCount = 1
  }

  func perform() -> VisionRecognitionResult {
    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
    guard
      let image = imageContext.createCGImage(
        inputImage,
        from: inputImage.extent
      )
    else {
      return failedResult()
    }

    let observation: VNHumanHandPoseObservation?
    let diagnostic: DiagnosticGestureResult
    do {
      let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
      try handler.perform([request])
      observation = request.results?.first
      diagnostic = try diagnosticAnalyzer.diagnosticResult(from: observation)
    } catch {
      return failedResult()
    }
    guard !cancelled else {
      return VisionRecognitionResult(
        diagnosticGesture: diagnostic,
        personalRecognizerResult: .failed
      )
    }
    guard let observation else {
      return VisionRecognitionResult(
        diagnosticGesture: diagnostic,
        personalRecognizerResult: .noHandDetected
      )
    }

    let normalizedHand: CGImage?
    do {
      normalizedHand = try handCropPath.normalizedCrop(
        from: image,
        detectedHand: observation
      )
    } catch {
      return VisionRecognitionResult(
        diagnosticGesture: diagnostic,
        personalRecognizerResult: .failed
      )
    }
    guard let normalizedHand else {
      return VisionRecognitionResult(
        diagnosticGesture: diagnostic,
        personalRecognizerResult: .failed
      )
    }
    do {
      return VisionRecognitionResult(
        diagnosticGesture: diagnostic,
        personalRecognizerResult: .classified(
          try classifier.classify(normalizedHand)
        )
      )
    } catch {
      return VisionRecognitionResult(
        diagnosticGesture: diagnostic,
        personalRecognizerResult: .failed
      )
    }
  }

  func cancel() {
    cancellationLock.lock()
    isCancelled = true
    cancellationLock.unlock()
    request.cancel()
  }

  private func failedResult() -> VisionRecognitionResult {
    VisionRecognitionResult(
      diagnosticGesture: DiagnosticGestureResult(
        handDetection: .analysisFailed,
        recognizedJointCount: 0,
        extendedFingerCount: 0,
        isOpenPalm: false
      ),
      personalRecognizerResult: .failed
    )
  }

  private var cancelled: Bool {
    cancellationLock.lock()
    defer { cancellationLock.unlock() }
    return isCancelled
  }
}

private enum PersonalRecognizerInferenceError: Error {
  case missingClassifications
  case modelUnavailable
}
