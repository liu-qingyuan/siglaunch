import SiglaunchCore
import XCTest

@testable import SiglaunchApp

@MainActor
final class RecognitionDiagnosticsStoreTests: XCTestCase {
  func testStoreKeepsOnlyTheLatestInMemorySnapshotAndClearsOnClose() {
    let store = RecognitionDiagnosticsStore()
    let session = RecognitionDiagnosticsSession(
      policy: .standard,
      targetFrameRate: .fps15,
      captureFramesPerSecond: 12
    )
    store.setSession(session)

    store.publish(snapshot(sequenceNumber: 1))
    store.publish(snapshot(sequenceNumber: 2))

    XCTAssertEqual(store.session, session)
    XCTAssertEqual(store.latestSnapshot?.diagnostics.frame.sequenceNumber, 2)

    store.setSession(nil)

    XCTAssertNil(store.session)
    XCTAssertNil(store.latestSnapshot)
  }

  private func snapshot(
    sequenceNumber: UInt64
  ) -> RecognitionDiagnosticsSnapshot {
    let frame = RecognitionFrameReference(
      lifecycleID: RecognitionLifecycleID(rawValue: 1),
      sequenceNumber: sequenceNumber
    )
    let analysis = RecognitionAnalysis(
      frame: frame,
      cameraImage: nil,
      normalizedCrop: nil,
      diagnosticGesture: DiagnosticGestureResult(
        handDetection: .detected,
        recognizedJointCount: 21,
        extendedFingerCount: 2,
        isOpenPalm: false
      ),
      personalRecognizerResult: .classified([
        PersonalRecognizerClassification(
          label: "domain_expansion",
          confidence: 0.9
        )
      ])
    )
    return RecognitionDiagnosticsSnapshot(
      diagnostics: RecognitionDiagnosticsFrame(
        frame: frame,
        policy: .standard,
        topClassification: PersonalRecognizerClassification(
          label: "domain_expansion",
          confidence: 0.9
        ),
        isPoseMatch: true,
        poseMatchCount: Int(sequenceNumber),
        targetFrameRate: .fps15,
        captureFramesPerSecond: 12,
        completedRecognitionFramesPerSecond: 10
      ),
      analysis: analysis
    )
  }
}
