import CoreGraphics
import SiglaunchCore
import XCTest

@testable import SiglaunchApp

final class SiglaunchMenuTests: XCTestCase {
  func testRecognitionDiagnosticsSnapshotExposesClassifierFacts() throws {
    let frame = RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: 1),
      sequenceNumber: 1
    )
    let top = PersonalRecognizerClassification(
      label: "domain_expansion",
      confidence: 0.9
    )
    let cameraImage = try makeImage(width: 64, height: 48)
    let normalizedCrop = try makeImage(width: 224, height: 224)
    let snapshot = RecognitionDiagnosticsSnapshot(
      diagnostics: RecognitionDiagnosticsFrame(
        frame: frame,
        policy: .standard,
        topClassification: top,
        isPoseMatch: true,
        poseMatchCount: 3,
        targetFrameRate: .fps15,
        captureFramesPerSecond: 12,
        completedRecognitionFramesPerSecond: 9.75
      ),
      analysis: RecognitionAnalysis(
        frame: frame,
        cameraImage: cameraImage,
        normalizedCrop: normalizedCrop,
        diagnosticGesture: DiagnosticGestureResult(
          handDetection: .detected,
          recognizedJointCount: 21,
          extendedFingerCount: 2,
          isOpenPalm: false
        ),
        personalRecognizerResult: .classified([top])
      )
    )

    XCTAssertEqual(snapshot.topCategoryText, "domain_expansion")
    XCTAssertEqual(snapshot.confidenceText, "0.900")
    XCTAssertEqual(snapshot.poseMatchText, "Yes")
    XCTAssertEqual(snapshot.evidenceText, "3/5")
    XCTAssertEqual(snapshot.conditionText, "Met")
    XCTAssertEqual(snapshot.outcomeTitle, "Classification completed")
    XCTAssertTrue(snapshot.cameraImage === cameraImage)
    XCTAssertTrue(snapshot.normalizedCrop === normalizedCrop)
    XCTAssertEqual(RecognitionFrameRate.allCases, [.fps10, .fps15, .fps30])
  }

  func testUnavailableFrameClearsEveryFrameLocalPresentationField() throws {
    let frame = RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: 1),
      sequenceNumber: 1
    )
    let top = PersonalRecognizerClassification(
      label: "domain_expansion",
      confidence: 0.9
    )
    let snapshot = RecognitionDiagnosticsSnapshot(
      diagnostics: RecognitionDiagnosticsFrame(
        frame: frame,
        policy: .standard,
        topClassification: top,
        isPoseMatch: true,
        poseMatchCount: 3,
        targetFrameRate: .fps15,
        captureFramesPerSecond: 12,
        completedRecognitionFramesPerSecond: 9.75
      ),
      analysis: RecognitionAnalysis(
        frame: frame,
        cameraImage: nil,
        normalizedCrop: try makeImage(width: 224, height: 224),
        diagnosticGesture: DiagnosticGestureResult(
          handDetection: .detected,
          recognizedJointCount: 21,
          extendedFingerCount: 2,
          isOpenPalm: false
        ),
        personalRecognizerResult: .classified([top])
      )
    )

    XCTAssertNil(snapshot.cameraImage)
    XCTAssertNil(snapshot.normalizedCrop)
    XCTAssertEqual(snapshot.topCategoryText, "Unavailable")
    XCTAssertEqual(snapshot.confidenceText, "Unavailable")
    XCTAssertEqual(snapshot.poseMatchText, "Unavailable")
    XCTAssertEqual(snapshot.evidenceText, "3/5")
    XCTAssertEqual(snapshot.outcomeTitle, "Frame unavailable")
  }

  func testActiveMonitoringUsesAStableMenuBarSymbol() {
    XCTAssertEqual(
      MenuPresentation.activeMonitoring.content.symbolName,
      "viewfinder.circle"
    )
  }

  func testTrainingPresentationExposesProgressAndCancellationState() {
    let progress = RecognizerTrainingPresentation.training(
      RecognizerTrainingProgress(completedUnitCount: 42, totalUnitCount: 100)
    )

    XCTAssertTrue(progress.isInProgress)
    XCTAssertTrue(progress.isCancellable)
    XCTAssertEqual(progress.content.title, "Training Personal Recognizer")
    XCTAssertEqual(progress.content.detail, "42% complete")

    XCTAssertTrue(RecognizerTrainingPresentation.saving.isInProgress)
    XCTAssertFalse(RecognizerTrainingPresentation.saving.isCancellable)
    XCTAssertFalse(RecognizerTrainingPresentation.succeeded.isInProgress)
  }

  func testPrimaryWorkflowPresentationsRemainOutcomeSpecific() {
    let preserved = PrimaryWorkflowPresentation.piAgentPreserved.content
    XCTAssertEqual(preserved.title, "Pi Agent Preserved")
    XCTAssertNil(preserved.detail)

    let success = PrimaryWorkflowPresentation.piAgentStarted.content
    XCTAssertEqual(success.title, "Pi Agent Started")
    XCTAssertNil(success.detail)

    let failure = PrimaryWorkflowPresentation.failed(.piStartFailed).content
    XCTAssertEqual(failure.title, "Workflow Failed")
    XCTAssertEqual(
      failure.detail,
      "Herdr could not start or confirm the configured Pi Agent."
    )
  }

  private func makeImage(width: Int, height: Int) throws -> CGImage {
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      let image = context.makeImage()
    else {
      throw SiglaunchMenuTestError.imageCreationFailed
    }
    return image
  }

  func testTrainingFailuresRemainStageSpecificInMenu() {
    let cases: [(RecognizerTrainingFailure, String)] = [
      (.training(.trainingFailed), "Create ML training failed."),
      (
        .candidateSave(.compilationFailed),
        "The Personal Recognizer could not be compiled."
      ),
      (
        .modelReplacement(.replacementFailed),
        "The active Personal Recognizer could not be replaced."
      ),
    ]

    for (failure, detail) in cases {
      let content = RecognizerTrainingPresentation.failed(failure).content
      XCTAssertEqual(content.title, "Recognizer Training Failed")
      XCTAssertEqual(content.detail, detail)
    }
  }
}

private enum SiglaunchMenuTestError: Error {
  case imageCreationFailed
}
