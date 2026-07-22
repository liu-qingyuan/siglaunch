import AppKit
import QuartzCore
import SiglaunchCore
import XCTest

@testable import SiglaunchApp

@MainActor
final class DomainExpansionHUDPresenterTests: XCTestCase {
  nonisolated override func tearDown() {
    MainActor.assumeIsolated {
      for window in NSApplication.shared.windows
      where window.identifier?.rawValue
        == AppKitDomainExpansionHUDAdapter.panelIdentifier.rawValue
      {
        window.close()
      }
    }
    super.tearDown()
  }

  func testShowUsesCurrentScreenWithoutActivationAndRunsSilentRingAnimation() throws {
    guard let screen = NSScreen.main else {
      throw XCTSkip("No AppKit screen is available")
    }
    let scheduler = TestHUDScheduler()
    var requestedScreenCount = 0
    let presenter = AppKitDomainExpansionHUDAdapter(
      screenProvider: {
        requestedScreenCount += 1
        return screen
      },
      scheduler: scheduler
    )
    var events: [DomainExpansionHUDPresentationEvent] = []
    let frontmostProcessIdentifier =
      NSWorkspace.shared.frontmostApplication?.processIdentifier
    let keyWindowIdentifier = NSApplication.shared.keyWindow.map(ObjectIdentifier.init)

    presenter.execute(.showDomainExpansion) { events.append($0) }

    let panel = try XCTUnwrap(presenter.presentedPanel)
    XCTAssertEqual(requestedScreenCount, 1)
    XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    XCTAssertFalse(panel.canBecomeKey)
    XCTAssertFalse(panel.canBecomeMain)
    XCTAssertTrue(panel.ignoresMouseEvents)
    XCTAssertFalse(panel.isOpaque)
    XCTAssertEqual(panel.backgroundColor, .clear)
    XCTAssertEqual(panel.screen, screen)
    XCTAssertTrue(screen.frame.contains(panel.frame))
    XCTAssertEqual(panel.level, .statusBar)
    XCTAssertEqual(textValues(in: panel), ["领域展开"])
    XCTAssertEqual(scheduler.delays, [1.2])
    XCTAssertNil(AppKitDomainExpansionHUDAdapter.soundName)

    let ring = try XCTUnwrap(
      descendants(of: panel.contentView).first {
        $0.identifier?.rawValue
          == AppKitDomainExpansionHUDAdapter.ringIdentifier.rawValue
      }
    )
    let ringLayer = try XCTUnwrap(
      ring.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first
    )
    XCTAssertEqual(ringLayer.lineWidth, 1.5, accuracy: 0.001)
    let animation = try XCTUnwrap(
      ring.layer?.animation(
        forKey: AppKitDomainExpansionHUDAdapter.ringAnimationKey
      ) as? CAAnimationGroup
    )
    XCTAssertEqual(animation.duration, 1.2, accuracy: 0.001)
    let scaleAnimation = try XCTUnwrap(
      animation.animations?.compactMap { $0 as? CABasicAnimation }
        .first { $0.keyPath == "transform.scale" }
    )
    let fromScale = try XCTUnwrap(
      (scaleAnimation.fromValue as? NSNumber)?.doubleValue
    )
    let toScale = try XCTUnwrap(
      (scaleAnimation.toValue as? NSNumber)?.doubleValue
    )
    XCTAssertEqual(fromScale, 0.2, accuracy: 0.001)
    XCTAssertEqual(toScale, 1.25, accuracy: 0.001)
    XCTAssertEqual(
      NSWorkspace.shared.frontmostApplication?.processIdentifier,
      frontmostProcessIdentifier
    )
    XCTAssertEqual(
      NSApplication.shared.keyWindow.map(ObjectIdentifier.init),
      keyWindowIdentifier
    )

    scheduler.runNext()
    XCTAssertEqual(events, [.animationCompleted])
  }

  func testDefaultScreenProviderUsesTheScreenContainingThePointer() throws {
    let mouseLocation = NSEvent.mouseLocation
    guard
      let expectedScreen = NSScreen.screens.first(where: {
        NSMouseInRect(mouseLocation, $0.frame, false)
      }) ?? NSScreen.main
    else {
      throw XCTSkip("No AppKit screen is available")
    }
    let scheduler = TestHUDScheduler()
    let presenter = AppKitDomainExpansionHUDAdapter(scheduler: scheduler)
    let frontmostProcessIdentifier =
      NSWorkspace.shared.frontmostApplication?.processIdentifier
    let keyWindowIdentifier =
      NSApplication.shared.keyWindow.map(ObjectIdentifier.init)

    presenter.execute(.showDomainExpansion) { _ in }

    let panel = try XCTUnwrap(presenter.presentedPanel)
    XCTAssertEqual(panel.screen, expectedScreen)
    XCTAssertTrue(expectedScreen.frame.contains(panel.frame))
    XCTAssertEqual(
      NSWorkspace.shared.frontmostApplication?.processIdentifier,
      frontmostProcessIdentifier
    )
    XCTAssertEqual(
      NSApplication.shared.keyWindow.map(ObjectIdentifier.init),
      keyWindowIdentifier
    )
    presenter.execute(.dismiss) { _ in }
  }

