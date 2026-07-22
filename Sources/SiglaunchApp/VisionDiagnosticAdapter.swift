import CoreGraphics
import CoreVideo
import SiglaunchCore
import Vision

@MainActor
protocol RecognitionAdapting: AnyObject {
  func receive(_ frame: CapturedRecognitionFrame)
  func execute(
    _ effect: RecognitionEffect,
    eventSink: @escaping @MainActor @Sendable (RecognitionFrameCompletion) -> Void
  )
  func reset()
}

struct VisionRecognitionResult: Equatable, Sendable {
  let diagnosticGesture: DiagnosticGestureResult
  let personalRecognizerResult: PersonalRecognizerInferenceResult
}

protocol VisionDiagnosticAnalysis: AnyObject, Sendable {
  func perform() -> VisionRecognitionResult
  func cancel()
}

protocol VisionDiagnosticAnalyzing: Sendable {
  func makeAnalysis(pixelBuffer: CVPixelBuffer) -> any VisionDiagnosticAnalysis
  func reset()
}

extension VisionDiagnosticAnalyzing {
  func reset() {}
}

final class SerialVisionDiagnosticExecutor: @unchecked Sendable {
  private let queue = DispatchQueue(
    label: "com.siglaunch.vision-diagnostics",
    qos: .userInitiated
  )

  func perform(
    _ analysis: any VisionDiagnosticAnalysis
  ) async -> VisionRecognitionResult {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(returning: analysis.perform())
      }
    }
  }
}

@MainActor
final class VisionDiagnosticAdapter: RecognitionAdapting {
  private final class PixelBufferBox: @unchecked Sendable {
    let value: CVPixelBuffer

    init(_ value: CVPixelBuffer) {
      self.value = value
    }
  }

  private let analyzer: any VisionDiagnosticAnalyzing
  private let executor: SerialVisionDiagnosticExecutor
  private var frames: [RecognitionFrameReference: PixelBufferBox] = [:]
  private var activeAnalysis: (any VisionDiagnosticAnalysis)?
  private var analysisTask: Task<Void, Never>?

  init(
    analyzer: any VisionDiagnosticAnalyzing = VisionPersonalRecognizerAnalyzer(),
    executor: SerialVisionDiagnosticExecutor = SerialVisionDiagnosticExecutor()
  ) {
    self.analyzer = analyzer
    self.executor = executor
  }

  deinit {
    activeAnalysis?.cancel()
    analysisTask?.cancel()
  }

  func receive(_ frame: CapturedRecognitionFrame) {
    frames[frame.reference] = PixelBufferBox(frame.pixelBuffer)
  }

  func execute(
    _ effect: RecognitionEffect,
    eventSink: @escaping @MainActor @Sendable (RecognitionFrameCompletion) -> Void
  ) {
    switch effect {
    case .discardFrame(let reference):
      frames.removeValue(forKey: reference)
    case .analyzeFrame(let reference):
      guard let pixelBuffer = frames.removeValue(forKey: reference) else {
        return
      }
      let analysis = analyzer.makeAnalysis(pixelBuffer: pixelBuffer.value)
      activeAnalysis = analysis
      let executor = executor
      analysisTask = Task { [weak self] in
        let result = await executor.perform(analysis)
        guard !Task.isCancelled else { return }
        eventSink(
          RecognitionFrameCompletion(
            frame: reference,
            diagnosticGesture: result.diagnosticGesture,
            personalRecognizerResult: result.personalRecognizerResult
          )
        )
        if self?.activeAnalysis === analysis {
          self?.activeAnalysis = nil
          self?.analysisTask = nil
        }
      }
    }
  }

  func reset() {
    frames.removeAll()
    activeAnalysis?.cancel()
    activeAnalysis = nil
    analysisTask?.cancel()
    analysisTask = nil
    analyzer.reset()
  }
}

final class VisionHandDiagnosticAnalyzer: VisionDiagnosticAnalyzing, @unchecked Sendable {
  private typealias JointName = VNHumanHandPoseObservation.JointName

  private let minimumJointConfidence: VNConfidence

  init(minimumJointConfidence: VNConfidence = 0.2) {
    self.minimumJointConfidence = max(0, min(minimumJointConfidence, 1))
  }

  func makeAnalysis(
    pixelBuffer: CVPixelBuffer
  ) -> any VisionDiagnosticAnalysis {
    VisionHandDiagnosticAnalysis(
      analyzer: self,
      pixelBuffer: pixelBuffer
    )
  }

