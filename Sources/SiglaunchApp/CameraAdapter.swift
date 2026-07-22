@preconcurrency import AVFoundation
import AppKit
import SiglaunchCore

enum CameraFrameRatePolicy {
  static func closestSupportedRate(
    notExceeding target: Double,
    ranges: [ClosedRange<Double>]
  ) -> Double? {
    ranges.compactMap { range in
      guard range.lowerBound <= target else { return nil }
      return min(target, range.upperBound)
    }.max()
  }
}

struct CapturedRecognitionFrame: @unchecked Sendable {
  let reference: RecognitionFrameReference
  let pixelBuffer: CVPixelBuffer
}

enum CameraFrameDelivery {
  static func deliver(
    _ frame: CapturedRecognitionFrame,
    to sink: @escaping @MainActor @Sendable (CapturedRecognitionFrame) -> Void
  ) {
    if Thread.isMainThread {
      MainActor.assumeIsolated {
        sink(frame)
      }
      return
    }

    DispatchQueue.main.sync {
      MainActor.assumeIsolated {
        sink(frame)
      }
    }
  }
}

@MainActor
protocol CameraAdapting: AnyObject {
  func execute(
    _ effect: CameraEffect,
    eventSink: @escaping @MainActor @Sendable (CameraEvent) -> Void,
    frameSink: @escaping @MainActor @Sendable (CapturedRecognitionFrame) -> Void
  )
}

