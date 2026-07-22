import CoreGraphics
import Foundation
import ImageIO
import SiglaunchCore
import UniformTypeIdentifiers

protocol HandCropNormalizing: Sendable {
  func normalizedCrop(from image: CGImage) throws -> CGImage?
}

protocol PoseDatasetPreparing: Sendable {
  func prepare(
    at rootPath: String,
    progress: @escaping @Sendable (PoseDatasetPreparationProgress) async -> Void
  ) async -> PoseDatasetPreparationResult
}

actor PoseDatasetAdapter: PoseDatasetPreparing {
  private struct LabelCounts {
    var valid = 0
    var handless = 0
    var unreadable = 0

    var summary: PoseDatasetLabelSummary {
      PoseDatasetLabelSummary(
        validImageCount: valid,
        handlessImageCount: handless,
        unreadableImageCount: unreadable
      )
    }
  }

  private let outputDirectory: URL
  private let handCropPath: any HandCropNormalizing
  private let fileManager: FileManager

  init(
    outputDirectory: URL = PoseDatasetAdapter.defaultOutputDirectory,
    handCropPath: any HandCropNormalizing = VisionHandCropAdapter(),
    fileManager: FileManager = .default
  ) {
    self.outputDirectory = outputDirectory
    self.handCropPath = handCropPath
    self.fileManager = fileManager
  }

  func prepare(
    at rootPath: String,
    progress: @escaping @Sendable (PoseDatasetPreparationProgress) async -> Void
  ) async -> PoseDatasetPreparationResult {
    let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
    if let failure = directoryFailure(at: root) {
      return .failed(.rootDirectoryUnavailable(failure))
    }

    var filesByLabel: [PoseDatasetLabel: [URL]] = [:]
    for label in PoseDatasetLabel.allCases {
      let directory = root.appendingPathComponent(label.rawValue, isDirectory: true)
      if let failure = directoryFailure(at: directory) {
        return .failed(.labelDirectoryUnavailable(label: label, reason: failure))
      }
      do {
        filesByLabel[label] = try imageCandidates(in: directory)
      } catch {
        return .failed(.labelDirectoryUnavailable(label: label, reason: .unreadable))
      }
    }

    do {
      try fileManager.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      return .failed(.outputUnavailable)
    }

    let preparedDirectory =
      outputDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      for label in PoseDatasetLabel.allCases {
        try fileManager.createDirectory(
          at: preparedDirectory.appendingPathComponent(label.rawValue, isDirectory: true),
          withIntermediateDirectories: true
        )
      }
    } catch {
      removePreparedDirectory(preparedDirectory)
      return .failed(.outputUnavailable)
    }

    var counts = Dictionary(
      uniqueKeysWithValues: PoseDatasetLabel.allCases.map { ($0, LabelCounts()) }
    )
    var samples: [PoseDatasetSample] = []
    var processedImageCount = 0
    let totalImageCount = filesByLabel.values.reduce(0) { $0 + $1.count }

    for label in PoseDatasetLabel.allCases {
      for sourceURL in filesByLabel[label, default: []] {
        if let sourceImage = loadOrientedImage(at: sourceURL) {
          let normalizedImage: CGImage?
          do {
            normalizedImage = try handCropPath.normalizedCrop(from: sourceImage)
          } catch {
            let summary = makeSummary(from: counts)
            removePreparedDirectory(preparedDirectory)
            return .failed(.preparationFailed(summary: summary))
          }

          if let normalizedImage {
            let sampleIndex = counts[label, default: LabelCounts()].valid + 1
            let destinationURL =
              preparedDirectory
              .appendingPathComponent(label.rawValue, isDirectory: true)
              .appendingPathComponent(String(format: "%04d.png", sampleIndex))
            guard writePNG(normalizedImage, to: destinationURL) else {
              removePreparedDirectory(preparedDirectory)
              return .failed(.outputUnavailable)
            }
            counts[label, default: LabelCounts()].valid += 1
            samples.append(
              PoseDatasetSample(label: label, imagePath: destinationURL.path)
            )
          } else {
            counts[label, default: LabelCounts()].handless += 1
          }
        } else {
          counts[label, default: LabelCounts()].unreadable += 1
        }

        processedImageCount += 1
        await progress(
          PoseDatasetPreparationProgress(
            label: label,
            processedImageCount: processedImageCount,
            totalImageCount: totalImageCount
          )
        )
      }
    }

    let summary = makeSummary(from: counts)
    guard
      PoseDatasetLabel.allCases.allSatisfy({
        summary.summary(for: $0).validImageCount
          >= PoseDatasetTrainingInput.minimumValidImageCountPerLabel
      })
    else {
      removePreparedDirectory(preparedDirectory)
      return .failed(
        .insufficientValidImages(
          summary: summary,
          minimumPerLabel: PoseDatasetTrainingInput.minimumValidImageCountPerLabel
        )
      )
    }

    guard
      let input = PoseDatasetTrainingInput(
        directoryPath: preparedDirectory.path,
        samples: samples,
        summary: summary
      )
    else {
      removePreparedDirectory(preparedDirectory)
      return .failed(.preparationFailed(summary: summary))
    }
    return .succeeded(input)
  }

  private func directoryFailure(at url: URL) -> PoseDatasetDirectoryFailure? {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return .missing
    }
    guard isDirectory.boolValue else {
      return .notDirectory
    }
    guard fileManager.isReadableFile(atPath: url.path) else {
      return .unreadable
    }
    return nil
  }

  private func imageCandidates(in directory: URL) throws -> [URL] {
    try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    )
    .filter { url in
      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  private func loadOrientedImage(at url: URL) -> CGImage? {
    guard
      fileManager.isReadableFile(atPath: url.path),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
    else {
      return nil
    }

    let maximumDimension = max(width.intValue, height.intValue)
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  private func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      return false
    }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
  }

  private func makeSummary(
    from counts: [PoseDatasetLabel: LabelCounts]
  ) -> PoseDatasetSummary {
    PoseDatasetSummary(
      domainExpansion: counts[.domainExpansion, default: LabelCounts()].summary,
      other: counts[.other, default: LabelCounts()].summary
    )
  }

  private func removePreparedDirectory(_ directory: URL) {
    try? fileManager.removeItem(at: directory)
  }

  private static var defaultOutputDirectory: URL {
    let applicationSupport =
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? FileManager.default.temporaryDirectory
    return
      applicationSupport
      .appendingPathComponent("Siglaunch", isDirectory: true)
      .appendingPathComponent("Pose Datasets", isDirectory: true)
  }
}
