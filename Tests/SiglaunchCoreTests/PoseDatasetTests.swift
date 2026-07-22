import SiglaunchCore
import XCTest

final class PoseDatasetTests: XCTestCase {
  func testTrainingInputRequiresMinimumSamplesForEveryLabel() {
    let samples = makeSamples(domainExpansionCount: 10, otherCount: 9)
    let summary = makeSummary(domainExpansionCount: 10, otherCount: 9)

    XCTAssertNil(
      PoseDatasetTrainingInput(
        directoryPath: "/prepared",
        samples: samples,
        summary: summary
      )
    )
  }

  func testTrainingInputRequiresSummaryToMatchLabeledSamples() {
    let samples = makeSamples(domainExpansionCount: 10, otherCount: 10)
    let mismatchedSummary = makeSummary(domainExpansionCount: 11, otherCount: 10)

    XCTAssertNil(
      PoseDatasetTrainingInput(
        directoryPath: "/prepared",
        samples: samples,
        summary: mismatchedSummary
      )
    )
  }

  func testTrainingInputAcceptsConsistentTrainableSamples() {
    let samples = makeSamples(domainExpansionCount: 10, otherCount: 10)
    let summary = makeSummary(domainExpansionCount: 10, otherCount: 10)

    XCTAssertNotNil(
      PoseDatasetTrainingInput(
        directoryPath: "/prepared",
        samples: samples,
        summary: summary
      )
    )
  }

  private func makeSamples(
    domainExpansionCount: Int,
    otherCount: Int
  ) -> [PoseDatasetSample] {
    makeSamples(label: .domainExpansion, count: domainExpansionCount)
      + makeSamples(label: .other, count: otherCount)
  }

  private func makeSamples(
    label: PoseDatasetLabel,
    count: Int
  ) -> [PoseDatasetSample] {
    (0..<count).map { index in
      PoseDatasetSample(
        label: label,
        imagePath: "/prepared/\(label.rawValue)/\(index).png"
      )
    }
  }

  private func makeSummary(
    domainExpansionCount: Int,
    otherCount: Int
  ) -> PoseDatasetSummary {
    PoseDatasetSummary(
      domainExpansion: PoseDatasetLabelSummary(
        validImageCount: domainExpansionCount,
        handlessImageCount: 0,
        unreadableImageCount: 0
      ),
      other: PoseDatasetLabelSummary(
        validImageCount: otherCount,
        handlessImageCount: 0,
        unreadableImageCount: 0
      )
    )
  }
}
