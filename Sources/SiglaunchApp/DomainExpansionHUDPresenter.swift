import AppKit
import QuartzCore
import SiglaunchCore

@MainActor
public protocol DomainExpansionHUDPresenting: AnyObject {
  func execute(
    _ effect: DomainExpansionHUDPresentationEffect,
    eventSink: @escaping @MainActor @Sendable (DomainExpansionHUDPresentationEvent) -> Void
  )
}

@MainActor
protocol DomainExpansionHUDScheduledAction: AnyObject {
  func cancel()
}

@MainActor
protocol DomainExpansionHUDScheduling: AnyObject {
  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> any DomainExpansionHUDScheduledAction
}

@MainActor
private final class SystemDomainExpansionHUDScheduler: DomainExpansionHUDScheduling {
  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> any DomainExpansionHUDScheduledAction {
    SystemDomainExpansionHUDScheduledAction(delay: delay, action: action)
  }
}

@MainActor
private final class SystemDomainExpansionHUDScheduledAction:
  DomainExpansionHUDScheduledAction
{
  private let task: Task<Void, Never>

  init(
    delay: TimeInterval,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
    task = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: nanoseconds)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      action()
    }
  }

  func cancel() {
    task.cancel()
  }
}

@MainActor
final class AppKitDomainExpansionHUDAdapter: NSObject, DomainExpansionHUDPresenting {
  static let animationDuration: TimeInterval = 1.2
  static let fadeDuration: TimeInterval = 0.2
  static let soundName: NSSound.Name? = nil
  static let panelIdentifier = NSUserInterfaceItemIdentifier(
    "siglaunch.domain-expansion-hud"
  )
  static let ringIdentifier = NSUserInterfaceItemIdentifier(
    "siglaunch.domain-expansion-ring"
  )
  static let dismissButtonIdentifier = NSUserInterfaceItemIdentifier(
    "siglaunch.domain-expansion-dismiss"
  )
  static let ringAnimationKey = "siglaunch.domain-expansion-ring-animation"

  private let screenProvider: @MainActor () -> NSScreen?
  private let scheduler: any DomainExpansionHUDScheduling
  private var panel: DomainExpansionHUDPanel?
  private var animationCompletion: (any DomainExpansionHUDScheduledAction)?
  private var fadeCompletion: (any DomainExpansionHUDScheduledAction)?
  private var eventSink: (@MainActor @Sendable (DomainExpansionHUDPresentationEvent) -> Void)?

  var presentedPanel: NSPanel? { panel }

  init(
    screenProvider: @escaping @MainActor () -> NSScreen? = {
      AppKitDomainExpansionHUDAdapter.currentScreen()
    },
    scheduler: any DomainExpansionHUDScheduling = SystemDomainExpansionHUDScheduler()
  ) {
    self.screenProvider = screenProvider
    self.scheduler = scheduler
    super.init()
  }

  func execute(
    _ effect: DomainExpansionHUDPresentationEffect,
    eventSink: @escaping @MainActor @Sendable (DomainExpansionHUDPresentationEvent) -> Void
  ) {
    self.eventSink = eventSink
    switch effect {
    case .showDomainExpansion:
      showDomainExpansion(eventSink: eventSink)
    case .fade:
      fade(eventSink: eventSink)
    case .showError(let failure):
      showError(failure, eventSink: eventSink)
    case .dismiss:
      dismiss(eventSink: eventSink)
    }
  }

