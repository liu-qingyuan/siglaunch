import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import SiglaunchCore
import Vision
import XCTest

@testable import SiglaunchApp

final class VisionDiagnosticAdapterTests: XCTestCase {
  func testRealVisionDistinguishesOpenPalmFromClosedFist() throws {
    let analyzer = VisionHandDiagnosticAnalyzer()

    let openPalm = try analyzer.analyze(cgImage: loadFixture(named: "open-palm"))
    let closedFist = try analyzer.analyze(cgImage: loadFixture(named: "closed-fist"))

    XCTAssertEqual(openPalm.handDetection, .detected)
    XCTAssertGreaterThanOrEqual(openPalm.recognizedJointCount, 15)
    XCTAssertEqual(openPalm.extendedFingerCount, 5)
    XCTAssertTrue(openPalm.isOpenPalm)

    XCTAssertEqual(closedFist.handDetection, .detected)
    XCTAssertGreaterThanOrEqual(closedFist.recognizedJointCount, 10)
    XCTAssertLessThan(closedFist.extendedFingerCount, 5)
    XCTAssertFalse(closedFist.isOpenPalm)
  }

  @MainActor
  func testProductionAdapterCompletesRealVisionFixtureAnalysis() async throws {
    let adapter = VisionDiagnosticAdapter()
    let cases: [(fixture: String, openPalm: Bool)] = [
      ("open-palm", true),
      ("closed-fist", false),
    ]

    for (index, testCase) in cases.enumerated() {
      let reference = RecognitionFrameReference(
        lifecycleID: RecognitionLifecycleID(rawValue: 1),
        sequenceNumber: UInt64(index + 1)
      )
      adapter.receive(
        CapturedRecognitionFrame(
          reference: reference,
          pixelBuffer: try pixelBuffer(
            from: loadFixture(named: testCase.fixture)
          )
        )
      )
      let completed = expectation(description: "\(testCase.fixture) completed")
      var observedCompletion: RecognitionAnalysis?

      adapter.execute(.analyzeFrame(reference)) { completion in
        observedCompletion = completion
        completed.fulfill()
      }
      await fulfillment(of: [completed], timeout: 3)

      XCTAssertEqual(observedCompletion?.frame, reference)
      XCTAssertEqual(
        observedCompletion?.diagnosticGesture.handDetection,
        .detected
      )
      XCTAssertEqual(
        observedCompletion?.diagnosticGesture.isOpenPalm,
        testCase.openPalm
      )
    }
  }

