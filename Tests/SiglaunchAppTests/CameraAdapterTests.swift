import AppKit
import SiglaunchCore
import XCTest

@testable import SiglaunchApp

@MainActor
final class CameraAdapterTests: XCTestCase {
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

  func testLiveBuiltInCameraAuthorizationCaptureAndReleaseWhenOptedIn() async throws {
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

    let started = expectation(description: "capture started")
    var startResult: CameraCaptureStartResult?
    adapter.execute(.startBuiltInCamera) { event in
      guard case .captureStartCompleted(let result) = event else { return }
      startResult = result
      started.fulfill()
    }
    await fulfillment(of: [started], timeout: 15)
    XCTAssertEqual(startResult, .succeeded)

    let released = expectation(description: "camera released")
    adapter.execute(.stopAndReleaseCamera) { event in
      guard event == .released else { return }
      released.fulfill()
    }
    await fulfillment(of: [released], timeout: 15)
  }
}