  private func showDomainExpansion(
    eventSink: @escaping @MainActor @Sendable (DomainExpansionHUDPresentationEvent) -> Void
  ) {
    cancelScheduledActions()
    panel?.close()
    panel = nil

    guard let screen = screenProvider() else {
      eventSink(.presentationFailed(.showDomainExpansion))
      return
    }

    let panel = makePanel(on: screen)
    let contentView = makeDomainExpansionContentView()
    panel.contentView = contentView
    panel.ignoresMouseEvents = true
    panel.alphaValue = 1
    panel.orderFrontRegardless()
    contentView.layoutSubtreeIfNeeded()
    contentView.ringView.startAnimation(duration: Self.animationDuration)
    self.panel = panel

    if let soundName = Self.soundName {
      _ = NSSound(named: soundName)?.play()
    }

    animationCompletion = scheduler.schedule(
      after: Self.animationDuration
    ) { [weak self, weak panel] in
      guard let self, panel === self.panel else { return }
      animationCompletion = nil
      self.eventSink?(.animationCompleted)
    }
  }

  private func fade(
    eventSink: @escaping @MainActor @Sendable (DomainExpansionHUDPresentationEvent) -> Void
  ) {
    animationCompletion?.cancel()
    animationCompletion = nil
    guard let panel else {
      eventSink(.presentationFailed(.fade))
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fadeDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().alphaValue = 0
    }
    fadeCompletion?.cancel()
    fadeCompletion = scheduler.schedule(after: Self.fadeDuration) {
      [weak self, weak panel] in
      guard let self, panel === self.panel else { return }
      panel?.close()
      self.panel = nil
      fadeCompletion = nil
      self.eventSink = nil
    }
  }

  private func showError(
    _ failure: PrimaryWorkflowFailure,
    eventSink: @escaping @MainActor @Sendable (DomainExpansionHUDPresentationEvent) -> Void
  ) {
    animationCompletion?.cancel()
    animationCompletion = nil
    guard let panel else {
      eventSink(.presentationFailed(.showError(failure)))
      return
    }

    panel.contentView = makeErrorContentView(failure: failure)
    panel.ignoresMouseEvents = false
    panel.alphaValue = 1
    panel.orderFrontRegardless()
  }

  private func dismiss(
    eventSink: @escaping @MainActor @Sendable (DomainExpansionHUDPresentationEvent) -> Void
  ) {
    cancelScheduledActions()
    guard let panel else {
      eventSink(.presentationFailed(.dismiss))
      return
    }
    panel.close()
    self.panel = nil
    self.eventSink = nil
  }

  private func cancelScheduledActions() {
    animationCompletion?.cancel()
    animationCompletion = nil
    fadeCompletion?.cancel()
    fadeCompletion = nil
  }

  private func makePanel(on screen: NSScreen) -> DomainExpansionHUDPanel {
    let size = NSSize(width: 360, height: 220)
    let frame = NSRect(
      x: screen.frame.midX - size.width / 2,
      y: screen.frame.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
    let panel = DomainExpansionHUDPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.setFrame(frame, display: false)
    panel.identifier = Self.panelIdentifier
    panel.level = .statusBar
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isMovable = false
    panel.animationBehavior = .none
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
      .ignoresCycle,
    ]
    return panel
  }

  private func makeDomainExpansionContentView() -> DomainExpansionHUDContentView {
    DomainExpansionHUDContentView()
  }

  private func makeErrorContentView(
    failure: PrimaryWorkflowFailure
  ) -> NSView {
    let container = makeContainerView()

    let title = NSTextField(labelWithString: "Workflow Failed")
    title.font = .systemFont(ofSize: 20, weight: .semibold)
    title.textColor = .white
    title.alignment = .center

    let detail = NSTextField(labelWithString: failure.detail)
    detail.font = .systemFont(ofSize: 13, weight: .regular)
    detail.textColor = NSColor.white.withAlphaComponent(0.82)
    detail.alignment = .center
    detail.lineBreakMode = .byWordWrapping
    detail.maximumNumberOfLines = 3
    detail.preferredMaxLayoutWidth = 290

    let stack = NSStackView(views: [title, detail])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)

