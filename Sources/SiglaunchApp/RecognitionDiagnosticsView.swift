import AppKit
import SiglaunchCore
import SwiftUI

struct RecognitionDiagnosticsView: View {
  @ObservedObject var store: RecognitionDiagnosticsStore

  var body: some View {
    Group {
      if let session = store.session {
        diagnosticsContent(session: session, snapshot: store.latestSnapshot)
      } else {
        EmptyView()
      }
    }
    .frame(minWidth: 760, minHeight: 560)
  }

  private func diagnosticsContent(
    session: RecognitionDiagnosticsSession,
    snapshot: RecognitionDiagnosticsSnapshot?
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Recognition Diagnostics")
            .font(.title2.weight(.semibold))
          Text(snapshot?.outcomeTitle ?? "Waiting for completed frame")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if let snapshot {
          Label(
            snapshot.diagnostics.isTriggerConditionSatisfied
              ? "Trigger condition met"
              : "Observing",
            systemImage: snapshot.diagnostics.isTriggerConditionSatisfied
              ? "checkmark.circle.fill"
              : "waveform.path.ecg"
          )
          .foregroundStyle(
            snapshot.diagnostics.isTriggerConditionSatisfied ? .green : .secondary
          )
        }
      }
      .padding(20)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          HStack(alignment: .top, spacing: 16) {
            DiagnosticImagePane(
              title: "Camera Frame",
              image: snapshot?.cameraImage,
              placeholderSymbol: "video.slash",
              aspectRatio: 4 / 3
            )
            .frame(maxWidth: .infinity)

            DiagnosticImagePane(
              title: "Classifier Crop",
              image: snapshot?.normalizedCrop,
              placeholderSymbol: "viewfinder",
              aspectRatio: 1
            )
            .frame(width: 224)
          }

          Divider()

          diagnosticsGrid(session: session, snapshot: snapshot)

          Divider()

          rulesSection(policy: session.policy)
        }
        .padding(20)
      }
    }
  }

  private func diagnosticsGrid(
    session: RecognitionDiagnosticsSession,
    snapshot: RecognitionDiagnosticsSnapshot?
  ) -> some View {
    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
      metricRow("Top Category", snapshot?.topCategoryText ?? "Unavailable")
      metricRow("Confidence", snapshot?.confidenceText ?? "Unavailable")
      metricRow("Pose Match", snapshot?.poseMatchText ?? "Unavailable")
      metricRow(
        "Rolling Evidence",
        snapshot?.evidenceText
          ?? "0/\(session.policy.evidenceWindowSize)"
      )
      metricRow(
        "Condition",
        snapshot?.conditionText ?? "Not met"
      )
      metricRow(
        "Target FPS",
        "\(snapshot?.diagnostics.targetFrameRate.rawValue ?? session.targetFrameRate.rawValue)"
      )
      metricRow(
        "Capture FPS",
        Self.formatFPS(
          snapshot?.diagnostics.captureFramesPerSecond
            ?? session.captureFramesPerSecond
        )
      )
      metricRow(
        "Completed FPS",
        snapshot.map {
          Self.formatFPS($0.diagnostics.completedRecognitionFramesPerSecond)
        } ?? "Pending"
      )
    }
    .font(.body.monospacedDigit())
  }

  private func metricRow(_ title: String, _ value: String) -> some View {
    GridRow {
      Text(title)
        .foregroundStyle(.secondary)
        .frame(width: 150, alignment: .leading)
      Text(value)
        .textSelection(.enabled)
    }
  }

  private func rulesSection(
    policy: DomainExpansionRecognitionPolicy
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Fixed Recognition Rules")
        .font(.headline)
      Label(
        "Top category is \(policy.targetLabel)",
        systemImage: "tag"
      )
      Label(
        "Confidence >= \(Self.formatConfidence(policy.minimumConfidence))",
        systemImage: "gauge.with.dots.needle.67percent"
      )
      Label(
        "At least \(policy.requiredPoseMatchCount) Pose Matches in the latest \(policy.evidenceWindowSize) classified frames",
        systemImage: "rectangle.stack"
      )
    }
  }

  private static func formatFPS(_ value: Double?) -> String {
    guard let value else { return "Pending" }
    let rounded = value.rounded()
    if abs(value - rounded) < 0.05 {
      return "\(Int(rounded))"
    }
    return String(format: "%.1f", value)
  }

  private static func formatConfidence(_ value: Double) -> String {
    String(format: "%.2f", value)
  }
}

private struct DiagnosticImagePane: View {
  let title: String
  let image: CGImage?
  let placeholderSymbol: String
  let aspectRatio: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      ZStack {
        Color.black
        if let image {
          Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
        } else {
          Image(systemName: placeholderSymbol)
            .font(.system(size: 28))
            .foregroundStyle(.secondary)
        }
      }
      .aspectRatio(aspectRatio, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .overlay {
        RoundedRectangle(cornerRadius: 4)
          .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
      }
    }
  }
}

extension RecognitionDiagnosticsSnapshot {
  var topCategoryText: String {
    guard cameraImage != nil else { return "Unavailable" }
    return diagnostics.topClassification?.label ?? "Unavailable"
  }

  var confidenceText: String {
    guard
      cameraImage != nil,
      let confidence = diagnostics.topClassification?.confidence
    else {
      return "Unavailable"
    }
    return String(format: "%.3f", confidence)
  }

  var poseMatchText: String {
    guard cameraImage != nil, let isPoseMatch = diagnostics.isPoseMatch else {
      return "Unavailable"
    }
    return isPoseMatch ? "Yes" : "No"
  }

  var evidenceText: String {
    "\(diagnostics.poseMatchCount)/\(diagnostics.policy.evidenceWindowSize)"
  }

  var conditionText: String {
    diagnostics.isTriggerConditionSatisfied ? "Met" : "Not met"
  }

  var outcomeTitle: String {
    guard cameraImage != nil else { return "Frame unavailable" }
    switch personalRecognizerResult {
    case .classified:
      return diagnostics.topClassification == nil
        ? "Classification unavailable"
        : "Classification completed"
    case .noHandDetected:
      return "No hand detected"
    case .failed:
      return normalizedCrop == nil
        ? "Crop unavailable"
        : "Classification failed"
    }
  }
}

@MainActor
final class RecognitionDiagnosticsWindowController: NSObject, NSWindowDelegate {
  private let store: RecognitionDiagnosticsStore
  private let onClose: () -> Void
  private var window: NSWindow?
  private var isClosingProgrammatically = false

  init(
    store: RecognitionDiagnosticsStore,
    onClose: @escaping () -> Void
  ) {
    self.store = store
    self.onClose = onClose
    super.init()
  }

  func show() {
    if let window {
      NSApplication.shared.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Recognition Diagnostics"
    window.contentMinSize = NSSize(width: 760, height: 560)
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentViewController = NSHostingController(
      rootView: RecognitionDiagnosticsView(store: store)
    )
    window.center()
    self.window = window

    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func close() {
    guard let window else { return }
    isClosingProgrammatically = true
    window.close()
    isClosingProgrammatically = false
    self.window = nil
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
    guard !isClosingProgrammatically else { return }
    onClose()
  }
}