  @MainActor
  func testRealVisionCropFeedsPersonalRecognizerAndReturnsClassifications() async throws {
    let classifier = RecordingPersonalRecognizerClassifier(
      classifications: [
        PersonalRecognizerClassification(
          label: "domain_expansion",
          confidence: 0.9
        ),
        PersonalRecognizerClassification(label: "other", confidence: 0.1),
      ]
    )
    let adapter = VisionDiagnosticAdapter(
      analyzer: VisionPersonalRecognizerAnalyzer(classifier: classifier)
    )
    let reference = RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: 1),
      sequenceNumber: 1
    )
    let cameraImage = try loadFixture(named: "open-palm")
    adapter.receive(
      CapturedRecognitionFrame(
        reference: reference,
        pixelBuffer: try pixelBuffer(from: cameraImage)
      )
    )
    let completed = expectation(description: "Vision and classifier completed")
    var observedAnalysis: RecognitionAnalysis?

    adapter.execute(.analyzeFrame(reference)) { analysis in
      observedAnalysis = analysis
      completed.fulfill()
    }
    await fulfillment(of: [completed], timeout: 3)

    XCTAssertEqual(observedAnalysis?.frame, reference)
    XCTAssertEqual(observedAnalysis?.cameraImage?.width, cameraImage.width)
    XCTAssertEqual(observedAnalysis?.cameraImage?.height, cameraImage.height)
    XCTAssertEqual(observedAnalysis?.normalizedCrop?.width, 224)
    XCTAssertEqual(observedAnalysis?.normalizedCrop?.height, 224)
    XCTAssertEqual(classifier.imageSizes, [CGSize(width: 224, height: 224)])
    XCTAssertEqual(
      observedAnalysis?.personalRecognizerResult,
      .classified(classifier.classifications)
    )
  }

  func testCoreMLModelLoadFailureIsRetriedOnlyAfterReset() throws {
    var loadAttemptCount = 0
    let classifier = CoreMLPersonalRecognizerClassifier(
      rootDirectory: URL(fileURLWithPath: "/missing-model-root"),
      loadModel: { _ in
        loadAttemptCount += 1
        throw FailingPersonalRecognizerError.expected
      }
    )
    let image = try blankImage()

    XCTAssertThrowsError(try classifier.classify(image))
    XCTAssertThrowsError(try classifier.classify(image))
    XCTAssertEqual(loadAttemptCount, 1)

    classifier.reset()
    XCTAssertThrowsError(try classifier.classify(image))
    XCTAssertEqual(loadAttemptCount, 2)
  }

  func testResetDoesNotWaitForInFlightModelLoad() throws {
    let loadStarted = expectation(description: "model load started")
    let resetFinished = expectation(description: "reset finished")
    let classificationFinished = expectation(description: "classification finished")
    let allowLoadToFinish = DispatchSemaphore(value: 0)
    let classifier = CoreMLPersonalRecognizerClassifier(
      rootDirectory: URL(fileURLWithPath: "/missing-model-root"),
      loadModel: { _ in
        loadStarted.fulfill()
        allowLoadToFinish.wait()
        throw FailingPersonalRecognizerError.expected
      }
    )
    let image = try blankImage()

    DispatchQueue.global().async {
      _ = try? classifier.classify(image)
      classificationFinished.fulfill()
    }
    wait(for: [loadStarted], timeout: 1)
    DispatchQueue.global().async {
      classifier.reset()
      resetFinished.fulfill()
    }

    let resetResult = XCTWaiter.wait(for: [resetFinished], timeout: 0.1)
    allowLoadToFinish.signal()
    wait(for: [classificationFinished], timeout: 1)
    XCTAssertEqual(resetResult, .completed)
  }

  @MainActor
  func testProductionAnalyzerReportsNoHandWithoutClassifying() async throws {
    let classifier = RecordingPersonalRecognizerClassifier(classifications: [])
    let adapter = VisionDiagnosticAdapter(
      analyzer: VisionPersonalRecognizerAnalyzer(classifier: classifier)
    )
    let reference = RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: 1),
      sequenceNumber: 1
    )
    adapter.receive(
      CapturedRecognitionFrame(
        reference: reference,
        pixelBuffer: try pixelBuffer(from: blankImage())
      )
    )
    let completed = expectation(description: "handless frame completed")
    var observedCompletion: RecognitionAnalysis?

    adapter.execute(.analyzeFrame(reference)) { completion in
      observedCompletion = completion
      completed.fulfill()
    }
    await fulfillment(of: [completed], timeout: 3)

    XCTAssertEqual(observedCompletion?.diagnosticGesture.handDetection, .notDetected)
    XCTAssertEqual(observedCompletion?.personalRecognizerResult, .noHandDetected)
    XCTAssertNotNil(observedCompletion?.cameraImage)
    XCTAssertNil(observedCompletion?.normalizedCrop)
    XCTAssertTrue(classifier.imageSizes.isEmpty)
  }

  @MainActor
  func testClassifierFailurePreservesVisionDiagnostics() async throws {
    let adapter = VisionDiagnosticAdapter(
      analyzer: VisionPersonalRecognizerAnalyzer(
        classifier: FailingPersonalRecognizerClassifier()
      )
    )
    let reference = RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: 1),
      sequenceNumber: 1
    )
    adapter.receive(
      CapturedRecognitionFrame(
        reference: reference,
        pixelBuffer: try pixelBuffer(from: loadFixture(named: "open-palm"))
      )
    )
    let completed = expectation(description: "failed classification completed")
    var observedCompletion: RecognitionAnalysis?

    adapter.execute(.analyzeFrame(reference)) { completion in
      observedCompletion = completion
      completed.fulfill()
    }
    await fulfillment(of: [completed], timeout: 3)

    XCTAssertEqual(observedCompletion?.diagnosticGesture.handDetection, .detected)
    XCTAssertEqual(observedCompletion?.personalRecognizerResult, .failed)
    XCTAssertNotNil(observedCompletion?.cameraImage)
    XCTAssertEqual(observedCompletion?.normalizedCrop?.width, 224)
    XCTAssertEqual(observedCompletion?.normalizedCrop?.height, 224)
  }

  @MainActor
  func testDetectedHandWithoutNormalizedCropReportsFailure() async throws {
    let classifier = RecordingPersonalRecognizerClassifier(classifications: [])
    let adapter = VisionDiagnosticAdapter(
      analyzer: VisionPersonalRecognizerAnalyzer(
        handCropPath: MissingNormalizedCropPath(),
        classifier: classifier
      )
    )
    let reference = RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: 1),
      sequenceNumber: 1
    )
    adapter.receive(
      CapturedRecognitionFrame(
        reference: reference,
        pixelBuffer: try pixelBuffer(from: loadFixture(named: "open-palm"))
      )
    )
    let completed = expectation(description: "missing crop completed")
    var observedCompletion: RecognitionAnalysis?

    adapter.execute(.analyzeFrame(reference)) { completion in
      observedCompletion = completion
      completed.fulfill()
    }
    await fulfillment(of: [completed], timeout: 3)

    XCTAssertEqual(observedCompletion?.diagnosticGesture.handDetection, .detected)
    XCTAssertEqual(observedCompletion?.personalRecognizerResult, .failed)
    XCTAssertNotNil(observedCompletion?.cameraImage)
    XCTAssertNil(observedCompletion?.normalizedCrop)
    XCTAssertTrue(classifier.imageSizes.isEmpty)
  }

  @MainActor
  func testLiveCompiledPersonalRecognizerClassifiesRepresentativeFixturesWhenOptedIn()
    async throws
  {
    let environment = ProcessInfo.processInfo.environment
    guard environment["SIGLAUNCH_RUN_PERSONAL_RECOGNIZER_FIXTURE"] == "1" else {
      throw XCTSkip(
        "Set SIGLAUNCH_RUN_PERSONAL_RECOGNIZER_FIXTURE=1 to use private pose fixtures."
      )
    }
    guard
      let modelRootPath = environment["SIGLAUNCH_PERSONAL_RECOGNIZER_MODEL_ROOT"],
      let fixtureRootPath = environment["SIGLAUNCH_PERSONAL_RECOGNIZER_FIXTURE_ROOT"]
    else {
      return XCTFail(
        "Set SIGLAUNCH_PERSONAL_RECOGNIZER_MODEL_ROOT and SIGLAUNCH_PERSONAL_RECOGNIZER_FIXTURE_ROOT."
      )
    }

    let adapter = VisionDiagnosticAdapter(
      analyzer: VisionPersonalRecognizerAnalyzer(
        classifier: CoreMLPersonalRecognizerClassifier(
          rootDirectory: URL(
            fileURLWithPath: modelRootPath,
            isDirectory: true
          )
        )
      )
    )
    let cases: [(name: String, isPoseMatch: Bool)] = [
      ("positive", true),
      ("near-miss", false),
      ("nonmatch", false),
    ]

    for (index, testCase) in cases.enumerated() {
      let imageURL = URL(
        fileURLWithPath: fixtureRootPath,
        isDirectory: true
      )
      .appendingPathComponent(testCase.name)
      .appendingPathExtension("png")
      let reference = RecognitionFrameReference(
        lifecycleID: RecognitionLifecycleID(rawValue: 1),
        sequenceNumber: UInt64(index + 1)
      )
      adapter.receive(
        CapturedRecognitionFrame(
          reference: reference,
          pixelBuffer: try pixelBuffer(from: loadImage(at: imageURL))
        )
      )
      let completed = expectation(description: "\(testCase.name) classified")
      var observedCompletion: RecognitionAnalysis?
      adapter.execute(.analyzeFrame(reference)) { completion in
        observedCompletion = completion
        completed.fulfill()
      }
      await fulfillment(of: [completed], timeout: 10)

      guard
        let result = observedCompletion?.personalRecognizerResult,
        case .classified(let classifications) = result,
        let top = classifications.max(by: { $0.confidence < $1.confidence })
      else {
        XCTFail("\(testCase.name) did not complete Vision and Core ML classification")
        continue
      }
      let isPoseMatch =
        top.label == "domain_expansion" && top.confidence >= 0.75
      XCTAssertEqual(isPoseMatch, testCase.isPoseMatch, testCase.name)
    }
  }

  @MainActor
  func testResetCancelsOldAnalysisAndSerializesTheNextLifecycle() async throws {
    let firstStarted = expectation(description: "first Vision analysis started")
    let secondCompleted = expectation(description: "second Vision analysis completed")
    let analyzer = ControlledVisionDiagnosticAnalyzer(
      firstStarted: firstStarted
    )
    let adapter = VisionDiagnosticAdapter(analyzer: analyzer)
    let pixelBuffer = try pixelBuffer(from: loadFixture(named: "closed-fist"))
    let first = RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: 1),
      sequenceNumber: 1
    )
    let second = RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: 2),
      sequenceNumber: 1
    )
    var completedFrames: [RecognitionFrameReference] = []

    adapter.receive(
      CapturedRecognitionFrame(reference: first, pixelBuffer: pixelBuffer)
    )
    adapter.execute(.analyzeFrame(first)) { completion in
      completedFrames.append(completion.frame)
    }
    await fulfillment(of: [firstStarted], timeout: 1)

    adapter.reset()
    XCTAssertTrue(analyzer.wasFirstAnalysisCancelled)
    adapter.receive(
      CapturedRecognitionFrame(reference: second, pixelBuffer: pixelBuffer)
    )
    adapter.execute(.analyzeFrame(second)) { completion in
      completedFrames.append(completion.frame)
      secondCompleted.fulfill()
    }
    await fulfillment(of: [secondCompleted], timeout: 1)

    XCTAssertEqual(completedFrames, [second])
    XCTAssertEqual(analyzer.maximumConcurrentAnalysisCount, 1)
  }

  private func pixelBuffer(from image: CGImage) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      image.width,
      image.height,
      kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else {
      throw VisionDiagnosticFixtureError.pixelBufferCreationFailed(status)
    }

    CIContext().render(
      CIImage(cgImage: image),
      to: pixelBuffer,
      bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
      colorSpace: image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    )
    return pixelBuffer
  }

  private func blankImage() throws -> CGImage {
    guard
      let context = CGContext(
        data: nil,
        width: 512,
        height: 512,
        bitsPerComponent: 8,
        bytesPerRow: 512 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      let image = context.makeImage()
    else {
      throw VisionDiagnosticFixtureError.renderingFailed
    }
    return image
  }

  private func loadFixture(named name: String) throws -> CGImage {
    guard
      let url = Bundle.module.url(
        forResource: name,
        withExtension: "png",
        subdirectory: "Fixtures"
      ) ?? Bundle.module.url(forResource: name, withExtension: "png")
    else {
      throw VisionDiagnosticFixtureError.unreadable(name)
    }
    return try loadImage(at: url)
  }

  private func loadImage(at url: URL) throws -> CGImage {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw VisionDiagnosticFixtureError.unreadable(url.path)
    }
    return image
  }
}

