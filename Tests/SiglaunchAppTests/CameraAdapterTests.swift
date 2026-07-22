import AppKit
import CoreVideo
import SiglaunchCore
import XCTest

@testable import SiglaunchApp

@MainActor
final class CameraAdapterTests: XCTestCase {
  func testFrameRatePolicySelectsClosestSupportedRateWithoutExceedingTarget() {
    let cases: [(target: Double, ranges: [ClosedRange<Double>], expected: Double?)] = [
      (15, [10...30], 15),
      (15, [24...60, 10...12], 12),
      (30, [10...15, 20...29.97], 29.97),
      (10, [24...60], nil),
    ]

    for testCase in cases {
      let actual = CameraFrameRatePolicy.closestSupportedRate(
        notExceeding: testCase.target,
        ranges: testCase.ranges
      )
      if let expected = testCase.expected {
        XCTAssertEqual(actual ?? -1, expected, accuracy: 0.001)
      } else {
        XCTAssertNil(actual)
      }
    }
  }
  func testFrameDeliveryReturnsOnlyAfterTheMainActorSinkRuns() async throws {
    let delivered = expectation(description: "frame delivered")
    let state = CameraFrameDeliveryState()
    let frame = CapturedRecognitionFrame(
      reference: RecognitionFrameReference(
        lifecycleID: RecognitionLifecycleID(rawValue: 1),
        sequenceNumber: 1
      ),
      pixelBuffer: try makePixelBuffer()
    )

    let deliveryTask = Task.detached {
      CameraFrameDelivery.deliver(frame) { deliveredFrame in
        state.markDelivered(deliveredFrame.reference)
        delivered.fulfill()
      }
      return state.deliveredReference
    }

    await fulfillment(of: [delivered], timeout: 1)
    let deliveredBeforeReturn = await deliveryTask.value
    XCTAssertEqual(deliveredBeforeReturn, frame.reference)
  }

  func testForwardsSystemLifecycleAndAuthorizationRefreshEvents() async {
    let notificationCenter = NotificationCenter()
    let workspaceNotificationCenter = NotificationCenter()
    let adapter = ProductionCameraAdapter(
      notificationCenter: notificationCenter,
      workspaceNotificationCenter: workspaceNotificationCenter
    )
    let released = expectation(description: "camera released")
    let sleeping = expectation(description: "system will sleep")
    let awake = expectation(description: "system did wake")
    let authorizationRefreshed = expectation(description: "authorization refreshed")
    var events: [CameraEvent] = []

    let eventSink: @MainActor @Sendable (CameraEvent) -> Void = { event in
      events.append(event)
      switch event {
      case .released:
        released.fulfill()
      case .systemWillSleep:
        sleeping.fulfill()
      case .systemDidWake:
        awake.fulfill()
      case .authorizationChanged:
        authorizationRefreshed.fulfill()
      default:
        break
      }
    }

    adapter.execute(.stopAndReleaseCamera, eventSink: eventSink)
    workspaceNotificationCenter.post(
      name: NSWorkspace.willSleepNotification,
      object: nil
    )
    workspaceNotificationCenter.post(
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
    notificationCenter.post(
      name: NSApplication.didBecomeActiveNotification,
      object: nil
    )

    await fulfillment(
      of: [released, sleeping, awake, authorizationRefreshed],
      timeout: 1
    )
    XCTAssertTrue(events.contains(.released))
    XCTAssertTrue(events.contains(.systemWillSleep))
    XCTAssertTrue(events.contains(.systemDidWake))
  }

  private func makePixelBuffer() throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      16,
      16,
      kCVPixelFormatType_32BGRA,
      nil,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else {
      throw CameraAdapterTestError.pixelBufferCreationFailed(status)
    }
    return pixelBuffer
  }

  func testLiveBuiltInCameraFrameRateCaptureAndReleaseWhenOptedIn() async throws {
    guard ProcessInfo.processInfo.environment["SIGLAUNCH_RUN_CAMERA_SMOKE"] == "1" else {
      throw XCTSkip(
        "Set SIGLAUNCH_RUN_CAMERA_SMOKE=1 in a GUI session to use the physical camera."
      )
    }

    let adapter = ProductionCameraAdapter()
    let authorized = expectation(description: "camera authorized")
    var authorizationStatus: CameraAuthorizationStatus?
    adapter.execute(.requestAuthorization) { event in
      guard case .authorizationChanged(let status) = event else { return }
      authorizationStatus = status
      authorized.fulfill()
    }
    await fulfillment(of: [authorized], timeout: 30)
    XCTAssertEqual(authorizationStatus, .authorized)

    let selectedRate = expectation(description: "frame rate selected")
    let started = expectation(description: "capture started")
    let frameDelivered = expectation(description: "recognition frame delivered")
    var selection: RecognitionFrameRateSelection?
    var startLifecycleID: RecognitionLifecycleID?
    var startResult: CameraCaptureStartResult?
    var capturedReference: RecognitionFrameReference?
    adapter.execute(
      .startBuiltInCamera(
        targetFrameRate: .fps15,
        lifecycleID: RecognitionLifecycleID(rawValue: 1)
      ),
      eventSink: { event in
        switch event {
        case .recognitionFrameRateSelected(let value):
          selection = value
          selectedRate.fulfill()
        case .captureStartCompleted(let lifecycleID, let result):
          startLifecycleID = lifecycleID
          startResult = result
          started.fulfill()
        default:
          break
        }
      },
      frameSink: { frame in
        guard capturedReference == nil else { return }
        capturedReference = frame.reference
        frameDelivered.fulfill()
      }
    )
    await fulfillment(
      of: [selectedRate, started, frameDelivered],
      timeout: 15
    )
    XCTAssertEqual(startLifecycleID, RecognitionLifecycleID(rawValue: 1))
    XCTAssertEqual(startResult, .succeeded)
    XCTAssertEqual(selection?.targetFrameRate, .fps15)
    XCTAssertGreaterThan(selection?.actualFramesPerSecond ?? 0, 0)
    XCTAssertLessThanOrEqual(selection?.actualFramesPerSecond ?? .infinity, 15)
    XCTAssertEqual(
      capturedReference?.lifecycleID,
      RecognitionLifecycleID(rawValue: 1)
    )

    let released = expectation(description: "camera released")
    adapter.execute(.stopAndReleaseCamera) { event in
      guard event == .released else { return }
      released.fulfill()
    }
    await fulfillment(of: [released], timeout: 15)
  }
}

private final class CameraFrameDeliveryState: @unchecked Sendable {
  private let lock = NSLock()
  private var reference: RecognitionFrameReference?

  var deliveredReference: RecognitionFrameReference? {
    lock.withLock { reference }
  }

  func markDelivered(_ reference: RecognitionFrameReference) {
    lock.withLock { self.reference = reference }
  }
}

private enum CameraAdapterTestError: Error {
  case pixelBufferCreationFailed(CVReturn)
}