  func testErrorIsStepSpecificDismissibleAndHasNoRetryControl() throws {
    guard let screen = NSScreen.main else {
      throw XCTSkip("No AppKit screen is available")
    }
    let scheduler = TestHUDScheduler()
    let presenter = AppKitDomainExpansionHUDAdapter(
      screenProvider: { screen },
      scheduler: scheduler
    )
    var events: [DomainExpansionHUDPresentationEvent] = []
    presenter.execute(.showDomainExpansion) { events.append($0) }
    scheduler.runNext()
    let frontmostProcessIdentifier =
      NSWorkspace.shared.frontmostApplication?.processIdentifier
    let keyWindowIdentifier =
      NSApplication.shared.keyWindow.map(ObjectIdentifier.init)

    presenter.execute(.showError(.ghosttyNotInstalled)) { events.append($0) }

    let panel = try XCTUnwrap(presenter.presentedPanel)
    XCTAssertEqual(
      textValues(in: panel),
      ["Workflow Failed", "Ghostty is not installed."]
    )
    let buttons = descendants(of: panel.contentView).compactMap { $0 as? NSButton }
    let dismissButton = try XCTUnwrap(
      buttons.first {
        $0.identifier?.rawValue
          == AppKitDomainExpansionHUDAdapter.dismissButtonIdentifier.rawValue
      }
    )
    XCTAssertEqual(dismissButton.toolTip, "Dismiss")
    XCTAssertTrue(dismissButton.acceptsFirstMouse(for: nil))
    XCTAssertFalse(buttons.contains { $0.title.localizedCaseInsensitiveContains("retry") })
    XCTAssertFalse(panel.canBecomeKey)
    XCTAssertFalse(panel.canBecomeMain)
    XCTAssertFalse(panel.ignoresMouseEvents)
    XCTAssertEqual(
      NSWorkspace.shared.frontmostApplication?.processIdentifier,
      frontmostProcessIdentifier
    )
    XCTAssertEqual(
      NSApplication.shared.keyWindow.map(ObjectIdentifier.init),
      keyWindowIdentifier
    )

    dismissButton.performClick(nil)
    XCTAssertEqual(events, [.animationCompleted, .dismissed])
    XCTAssertTrue(panel.isVisible)

    presenter.execute(.dismiss) { events.append($0) }
    XCTAssertFalse(panel.isVisible)
    XCTAssertEqual(events, [.animationCompleted, .dismissed])
    XCTAssertEqual(
      NSWorkspace.shared.frontmostApplication?.processIdentifier,
      frontmostProcessIdentifier
    )
    XCTAssertEqual(
      NSApplication.shared.keyWindow.map(ObjectIdentifier.init),
      keyWindowIdentifier
    )
  }

  func testSuccessFadeAddsNoCompletionTextAndOrdersPanelOut() throws {
    guard let screen = NSScreen.main else {
      throw XCTSkip("No AppKit screen is available")
    }
    let scheduler = TestHUDScheduler()
    let presenter = AppKitDomainExpansionHUDAdapter(
      screenProvider: { screen },
      scheduler: scheduler
    )
    var events: [DomainExpansionHUDPresentationEvent] = []
    presenter.execute(.showDomainExpansion) { events.append($0) }
    scheduler.runNext()
    let panel = try XCTUnwrap(presenter.presentedPanel)

    presenter.execute(.fade) { events.append($0) }

    XCTAssertEqual(textValues(in: panel), ["领域展开"])
    XCTAssertEqual(scheduler.delays, [1.2, 0.2])
    scheduler.runNext()
    XCTAssertFalse(panel.isVisible)
    XCTAssertEqual(events, [.animationCompleted])
  }

  func testMissingCurrentScreenReturnsPresentationFailure() {
    let presenter = AppKitDomainExpansionHUDAdapter(
      screenProvider: { nil },
      scheduler: TestHUDScheduler()
    )
    var events: [DomainExpansionHUDPresentationEvent] = []

    presenter.execute(.showDomainExpansion) { events.append($0) }

    XCTAssertEqual(
      events,
      [.presentationFailed(.showDomainExpansion)]
    )
    XCTAssertNil(presenter.presentedPanel)
  }

  private var presentedHUDPanels: [NSPanel] {
    NSApplication.shared.windows.compactMap { window in
      guard
        window.isVisible,
        window.identifier?.rawValue
          == AppKitDomainExpansionHUDAdapter.panelIdentifier.rawValue
      else {
        return nil
      }
      return window as? NSPanel
    }
  }

  private func textValues(in panel: NSPanel) -> [String] {
    descendants(of: panel.contentView)
      .compactMap { $0 as? NSTextField }
      .map(\.stringValue)
      .filter { !$0.isEmpty }
  }

  private func descendants(of view: NSView?) -> [NSView] {
    guard let view else { return [] }
    return view.subviews + view.subviews.flatMap { descendants(of: $0) }
  }
}

@MainActor
private final class TestHUDScheduler: DomainExpansionHUDScheduling {
  private struct ScheduledAction {
    let delay: TimeInterval
    let token: TestHUDScheduledAction
    let action: @MainActor @Sendable () -> Void
  }

  private var scheduledActions: [ScheduledAction] = []
  private(set) var delays: [TimeInterval] = []

  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> any DomainExpansionHUDScheduledAction {
    let token = TestHUDScheduledAction()
    delays.append(delay)
    scheduledActions.append(
      ScheduledAction(delay: delay, token: token, action: action)
    )
    return token
  }

  func runNext() {
    guard !scheduledActions.isEmpty else { return }
    let scheduledAction = scheduledActions.removeFirst()
    guard !scheduledAction.token.isCancelled else { return }
    scheduledAction.action()
  }
}

@MainActor
private final class TestHUDScheduledAction: DomainExpansionHUDScheduledAction {
  private(set) var isCancelled = false

  func cancel() {
    isCancelled = true
  }
}
