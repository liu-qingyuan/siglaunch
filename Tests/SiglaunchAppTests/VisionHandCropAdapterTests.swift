import CoreGraphics
import Foundation
import ImageIO
import SiglaunchCore
import XCTest

@testable import SiglaunchApp

final class VisionHandCropAdapterTests: XCTestCase {
  func testRealVisionDetectsFixtureAndProducesNormalizedCrop() throws {
    let image = try loadFixture(named: "open-palm")
    let adapter = VisionHandCropAdapter()

    let crop = try adapter.normalizedCrop(from: image)

    XCTAssertEqual(crop?.width, 224)
    XCTAssertEqual(crop?.height, 224)
  }

  @MainActor
  func testRealVisionPreparedInputReturnsThroughProductionCoordinatorLoop() async throws {
    let fixtureURL = try fixtureURL(named: "open-palm")
    let workspace = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let root = workspace.appendingPathComponent("dataset", isDirectory: true)
    let output = workspace.appendingPathComponent("output", isDirectory: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: workspace)
    }

    for label in PoseDatasetLabel.allCases {
      let labelDirectory = root.appendingPathComponent(label.rawValue, isDirectory: true)
      try FileManager.default.createDirectory(
        at: labelDirectory,
        withIntermediateDirectories: true
      )
      for index in 0..<10 {
        try FileManager.default.copyItem(
          at: fixtureURL,
          to: labelDirectory.appendingPathComponent("\(index).png")
        )
      }
    }

    let coordinator = LaunchCoordinator()
    for event in [
      AppEvent.appLaunched,
      .menuBarApplicationConfigurationCompleted(.succeeded),
      .personalRecognizerChecked(.missing),
      .menuPresented(.setupRequired),
    ] {
      _ = coordinator.handle(event)
    }

    let ready = expectation(description: "real Vision training input ready")
    var observedEffects: [AppEffect] = []
    var presentations: [PoseDatasetImportPresentation?] = []
    var readyInput: PoseDatasetTrainingInput?
    var sendEvent: ((AppEvent) -> Void)!
    var effectAdapter: ProductionEffectAdapter!
    effectAdapter = ProductionEffectAdapter(
      recognizerStore: PersonalRecognizerStore(),
      poseDatasetFolderSelector: FixtureFolderSelector(path: root.path),
      poseDatasetPreparer: PoseDatasetAdapter(outputDirectory: output),
      eventSink: { event in sendEvent(event) },
      menuSink: { _ in },
      workflowSink: { _ in },
      poseDatasetSink: { presentation in
        presentations.append(presentation)
        if case .ready(let input) = presentation {
          readyInput = input
          ready.fulfill()
        }
      }
    )
    sendEvent = { event in
      let effects = coordinator.handle(event)
      observedEffects.append(contentsOf: effects)
      for effect in effects {
        effectAdapter.execute(effect)
      }
    }

    sendEvent(.poseDatasetImportRequested)
    await fulfillment(of: [ready], timeout: 5)

    XCTAssertEqual(readyInput?.samples.count, 20)
    let progress: [PoseDatasetPreparationProgress] = presentations.compactMap {
      presentation in
      guard
        let presentation,
        case .validating(let progress?) = presentation
      else {
        return nil
      }
      return progress
    }
    XCTAssertEqual(progress.count, 20)
    XCTAssertEqual(progress.last?.processedImageCount, 20)
    XCTAssertEqual(
      Array(observedEffects.prefix(4)),
      [
        .presentPoseDatasetImport(.choosingFolder),
        .selectPoseDatasetFolder,
        .presentPoseDatasetImport(.validating(nil)),
        .preparePoseDataset(at: root.path),
      ]
    )
    XCTAssertEqual(observedEffects.last, readyInput.map { .presentPoseDatasetImport(.ready($0)) })
  }

  func testRealVisionTreatsBlankImageAsHandless() throws {
    guard
      let context = CGContext(
        data: nil,
        width: 512,
        height: 512,
        bitsPerComponent: 8,
        bytesPerRow: 512 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      let image = context.makeImage()
    else {
      return XCTFail("could not create blank fixture")
    }

    XCTAssertNil(try VisionHandCropAdapter().normalizedCrop(from: image))
  }

  private func loadFixture(named name: String) throws -> CGImage {
    let url = try fixtureURL(named: name)
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw FixtureError.unreadable(name)
    }
    return image
  }

  private func fixtureURL(named name: String) throws -> URL {
    guard
      let url = Bundle.module.url(
        forResource: name,
        withExtension: "png",
        subdirectory: "Fixtures"
      ) ?? Bundle.module.url(forResource: name, withExtension: "png")
    else {
      throw FixtureError.unreadable(name)
    }
    return url
  }
}

@MainActor
private final class FixtureFolderSelector: PoseDatasetFolderSelecting {
  private let path: String

  init(path: String) {
    self.path = path
  }

  func selectFolder() -> PoseDatasetFolderSelectionResult {
    .selected(path: path)
  }
}

private enum FixtureError: Error {
  case unreadable(String)
}
