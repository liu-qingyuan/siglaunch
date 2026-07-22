import CoreGraphics
import ImageIO
import SiglaunchCore
import UniformTypeIdentifiers
import XCTest

@testable import SiglaunchApp

final class PoseDatasetAdapterTests: XCTestCase {
  func testRejectsUnavailableRootAndLabelDirectories() async throws {
    let workspace = try makeTemporaryDirectory()
    let output = workspace.appendingPathComponent("output", isDirectory: true)
    let missingRoot = workspace.appendingPathComponent("missing", isDirectory: true)
    let rootFile = workspace.appendingPathComponent("root-file")
    try Data("not a directory".utf8).write(to: rootFile)

    let missingLabelRoot = workspace.appendingPathComponent("missing-label", isDirectory: true)
    try FileManager.default.createDirectory(
      at: missingLabelRoot.appendingPathComponent("other", isDirectory: true),
      withIntermediateDirectories: true
    )

    let malformedLabelRoot = workspace.appendingPathComponent("malformed-label", isDirectory: true)
    try FileManager.default.createDirectory(
      at: malformedLabelRoot.appendingPathComponent("domain_expansion", isDirectory: true),
      withIntermediateDirectories: true
    )
    try Data("not a directory".utf8).write(
      to: malformedLabelRoot.appendingPathComponent("other")
    )

    let cases: [(name: String, root: URL, failure: PoseDatasetImportFailure)] = [
      (
        "missing root",
        missingRoot,
        .rootDirectoryUnavailable(.missing)
      ),
      (
        "root is a regular file",
        rootFile,
        .rootDirectoryUnavailable(.notDirectory)
      ),
      (
        "required label is missing",
        missingLabelRoot,
        .labelDirectoryUnavailable(label: .domainExpansion, reason: .missing)
      ),
      (
        "required label is not a directory",
        malformedLabelRoot,
        .labelDirectoryUnavailable(label: .other, reason: .notDirectory)
      ),
    ]

    for testCase in cases {
      let adapter = PoseDatasetAdapter(
        outputDirectory: output,
        handCropPath: FakeHandCropPath()
      )
      let result = await adapter.prepare(at: testCase.root.path) { _ in }
      XCTAssertEqual(result, .failed(testCase.failure), testCase.name)
    }
  }