extension CameraAdapting {
  func execute(
    _ effect: CameraEffect,
    eventSink: @escaping @MainActor @Sendable (CameraEvent) -> Void
  ) {
    execute(effect, eventSink: eventSink, frameSink: { _ in })
  }
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
    eventSink: @escaping @MainActor @Sendable (CameraEvent) -> Void,
    frameSink: @escaping @MainActor @Sendable (CapturedRecognitionFrame) -> Void
  ) {
    self.eventSink = eventSink
    installLifecycleObserversIfNeeded()

    switch effect {
    case .requestAuthorization:
      requestAuthorization()
    case .startBuiltInCamera,
      .updateRecognitionFrameRate,
      .stopCapture,
      .stopAndReleaseCamera,
      .rebuildBuiltInCamera:
      enqueue(effect, frameSink: frameSink)
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

  private func enqueue(
    _ effect: CameraEffect,
    frameSink: @escaping @MainActor @Sendable (CapturedRecognitionFrame) -> Void
  ) {
    let precedingTask = operationTask
    let captureController = captureController
    let lifecycleSink: @Sendable (CameraEvent) -> Void = { [weak self] event in
      Task { @MainActor [weak self] in
        self?.emit(event)
      }
    }
    let capturedFrameSink: @Sendable (CapturedRecognitionFrame) -> Void = {
      CameraFrameDelivery.deliver($0, to: frameSink)
    }

    operationTask = Task { [weak self] in
      _ = await precedingTask?.value
      guard !Task.isCancelled else { return }
      let events = await captureController.execute(
        effect,
        lifecycleSink: lifecycleSink,
        frameSink: capturedFrameSink
      )
      for event in events {
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
  private struct FrameRateCandidate {
    let format: AVCaptureDevice.Format
    let framesPerSecond: Double
    let pixelCount: Int32
    let isActiveFormat: Bool
  }

  private let notificationCenter: NotificationCenter
  private let outputQueue = DispatchQueue(
    label: "com.siglaunch.camera.recognition-frames",
    qos: .userInitiated
  )
  private var session: AVCaptureSession?
  private var device: AVCaptureDevice?
  private var videoOutput: AVCaptureVideoDataOutput?
  private var frameOutputDelegate: CameraFrameOutputDelegate?
  private var sessionObservations: [NSObjectProtocol] = []

  init(notificationCenter: NotificationCenter) {
    self.notificationCenter = notificationCenter
  }

  func execute(
    _ effect: CameraEffect,
    lifecycleSink: @escaping @Sendable (CameraEvent) -> Void,
    frameSink: @escaping @Sendable (CapturedRecognitionFrame) -> Void
  ) -> [CameraEvent] {
    switch effect {
    case .requestAuthorization:
      return []
    case .startBuiltInCamera(let targetFrameRate, let lifecycleID):
      return startBuiltInCamera(
        targetFrameRate: targetFrameRate,
        lifecycleID: lifecycleID,
        lifecycleSink: lifecycleSink,
        frameSink: frameSink
      )
    case .updateRecognitionFrameRate(let targetFrameRate, let lifecycleID):
      return updateRecognitionFrameRate(
        targetFrameRate: targetFrameRate,
        lifecycleID: lifecycleID,
        lifecycleSink: lifecycleSink,
        frameSink: frameSink
      )
    case .stopCapture:
      stopCapture()
      return []
    case .stopAndReleaseCamera:
      stopAndReleaseCamera()
      return [.released]
    case .rebuildBuiltInCamera(let targetFrameRate, let lifecycleID):
      stopAndReleaseCamera()
      return startBuiltInCamera(
        targetFrameRate: targetFrameRate,
        lifecycleID: lifecycleID,
        lifecycleSink: lifecycleSink,
        frameSink: frameSink
      )
    }
  }

  private func startBuiltInCamera(
    targetFrameRate: RecognitionFrameRate,
    lifecycleID: RecognitionLifecycleID,
    lifecycleSink: @escaping @Sendable (CameraEvent) -> Void,
    frameSink: @escaping @Sendable (CapturedRecognitionFrame) -> Void
  ) -> [CameraEvent] {
    let authorization = AVCaptureDevice.authorizationStatus(for: .video)
    guard authorization == .authorized else {
      return [.authorizationChanged(authorization.cameraAuthorizationStatus)]
    }

    if let session, let device, let videoOutput {
      do {
        let selectedRate = try configureFrameRate(
          on: device,
          targetFrameRate: targetFrameRate
        )
        installFrameOutputDelegate(
          on: videoOutput,
          lifecycleID: lifecycleID,
          frameSink: frameSink
        )
        installSessionObservers(
          for: session,
          lifecycleID: lifecycleID,
          lifecycleSink: lifecycleSink
        )
        if !session.isRunning {
          session.startRunning()
        }
        guard session.isRunning else {
          stopAndReleaseCamera()
          return [.captureStartCompleted(lifecycleID: lifecycleID, result: .failed(.startFailed))]
        }
        return [
          .recognitionFrameRateSelected(
            RecognitionFrameRateSelection(
              lifecycleID: lifecycleID,
              targetFrameRate: targetFrameRate,
              actualFramesPerSecond: selectedRate
            )
          ),
          .captureStartCompleted(lifecycleID: lifecycleID, result: .succeeded),
        ]
      } catch {
        stopAndReleaseCamera()
        return [
          .captureStartCompleted(lifecycleID: lifecycleID, result: .failed(.configurationFailed))
        ]
      }
    }

    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera],
      mediaType: .video,
      position: .unspecified
    )
    guard let device = discovery.devices.first else {
      return [
        .captureStartCompleted(lifecycleID: lifecycleID, result: .failed(.builtInCameraUnavailable))
      ]
    }

    let input: AVCaptureDeviceInput
    do {
      input = try AVCaptureDeviceInput(device: device)
    } catch {
      return [
        .captureStartCompleted(lifecycleID: lifecycleID, result: .failed(.configurationFailed))
      ]
    }

    let session = AVCaptureSession()
    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true

    session.beginConfiguration()
    if session.canSetSessionPreset(.high) {
      session.sessionPreset = .high
    }
    guard session.canAddInput(input), session.canAddOutput(output) else {
      session.commitConfiguration()
      return [
        .captureStartCompleted(lifecycleID: lifecycleID, result: .failed(.configurationFailed))
      ]
    }
    session.addInput(input)
    session.addOutput(output)
    session.commitConfiguration()

    let selectedRate: Double
    do {
      selectedRate = try configureFrameRate(
        on: device,
        targetFrameRate: targetFrameRate
      )
    } catch {
      return [
        .captureStartCompleted(lifecycleID: lifecycleID, result: .failed(.configurationFailed))
      ]
    }

    installFrameOutputDelegate(
      on: output,
      lifecycleID: lifecycleID,
      frameSink: frameSink
    )
    self.session = session
    self.device = device
    videoOutput = output
    installSessionObservers(
      for: session,
      lifecycleID: lifecycleID,
      lifecycleSink: lifecycleSink
    )
    session.startRunning()

    guard session.isRunning else {
      stopAndReleaseCamera()
      return [.captureStartCompleted(lifecycleID: lifecycleID, result: .failed(.startFailed))]
    }
    return [
      .recognitionFrameRateSelected(
        RecognitionFrameRateSelection(
          lifecycleID: lifecycleID,
          targetFrameRate: targetFrameRate,
          actualFramesPerSecond: selectedRate
        )
      ),
      .captureStartCompleted(lifecycleID: lifecycleID, result: .succeeded),
    ]
  }

  private func updateRecognitionFrameRate(
    targetFrameRate: RecognitionFrameRate,
    lifecycleID: RecognitionLifecycleID,
    lifecycleSink: @escaping @Sendable (CameraEvent) -> Void,
    frameSink: @escaping @Sendable (CapturedRecognitionFrame) -> Void
  ) -> [CameraEvent] {
    guard let session, let device, let videoOutput else {
      return [
        .captureStartCompleted(lifecycleID: lifecycleID, result: .failed(.configurationFailed))
      ]
    }

    do {
      let selectedRate = try configureFrameRate(
        on: device,
        targetFrameRate: targetFrameRate
      )
      installFrameOutputDelegate(
        on: videoOutput,
        lifecycleID: lifecycleID,
        frameSink: frameSink
      )
      installSessionObservers(
        for: session,
        lifecycleID: lifecycleID,
        lifecycleSink: lifecycleSink
      )
      return [
        .recognitionFrameRateSelected(
          RecognitionFrameRateSelection(
            lifecycleID: lifecycleID,
            targetFrameRate: targetFrameRate,
            actualFramesPerSecond: selectedRate
          )
        )
      ]
    } catch {
      return [
        .captureStartCompleted(lifecycleID: lifecycleID, result: .failed(.configurationFailed))
      ]
    }
  }

  private func configureFrameRate(
    on device: AVCaptureDevice,
    targetFrameRate: RecognitionFrameRate
  ) throws -> Double {
    let target = Double(targetFrameRate.rawValue)
    let candidates = device.formats.compactMap { format -> FrameRateCandidate? in
      let ranges = format.videoSupportedFrameRateRanges.map {
        $0.minFrameRate...$0.maxFrameRate
      }
      guard
        let framesPerSecond = CameraFrameRatePolicy.closestSupportedRate(
          notExceeding: target,
          ranges: ranges
        )
      else { return nil }
      let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      return FrameRateCandidate(
        format: format,
        framesPerSecond: framesPerSecond,
        pixelCount: dimensions.width * dimensions.height,
        isActiveFormat: format == device.activeFormat
      )
    }

    guard
      let selected = candidates.max(by: { left, right in
        if abs(left.framesPerSecond - right.framesPerSecond) > 0.001 {
          return left.framesPerSecond < right.framesPerSecond
        }
        if left.isActiveFormat != right.isActiveFormat {
          return !left.isActiveFormat
        }
        return left.pixelCount < right.pixelCount
      })
    else {
      throw CameraFrameRateConfigurationError.noSupportedRate
    }

    try device.lockForConfiguration()
    defer { device.unlockForConfiguration() }
    if device.activeFormat != selected.format {
      device.activeFormat = selected.format
    }
    let frameDuration = CMTime(
      seconds: 1 / selected.framesPerSecond,
      preferredTimescale: 60_000
    )
    device.activeVideoMinFrameDuration = frameDuration
    device.activeVideoMaxFrameDuration = frameDuration
    return selected.framesPerSecond
  }

  private func installFrameOutputDelegate(
    on output: AVCaptureVideoDataOutput,
    lifecycleID: RecognitionLifecycleID,
    frameSink: @escaping @Sendable (CapturedRecognitionFrame) -> Void
  ) {
    let delegate = CameraFrameOutputDelegate(
      lifecycleID: lifecycleID,
      frameSink: frameSink
    )
    frameOutputDelegate = delegate
    output.setSampleBufferDelegate(delegate, queue: outputQueue)
  }

  private func stopCapture() {
    guard let session, session.isRunning else { return }
    session.stopRunning()
  }

  private func stopAndReleaseCamera() {
    removeSessionObservers()
    videoOutput?.setSampleBufferDelegate(nil, queue: nil)
    frameOutputDelegate = nil
    device = nil
    videoOutput = nil
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
    lifecycleID: RecognitionLifecycleID,
    lifecycleSink: @escaping @Sendable (CameraEvent) -> Void
  ) {
    removeSessionObservers()
    sessionObservations = [
      notificationCenter.addObserver(
        forName: AVCaptureSession.wasInterruptedNotification,
        object: session,
        queue: nil
      ) { _ in
        lifecycleSink(.captureInterrupted(lifecycleID: lifecycleID))
      },
      notificationCenter.addObserver(
        forName: AVCaptureSession.interruptionEndedNotification,
        object: session,
        queue: nil
      ) { _ in
        lifecycleSink(.captureInterruptionEnded(lifecycleID: lifecycleID))
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

private final class CameraFrameOutputDelegate: NSObject,
  AVCaptureVideoDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  private let lifecycleID: RecognitionLifecycleID
  private let frameSink: @Sendable (CapturedRecognitionFrame) -> Void
  private var nextSequenceNumber: UInt64 = 1

  init(
    lifecycleID: RecognitionLifecycleID,
    frameSink: @escaping @Sendable (CapturedRecognitionFrame) -> Void
  ) {
    self.lifecycleID = lifecycleID
    self.frameSink = frameSink
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    let reference = RecognitionFrameReference(
      lifecycleID: lifecycleID,
      sequenceNumber: nextSequenceNumber
    )
    nextSequenceNumber &+= 1
    frameSink(
      CapturedRecognitionFrame(
        reference: reference,
        pixelBuffer: pixelBuffer
      )
    )
  }
}

private enum CameraFrameRateConfigurationError: Error {
  case noSupportedRate
}

extension AVAuthorizationStatus {
  fileprivate var cameraAuthorizationStatus: CameraAuthorizationStatus {
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
