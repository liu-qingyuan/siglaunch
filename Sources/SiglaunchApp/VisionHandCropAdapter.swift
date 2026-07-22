import CoreGraphics
import Vision

protocol DetectedHandCropNormalizing: HandCropNormalizing {
  func normalizedCrop(
    from image: CGImage,
    detectedHand: VNHumanHandPoseObservation
  ) throws -> CGImage?
}

final class VisionHandCropAdapter: DetectedHandCropNormalizing, @unchecked Sendable {
  private let outputSize: Int
  private let padding: CGFloat
  private let minimumJointConfidence: VNConfidence

  init(
    outputSize: Int = 224,
    padding: CGFloat = 0.25,
    minimumJointConfidence: VNConfidence = 0.2
  ) {
    precondition(outputSize > 0)
    precondition(padding >= 0)
    self.outputSize = outputSize
    self.padding = padding
    self.minimumJointConfidence = minimumJointConfidence
  }

  func normalizedCrop(from image: CGImage) throws -> CGImage? {
    let request = VNDetectHumanHandPoseRequest()
    request.maximumHandCount = 1
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
    try handler.perform([request])

    guard let observation = request.results?.first else { return nil }
    return try normalizedCrop(from: image, detectedHand: observation)
  }

  func normalizedCrop(
    from image: CGImage,
    detectedHand observation: VNHumanHandPoseObservation
  ) throws -> CGImage? {
    guard let normalizedJointBounds = try handBounds(for: observation) else {
      return nil
    }
    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let detectedBounds = VNImageRectForNormalizedRect(
      normalizedJointBounds,
      image.width,
      image.height
    )
    guard
      let cropBounds = paddedSquareBounds(
        around: detectedBounds,
        within: imageBounds
      ),
      let croppedImage = image.cropping(to: cropBounds)
    else {
      throw VisionHandCropError.invalidDetectedBounds
    }
    guard let normalizedImage = resize(croppedImage) else {
      throw VisionHandCropError.outputCreationFailed
    }
    return normalizedImage
  }

  private func handBounds(
    for observation: VNHumanHandPoseObservation
  ) throws -> CGRect? {
    let points = try observation.recognizedPoints(.all).values.filter {
      $0.confidence >= minimumJointConfidence
    }
    guard !points.isEmpty else { return nil }

    let minimumX = points.map(\.location.x).min() ?? 0
    let maximumX = points.map(\.location.x).max() ?? 0
    let minimumY = points.map(\.location.y).min() ?? 0
    let maximumY = points.map(\.location.y).max() ?? 0
    let width = maximumX - minimumX
    let height = maximumY - minimumY
    guard width > 0, height > 0 else { return nil }
    return CGRect(x: minimumX, y: minimumY, width: width, height: height)
  }

  private func paddedSquareBounds(
    around detectedBounds: CGRect,
    within imageBounds: CGRect
  ) -> CGRect? {
    let requestedSide =
      max(detectedBounds.width, detectedBounds.height)
      * (1 + 2 * padding)
    let side = min(
      ceil(requestedSide),
      floor(min(imageBounds.width, imageBounds.height))
    )
    guard side > 0 else { return nil }

    let center = CGPoint(x: detectedBounds.midX, y: detectedBounds.midY)
    let minimumX = min(
      max(floor(center.x - side / 2), imageBounds.minX),
      imageBounds.maxX - side
    )
    let minimumY = min(
      max(floor(center.y - side / 2), imageBounds.minY),
      imageBounds.maxY - side
    )
    return CGRect(x: minimumX, y: minimumY, width: side, height: side)
  }

  private func resize(_ image: CGImage) -> CGImage? {
    guard
      let context = CGContext(
        data: nil,
        width: outputSize,
        height: outputSize,
        bitsPerComponent: 8,
        bytesPerRow: outputSize * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }
    context.interpolationQuality = .high
    context.draw(
      image,
      in: CGRect(x: 0, y: 0, width: outputSize, height: outputSize)
    )
    return context.makeImage()
  }
}

private enum VisionHandCropError: Error {
  case invalidDetectedBounds
  case outputCreationFailed
}