    let dismissImage =
      NSImage(
        systemSymbolName: "xmark",
        accessibilityDescription: "Dismiss"
      ) ?? NSImage(size: NSSize(width: 14, height: 14))
    let dismissButton = DomainExpansionDismissButton(
      image: dismissImage,
      target: self,
      action: #selector(dismissRequested)
    )
    dismissButton.identifier = Self.dismissButtonIdentifier
    dismissButton.toolTip = "Dismiss"
    dismissButton.isBordered = false
    dismissButton.bezelStyle = .circular
    dismissButton.contentTintColor = NSColor.white.withAlphaComponent(0.8)
    dismissButton.setAccessibilityLabel("Dismiss")
    dismissButton.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(dismissButton)

    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 28),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -28),
      dismissButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
      dismissButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
      dismissButton.widthAnchor.constraint(equalToConstant: 28),
      dismissButton.heightAnchor.constraint(equalToConstant: 28),
    ])
    return container
  }

  private func makeContainerView() -> NSVisualEffectView {
    let container = NSVisualEffectView()
    container.material = .hudWindow
    container.blendingMode = .behindWindow
    container.state = .active
    container.wantsLayer = true
    container.layer?.cornerRadius = 8
    container.layer?.masksToBounds = true
    container.layer?.borderWidth = 1
    container.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    return container
  }

  @objc private func dismissRequested() {
    eventSink?(.dismissed)
  }

  private static func currentScreen() -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    return NSScreen.screens.first {
      NSMouseInRect(mouseLocation, $0.frame, false)
    } ?? NSScreen.main
  }
}

@MainActor
private final class DomainExpansionHUDPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

@MainActor
private final class DomainExpansionDismissButton: NSButton {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class DomainExpansionHUDContentView: NSVisualEffectView {
  let ringView = DomainExpansionRingView()

  init() {
    super.init(frame: .zero)
    material = .hudWindow
    blendingMode = .behindWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.masksToBounds = true
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

    ringView.identifier = AppKitDomainExpansionHUDAdapter.ringIdentifier
    ringView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(ringView)

    let title = NSTextField(labelWithString: "领域展开")
    title.font = .systemFont(ofSize: 26, weight: .semibold)
    title.textColor = .white
    title.alignment = .center
    title.translatesAutoresizingMaskIntoConstraints = false
    addSubview(title)

    NSLayoutConstraint.activate([
      ringView.centerXAnchor.constraint(equalTo: centerXAnchor),
      ringView.centerYAnchor.constraint(equalTo: centerYAnchor),
      ringView.widthAnchor.constraint(equalToConstant: 156),
      ringView.heightAnchor.constraint(equalToConstant: 156),
      title.centerXAnchor.constraint(equalTo: centerXAnchor),
      title.centerYAnchor.constraint(equalTo: centerYAnchor),
      title.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
      title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

@MainActor
private final class DomainExpansionRingView: NSView {
  private let ringLayer = CAShapeLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    ringLayer.fillColor = NSColor.clear.cgColor
    ringLayer.strokeColor = NSColor.systemCyan.withAlphaComponent(0.9).cgColor
    ringLayer.lineWidth = 1.5
    ringLayer.shadowColor = NSColor.systemCyan.cgColor
    ringLayer.shadowOpacity = 0.35
    ringLayer.shadowRadius = 4
    layer?.addSublayer(ringLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    ringLayer.frame = bounds
    ringLayer.path = CGPath(
      ellipseIn: bounds.insetBy(dx: 8, dy: 8),
      transform: nil
    )
  }

  func startAnimation(duration: TimeInterval) {
    layoutSubtreeIfNeeded()

    let scale = CABasicAnimation(keyPath: "transform.scale")
    scale.fromValue = 0.2
    scale.toValue = 1.25

    let opacity = CABasicAnimation(keyPath: "opacity")
    opacity.fromValue = 0.95
    opacity.toValue = 0.05

    let animation = CAAnimationGroup()
    animation.animations = [scale, opacity]
    animation.duration = duration
    animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
    animation.fillMode = .forwards
    animation.isRemovedOnCompletion = false
    layer?.add(
      animation,
      forKey: AppKitDomainExpansionHUDAdapter.ringAnimationKey
    )
  }
}
