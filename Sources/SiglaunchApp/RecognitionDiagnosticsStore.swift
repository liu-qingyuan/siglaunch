import Combine
import CoreGraphics
import SiglaunchCore

enum RecognitionDiagnosticsUpdate: @unchecked Sendable {
  case opened(RecognitionDiagnosticsSession)
  case snapshot(RecognitionDiagnosticsSnapshot)
  case closed
}

struct RecognitionDiagnosticsSnapshot: @unchecked Sendable {
  let diagnostics: RecognitionDiagnosticsFrame
  let analysis: RecognitionAnalysis

  init(
    diagnostics: RecognitionDiagnosticsFrame,
    analysis: RecognitionAnalysis
  ) {
    precondition(diagnostics.frame == analysis.frame)
    self.diagnostics = diagnostics
    self.analysis = analysis
  }

  var cameraImage: CGImage? { analysis.cameraImage }
  var normalizedCrop: CGImage? {
    guard cameraImage != nil else { return nil }
    return analysis.normalizedCrop
  }
  var diagnosticGesture: DiagnosticGestureResult {
    analysis.diagnosticGesture
  }
  var personalRecognizerResult: PersonalRecognizerInferenceResult {
    analysis.personalRecognizerResult
  }
}

@MainActor
final class RecognitionDiagnosticsStore: ObservableObject {
  @Published private(set) var session: RecognitionDiagnosticsSession?
  @Published private(set) var latestSnapshot: RecognitionDiagnosticsSnapshot?

  func setSession(_ session: RecognitionDiagnosticsSession?) {
    self.session = session
    latestSnapshot = nil
  }

  func publish(_ snapshot: RecognitionDiagnosticsSnapshot) {
    guard session != nil else { return }
    latestSnapshot = snapshot
  }
}