private final class MissingNormalizedCropPath:
  DetectedHandCropNormalizing,
  @unchecked Sendable
{
  func normalizedCrop(from image: CGImage) throws -> CGImage? {
    nil
  }

  func normalizedCrop(
    from image: CGImage,
    detectedHand: VNHumanHandPoseObservation
  ) throws -> CGImage? {
    nil
  }
}

private final class FailingPersonalRecognizerClassifier:
  PersonalRecognizerClassifying,
  @unchecked Sendable
{
  func classify(_ image: CGImage) throws -> [PersonalRecognizerClassification] {
    throw FailingPersonalRecognizerError.expected
  }

  func reset() {}
}

private enum FailingPersonalRecognizerError: Error {
  case expected
}

private final class RecordingPersonalRecognizerClassifier:
  PersonalRecognizerClassifying,
  @unchecked Sendable
{
  let classifications: [PersonalRecognizerClassification]
  private let lock = NSLock()
  private var observedImageSizes: [CGSize] = []

  init(classifications: [PersonalRecognizerClassification]) {
    self.classifications = classifications
  }

  var imageSizes: [CGSize] {
    lock.withLock { observedImageSizes }
  }

  func classify(_ image: CGImage) throws -> [PersonalRecognizerClassification] {
    lock.withLock {
      observedImageSizes.append(
        CGSize(width: image.width, height: image.height)
      )
    }
    return classifications
  }

  func reset() {}
}

