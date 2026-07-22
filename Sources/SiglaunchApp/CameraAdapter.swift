@preconcurrency import AVFoundation
import AppKit
import SiglaunchCore

@MainActor
protocol CameraAdapting: AnyObject {
  func execute(
    _ effect: CameraEffect,
    eventSink: @escaping @MainActor @Sendable (CameraEvent) -> Void
  )
}

@MainActor
final class ProductionCameraAdapter: CameraAdapting {
  private struct Observation {
    let center: NotificationCenter
    let token: NSObjectProtocol
  }

  private let captureController: CameraCaptureController
  private let notificationCenter: NotificationCenter
  private let workspaceNotificationCenter: NotificationCenter
  private var observations: [Observation] = []
  private var eventSink: (@MainActor @Sendable (CameraEvent) -> Void)?
  private var operationTask: Task<Void, Never>?

  init(
    notificationCenter: NotificationCenter = .default,
    workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
  ) {
    self.notificationCenter = notificationCenter
    self.workspaceNotificationCenter = workspaceNotificationCenter
    captureController = CameraCaptureController(notificationCenter: notificationCenter)
  }

  deinit {
    operationTask?.cancel()
    for observation in observations {
      observation.center.removeObserver(observation.token)
    }
  }

  func execute(
    _ effect: CameraEffect,
    eventSink: @escaping @MainActor @Sendable (CameraEvent) -> Void
  ) {
    self.eventSink = eventSink
    installLifecycleObserversIfNeeded()

    switch effect {
    case .requestAuthorization:
      requestAuthorization()
    case .startBuiltInCamera,
      .stopCapture,
      .stopAndReleaseCamera,
      .rebuildBuiltInCamera:
      enqueue(effect)
    }
  }

  private func requestAuthorization() {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    guard status == .notDetermined else {
      emit(.authorizationChanged(status.cameraAuthorizationStatus))
      return
    }

    AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
      Task { @MainActor [weak self] in
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        self?.emit(.authorizationChanged(status.cameraAuthorizationStatus))
      }
    }
  }

  private func enqueue(_ effect: CameraEffect) {
    let precedingTask = operationTask
    let captureController = captureController
    let lifecycleSink: @Sendable (CameraEvent) -> Void = { [weak self] event in
      Task { @MainActor [weak self] in
        self?.emit(event)
      }
    }

    operationTask = Task { [weak self] in
      _ = await precedingTask?.value
      guard !Task.isCancelled else { return }
      if let event = await captureController.execute(
        effect,
        lifecycleSink: lifecycleSink
      ) {
        self?.emit(event)
      }
    }
  }

  private func installLifecycleObserversIfNeeded() {
    guard observations.isEmpty else { return }

    observe(
      center: workspaceNotificationCenter,
      name: NSWorkspace.willSleepNotification
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.emit(.systemWillSleep)
      }
    }
    observe(
      center: workspaceNotificationCenter,
      name: NSWorkspace.didWakeNotification
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.emit(.systemDidWake)
      }
    }
    observe(
      center: notificationCenter,
      name: AVCaptureDevice.wasConnectedNotification
    ) { [weak self] notification in
      guard
        let device = notification.object as? AVCaptureDevice,
        device.hasMediaType(.video)
      else { return }
      Task { @MainActor [weak self] in
        self?.emit(.cameraSwitchDetected)
      }
    }
    observe(
      center: notificationCenter,
      name: AVCaptureDevice.wasDisconnectedNotification
    ) { [weak self] notification in
      guard
        let device = notification.object as? AVCaptureDevice,
        device.hasMediaType(.video)
      else { return }
      Task { @MainActor [weak self] in
        self?.emit(.cameraSwitchDetected)
      }
    }
    observe(
      center: notificationCenter,
      name: NSApplication.didBecomeActiveNotification
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        self?.emit(.authorizationChanged(status.cameraAuthorizationStatus))
      }
    }
  }

  private func observe(
    center: NotificationCenter,
    name: Notification.Name,
    using block: @escaping @Sendable (Notification) -> Void
  ) {
    let token = center.addObserver(
      forName: name,
      object: nil,
      queue: nil,
      using: block
    )
    observations.append(Observation(center: center, token: token))
  }

  private func emit(_ event: CameraEvent) {
    eventSink?(event)
  }
}

