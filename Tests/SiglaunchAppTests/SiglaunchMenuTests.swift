import SiglaunchCore
import XCTest

@testable import SiglaunchApp

final class SiglaunchMenuTests: XCTestCase {
  func testRecognitionDiagnosticsExposeRatesAndJointStatus() {
    let diagnostics = RecognitionDiagnostics(
      targetFrameRate: .fps15,
      captureFramesPerSecond: 12,
      completedRecognitionFramesPerSecond: 9.75,
      diagnosticGesture: DiagnosticGestureResult(
        handDetection: .detected,
        recognizedJointCount: 21,
        extendedFingerCount: 5,
        isOpenPalm: true
      )
    )

    XCTAssertEqual(
      diagnostics.content.detail,
      "Target: 15 FPS | Capture: 12 FPS | Completed: 9.8 FPS"
    )
    XCTAssertEqual(
      diagnostics.handDetail,
      "Hand: detected | Joints: 21 | Extended: 5 | Open palm: yes"
    )
    XCTAssertEqual(
      RecognitionFrameRate.allCases,
      [.fps10, .fps15, .fps30]
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