private final class ControlledVisionDiagnosticAnalyzer:
  VisionDiagnosticAnalyzing,
  @unchecked Sendable
{
  private let lock = NSLock()
  private let firstRelease = DispatchSemaphore(value: 0)
  private let firstStarted: XCTestExpectation
  private var nextIndex = 0
  private var activeAnalysisCount = 0
  private var maximumActiveAnalysisCount = 0
  private var firstAnalysisCancelled = false

  init(firstStarted: XCTestExpectation) {
    self.firstStarted = firstStarted
  }

  var wasFirstAnalysisCancelled: Bool {
    lock.withLock { firstAnalysisCancelled }
  }

  var maximumConcurrentAnalysisCount: Int {
    lock.withLock { maximumActiveAnalysisCount }
  }

  func makeAnalysis(
    pixelBuffer: CVPixelBuffer
  ) -> any VisionDiagnosticAnalysis {
    let index = lock.withLock {
      defer { nextIndex += 1 }
      return nextIndex
    }
    return ControlledVisionDiagnosticAnalysis(
      index: index,
      owner: self
    )
  }

  fileprivate func perform(index: Int) -> DiagnosticGestureResult {
    lock.withLock {
      activeAnalysisCount += 1
      maximumActiveAnalysisCount = max(
        maximumActiveAnalysisCount,
        activeAnalysisCount
      )
    }
    defer {
      lock.withLock { activeAnalysisCount -= 1 }
    }

    if index == 0 {
      firstStarted.fulfill()
      firstRelease.wait()
    }
    return DiagnosticGestureResult(
      handDetection: .notDetected,
      recognizedJointCount: 0,
      extendedFingerCount: 0,
      isOpenPalm: false
    )
  }

  fileprivate func cancel(index: Int) {
    guard index == 0 else { return }
    lock.withLock { firstAnalysisCancelled = true }
    firstRelease.signal()
  }
}

private final class ControlledVisionDiagnosticAnalysis:
  VisionDiagnosticAnalysis,
  @unchecked Sendable
{
  private let index: Int
  private let owner: ControlledVisionDiagnosticAnalyzer

  init(index: Int, owner: ControlledVisionDiagnosticAnalyzer) {
    self.index = index
    self.owner = owner
  }

  func perform() -> VisionRecognitionResult {
    VisionRecognitionResult(
      diagnosticGesture: owner.perform(index: index),
      personalRecognizerResult: .failed
    )
  }

  func cancel() {
    owner.cancel(index: index)
  }
}

private enum VisionDiagnosticFixtureError: Error {
  case unreadable(String)
  case pixelBufferCreationFailed(CVReturn)
  case renderingFailed
}