private actor CameraCaptureController {
  private let notificationCenter: NotificationCenter
  private var session: AVCaptureSession?
  private var sessionObservations: [NSObjectProtocol] = []

  init(notificationCenter: NotificationCenter) {
    self.notificationCenter = notificationCenter
  }

  func execute(
    _ effect: CameraEffect,
    lifecycleSink: @escaping @Sendable (CameraEvent) -> Void
  ) -> CameraEvent? {
    switch effect {
    case .requestAuthorization:
      return nil
    case .startBuiltInCamera:
      return startBuiltInCamera(lifecycleSink: lifecycleSink)
    case .stopCapture:
      stopCapture()
      return nil
    case .stopAndReleaseCamera:
      stopAndReleaseCamera()
      return .released
    case .rebuildBuiltInCamera:
      stopAndReleaseCamera()
      return startBuiltInCamera(lifecycleSink: lifecycleSink)
    }
  }

  private func startBuiltInCamera(
    lifecycleSink: @escaping @Sendable (CameraEvent) -> Void
  ) -> CameraEvent {
    let authorization = AVCaptureDevice.authorizationStatus(for: .video)
    guard authorization == .authorized else {
      return .authorizationChanged(authorization.cameraAuthorizationStatus)
    }

    if let session {
      if !session.isRunning {
        session.startRunning()
      }
      guard session.isRunning else {
        stopAndReleaseCamera()
        return .captureStartCompleted(.failed(.startFailed))
      }
      return .captureStartCompleted(.succeeded)
    }

    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera],
      mediaType: .video,
      position: .unspecified
    )
    guard let device = discovery.devices.first else {
      return .captureStartCompleted(.failed(.builtInCameraUnavailable))
    }

    let input: AVCaptureDeviceInput
    do {
      input = try AVCaptureDeviceInput(device: device)
    } catch {
      return .captureStartCompleted(.failed(.configurationFailed))
    }

    let session = AVCaptureSession()
    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true

    session.beginConfiguration()
    guard session.canAddInput(input), session.canAddOutput(output) else {
      session.commitConfiguration()
      return .captureStartCompleted(.failed(.configurationFailed))
    }
    session.addInput(input)
    session.addOutput(output)
    session.commitConfiguration()

    self.session = session
    installSessionObservers(for: session, lifecycleSink: lifecycleSink)
    session.startRunning()

    guard session.isRunning else {
      stopAndReleaseCamera()
      return .captureStartCompleted(.failed(.startFailed))
    }
    return .captureStartCompleted(.succeeded)
  }

  private func stopCapture() {
    guard let session, session.isRunning else { return }
    session.stopRunning()
  }

  private func stopAndReleaseCamera() {
    removeSessionObservers()
    guard let session else { return }
    if session.isRunning {
      session.stopRunning()
    }
    session.beginConfiguration()
    for input in session.inputs {
      session.removeInput(input)
    }
    for output in session.outputs {
      session.removeOutput(output)
    }
    session.commitConfiguration()
    self.session = nil
  }

  private func installSessionObservers(
    for session: AVCaptureSession,
    lifecycleSink: @escaping @Sendable (CameraEvent) -> Void
  ) {
    removeSessionObservers()
    sessionObservations = [
      notificationCenter.addObserver(
        forName: AVCaptureSession.wasInterruptedNotification,
        object: session,
        queue: nil
      ) { _ in
        lifecycleSink(.captureInterrupted)
      },
      notificationCenter.addObserver(
        forName: AVCaptureSession.interruptionEndedNotification,
        object: session,
        queue: nil
      ) { _ in
        lifecycleSink(.captureInterruptionEnded)
      },
    ]
  }

  private func removeSessionObservers() {
    for token in sessionObservations {
      notificationCenter.removeObserver(token)
    }
    sessionObservations.removeAll()
  }
}

private extension AVAuthorizationStatus {
  var cameraAuthorizationStatus: CameraAuthorizationStatus {
    switch self {
    case .notDetermined:
      .notDetermined
    case .restricted:
      .restricted
    case .denied:
      .denied
    case .authorized:
      .authorized
    @unknown default:
      .restricted
    }
  }
}