  func testRejectsUnreadableLabelDirectory() async throws {
    let workspace = try makeTemporaryDirectory()
    let root = workspace.appendingPathComponent("dataset", isDirectory: true)
    let domainExpansion = root.appendingPathComponent(
      PoseDatasetLabel.domainExpansion.rawValue,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: domainExpansion,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(PoseDatasetLabel.other.rawValue, isDirectory: true),
      withIntermediateDirectories: true
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o000],
      ofItemAtPath: domainExpansion.path
    )
    addTeardownBlock {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: domainExpansion.path
      )
    }

    let adapter = PoseDatasetAdapter(
      outputDirectory: workspace.appendingPathComponent("output", isDirectory: true),
      handCropPath: FakeHandCropPath()
    )

    let result = await adapter.prepare(at: root.path) { _ in }
    XCTAssertEqual(
      result,
      .failed(
        .labelDirectoryUnavailable(label: .domainExpansion, reason: .unreadable)
      )
    )
  }

  func testReportsCorruptAndHandlessImagesWhenValidCountIsInsufficient() async throws {
    let workspace = try makeTemporaryDirectory()
    let root = workspace.appendingPathComponent("dataset", isDirectory: true)
    try createLabelDirectories(at: root)
    try writeImages(
      count: 9,
      width: FakeImageFixture.validWidth,
      label: .domainExpansion,
      root: root
    )
    try writeImages(
      count: 10,
      width: FakeImageFixture.validWidth,
      label: .other,
      root: root
    )
    try writeImage(
      width: FakeImageFixture.handlessWidth,
      to: labelDirectory(.domainExpansion, root: root).appendingPathComponent("handless.png")
    )
    try Data("not an image".utf8).write(
      to: labelDirectory(.domainExpansion, root: root).appendingPathComponent("corrupt.png")
    )
    try Data("not an image".utf8).write(
      to: labelDirectory(.other, root: root).appendingPathComponent("corrupt.png")
    )

    let adapter = PoseDatasetAdapter(
      outputDirectory: workspace.appendingPathComponent("output", isDirectory: true),
      handCropPath: FakeHandCropPath()
    )
    let expectedSummary = PoseDatasetSummary(
      domainExpansion: PoseDatasetLabelSummary(
        validImageCount: 9,
        handlessImageCount: 1,
        unreadableImageCount: 1
      ),
      other: PoseDatasetLabelSummary(
        validImageCount: 10,
        handlessImageCount: 0,
        unreadableImageCount: 1
      )
    )

    let result = await adapter.prepare(at: root.path) { _ in }
    XCTAssertEqual(
      result,
      .failed(
        .insufficientValidImages(summary: expectedSummary, minimumPerLabel: 10)
      )
    )
  }

  func testCreatesNormalizedLocalTrainingInputAndReportsProgress() async throws {
    let workspace = try makeTemporaryDirectory()
    let root = workspace.appendingPathComponent("dataset", isDirectory: true)
    let output = workspace.appendingPathComponent("output", isDirectory: true)
    try createLabelDirectories(at: root)
    try writeImages(
      count: 10,
      width: FakeImageFixture.validWidth,
      label: .domainExpansion,
      root: root
    )
    try writeImages(
      count: 10,
      width: FakeImageFixture.validWidth,
      label: .other,
      root: root
    )
    try writeImage(
      width: FakeImageFixture.handlessWidth,
      to: labelDirectory(.domainExpansion, root: root).appendingPathComponent("handless.png")
    )
    try Data("not an image".utf8).write(
      to: labelDirectory(.other, root: root).appendingPathComponent("corrupt.png")
    )

    let progressRecorder = ProgressRecorder()
    let adapter = PoseDatasetAdapter(
      outputDirectory: output,
      handCropPath: FakeHandCropPath()
    )
    let result = await adapter.prepare(at: root.path) { progress in
      await progressRecorder.append(progress)
    }

    guard case .succeeded(let input) = result else {
      return XCTFail("expected training input, got \(result)")
    }
    XCTAssertEqual(input.samples.count, 20)
    XCTAssertEqual(
      input.summary,
      PoseDatasetSummary(
        domainExpansion: PoseDatasetLabelSummary(
          validImageCount: 10,
          handlessImageCount: 1,
          unreadableImageCount: 0
        ),
        other: PoseDatasetLabelSummary(
          validImageCount: 10,
          handlessImageCount: 0,
          unreadableImageCount: 1
        )
      )
    )
    XCTAssertTrue(input.samples.allSatisfy { FileManager.default.fileExists(atPath: $0.imagePath) })
    XCTAssertEqual(Set(input.samples.map(\.label)), Set(PoseDatasetLabel.allCases))

    for sample in input.samples {
      guard
        let source = CGImageSourceCreateWithURL(
          URL(fileURLWithPath: sample.imagePath) as CFURL,
          nil
        ),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else {
        return XCTFail("normalized sample is not a readable image: \(sample.imagePath)")
      }
      XCTAssertEqual(image.width, FakeImageFixture.normalizedSize)
      XCTAssertEqual(image.height, FakeImageFixture.normalizedSize)
    }

    let progress = await progressRecorder.values
    XCTAssertEqual(progress.count, 22)
    XCTAssertEqual(progress.last?.processedImageCount, 22)
    XCTAssertEqual(progress.last?.totalImageCount, 22)
  }

  func testVisionFailureStopsPreparationAndRemovesPartialOutput() async throws {
    let workspace = try makeTemporaryDirectory()
    let root = workspace.appendingPathComponent("dataset", isDirectory: true)
    let output = workspace.appendingPathComponent("output", isDirectory: true)
    try createLabelDirectories(at: root)
    try writeImage(
      width: FakeImageFixture.visionFailureWidth,
      to: labelDirectory(.domainExpansion, root: root).appendingPathComponent("vision-error.png")
    )

    let adapter = PoseDatasetAdapter(
      outputDirectory: output,
      handCropPath: FakeHandCropPath()
    )
    let result = await adapter.prepare(at: root.path) { _ in }

    XCTAssertEqual(
      result,
      .failed(
        .preparationFailed(
          summary: PoseDatasetSummary(
            domainExpansion: PoseDatasetLabelSummary(
              validImageCount: 0,
              handlessImageCount: 0,
              unreadableImageCount: 0
            ),
            other: PoseDatasetLabelSummary(
              validImageCount: 0,
              handlessImageCount: 0,
              unreadableImageCount: 0
            )
          )
        )
      )
    )
    let outputContents = try FileManager.default.contentsOfDirectory(atPath: output.path)
    XCTAssertTrue(outputContents.isEmpty)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directory)
    }
    return directory
  }

  private func createLabelDirectories(at root: URL) throws {
    for label in PoseDatasetLabel.allCases {
      try FileManager.default.createDirectory(
        at: labelDirectory(label, root: root),
        withIntermediateDirectories: true
      )
    }
  }

  private func writeImages(
    count: Int,
    width: Int,
    label: PoseDatasetLabel,
    root: URL
  ) throws {
    for index in 0..<count {
      try writeImage(
        width: width,
        to: labelDirectory(label, root: root)
          .appendingPathComponent(String(format: "%02d.png", index))
      )
    }
  }

  private func labelDirectory(_ label: PoseDatasetLabel, root: URL) -> URL {
    root.appendingPathComponent(label.rawValue, isDirectory: true)
  }

  private func writeImage(width: Int, to url: URL) throws {
    guard
      let image = makeImage(width: width, height: 8),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw TestError.imageCreationFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw TestError.imageCreationFailed
    }
  }
}

private actor ProgressRecorder {
  private(set) var values: [PoseDatasetPreparationProgress] = []

  func append(_ progress: PoseDatasetPreparationProgress) {
    values.append(progress)
  }
}

private enum FakeImageFixture {
  static let validWidth = 8
  static let handlessWidth = 2
  static let visionFailureWidth = 3
  static let normalizedSize = 6
}

private final class FakeHandCropPath: HandCropNormalizing, @unchecked Sendable {
  func normalizedCrop(from image: CGImage) throws -> CGImage? {
    if image.width == FakeImageFixture.handlessWidth {
      return nil
    }
    if image.width == FakeImageFixture.visionFailureWidth {
      throw TestError.visionFailed
    }
    return makeImage(
      width: FakeImageFixture.normalizedSize,
      height: FakeImageFixture.normalizedSize
    )
  }
}

private enum TestError: Error {
  case imageCreationFailed
  case visionFailed
}

private func makeImage(width: Int, height: Int) -> CGImage? {
  guard
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    return nil
  }
  context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  return context.makeImage()
}