  func analyze(cgImage: CGImage) throws -> DiagnosticGestureResult {
    let request = makeRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
    try handler.perform([request])
    return try diagnosticResult(from: request.results?.first)
  }

  func analyze(pixelBuffer: CVPixelBuffer) throws -> DiagnosticGestureResult {
    try analyze(pixelBuffer: pixelBuffer, request: makeRequest())
  }

  fileprivate func analyze(
    pixelBuffer: CVPixelBuffer,
    request: VNDetectHumanHandPoseRequest
  ) throws -> DiagnosticGestureResult {
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
    try handler.perform([request])
    return try diagnosticResult(from: request.results?.first)
  }

  private func makeRequest() -> VNDetectHumanHandPoseRequest {
    let request = VNDetectHumanHandPoseRequest()
    request.maximumHandCount = 1
    return request
  }

  func diagnosticResult(
    from observation: VNHumanHandPoseObservation?
  ) throws -> DiagnosticGestureResult {
    guard let observation else {
      return DiagnosticGestureResult(
        handDetection: .notDetected,
        recognizedJointCount: 0,
        extendedFingerCount: 0,
        isOpenPalm: false
      )
    }

    let recognizedPoints = try observation.recognizedPoints(.all)
    let confidentPoints = recognizedPoints.filter {
      $0.value.confidence >= minimumJointConfidence
    }
    let extendedFingerCount = extendedFingerChains.reduce(into: 0) {
      count, chain in
      if isExtended(chain, points: confidentPoints) {
        count += 1
      }
    }

    return DiagnosticGestureResult(
      handDetection: .detected,
      recognizedJointCount: confidentPoints.count,
      extendedFingerCount: extendedFingerCount,
      isOpenPalm: extendedFingerCount == extendedFingerChains.count
    )
  }

  private func isExtended(
    _ chain: (tip: JointName, middle: JointName, base: JointName),
    points: [JointName: VNRecognizedPoint]
  ) -> Bool {
    guard
      let wrist = points[.wrist],
      let tip = points[chain.tip],
      let middle = points[chain.middle],
      let base = points[chain.base]
    else { return false }

    let tipDistance = distance(from: wrist.location, to: tip.location)
    let middleDistance = distance(from: wrist.location, to: middle.location)
    let baseDistance = distance(from: wrist.location, to: base.location)
    return tipDistance > middleDistance * 1.05
      && middleDistance > baseDistance * 1.02
  }

  private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
    hypot(first.x - second.x, first.y - second.y)
  }

  private var extendedFingerChains: [(tip: JointName, middle: JointName, base: JointName)] {
    [
      (.thumbTip, .thumbIP, .thumbMP),
      (.indexTip, .indexPIP, .indexMCP),
      (.middleTip, .middlePIP, .middleMCP),
      (.ringTip, .ringPIP, .ringMCP),
      (.littleTip, .littlePIP, .littleMCP),
    ]
  }
}

private final class VisionHandDiagnosticAnalysis: VisionDiagnosticAnalysis,
  @unchecked Sendable
{
  private let analyzer: VisionHandDiagnosticAnalyzer
  private let pixelBuffer: CVPixelBuffer
  private let request: VNDetectHumanHandPoseRequest

  init(
    analyzer: VisionHandDiagnosticAnalyzer,
    pixelBuffer: CVPixelBuffer
  ) {
    self.analyzer = analyzer
    self.pixelBuffer = pixelBuffer
    request = VNDetectHumanHandPoseRequest()
    request.maximumHandCount = 1
  }

  func perform() -> VisionRecognitionResult {
    let diagnosticGesture: DiagnosticGestureResult
    do {
      diagnosticGesture = try analyzer.analyze(
        pixelBuffer: pixelBuffer,
        request: request
      )
    } catch {
      diagnosticGesture = DiagnosticGestureResult(
        handDetection: .analysisFailed,
        recognizedJointCount: 0,
        extendedFingerCount: 0,
        isOpenPalm: false
      )
    }
    let personalRecognizerResult: PersonalRecognizerInferenceResult =
      diagnosticGesture.handDetection == .notDetected
      ? .noHandDetected
      : .failed
    return VisionRecognitionResult(
      diagnosticGesture: diagnosticGesture,
      personalRecognizerResult: personalRecognizerResult
    )
  }

  func cancel() {
    request.cancel()
  }
}
