import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import SiglaunchCore
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
      var observedCompletion: RecognitionFrameCompletion?

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

  private func loadFixture(named name: String) throws -> CGImage {
    guard
      let url = Bundle.module.url(
        forResource: name,
        withExtension: "png",
        subdirectory: "Fixtures"
      ) ?? Bundle.module.url(forResource: name, withExtension: "png"),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw VisionDiagnosticFixtureError.unreadable(name)
    }
    return image
  }
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

  func perform() -> DiagnosticGestureResult {
    owner.perform(index: index)
  }

  func cancel() {
    owner.cancel(index: index)
  }
}

private enum VisionDiagnosticFixtureError: Error {
  case unreadable(String)
  case pixelBufferCreationFailed(CVReturn)
}
