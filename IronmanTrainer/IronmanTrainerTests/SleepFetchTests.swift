import XCTest
import HealthKit
@testable import Race1_Trainer

/// Tests for `HealthKitManager.summarizeSleep` — the pure helper used by
/// `fetchSleepData(for:)`. Covers the source variants called out in PRD
/// §11.1 test strategy: Apple Watch (stages), iPhone (asleep only), third-
/// party (asleepUnspecified), and the no-data case.
final class SleepFetchTests: XCTestCase {

    /// Build an HKCategorySample with a given value, source name, and
    /// duration. Uses a synthetic source name so tests don't depend on a
    /// real Apple Watch pairing.
    private func sample(
        value: HKCategoryValueSleepAnalysis,
        minutes: Int,
        sourceName: String,
        start: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> HKCategorySample {
        let end = start.addingTimeInterval(TimeInterval(minutes) * 60)
        let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        return HKCategorySample(
            type: type,
            value: value.rawValue,
            start: start,
            end: end,
            metadata: nil
        )
    }

    // MARK: - Empty

    func testSummarize_noSamples_returnsNil() {
        let result = HealthKitManager.summarizeSleep(samples: [], nightOf: Date())
        XCTAssertNil(result)
    }

    // MARK: - Apple Watch (stages present)

    func testSummarize_appleWatchStages() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            sample(value: .asleepCore, minutes: 200, sourceName: "Apple Watch", start: base),
            sample(value: .asleepDeep, minutes: 60, sourceName: "Apple Watch", start: base.addingTimeInterval(3600)),
            sample(value: .asleepREM, minutes: 90, sourceName: "Apple Watch", start: base.addingTimeInterval(7200)),
            sample(value: .awake, minutes: 10, sourceName: "Apple Watch", start: base.addingTimeInterval(10800)),
        ]

        guard let result = HealthKitManager.summarizeSleep(samples: samples, nightOf: base) else {
            return XCTFail("Expected a summary")
        }

        XCTAssertEqual(result.totalSleepMinutes, 200 + 60 + 90)
        XCTAssertEqual(result.deepSleepMinutes, 60)
        XCTAssertEqual(result.remSleepMinutes, 90)
        XCTAssertEqual(result.awakeMinutes, 10)
        XCTAssertFalse(result.source.isEmpty)
    }

    // MARK: - iPhone (asleep only, no stages)

    func testSummarize_iPhoneAsleepOnly() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            sample(value: .asleepUnspecified, minutes: 420, sourceName: "iPhone", start: base),
        ]

        guard let result = HealthKitManager.summarizeSleep(samples: samples, nightOf: base) else {
            return XCTFail("Expected a summary")
        }

        XCTAssertEqual(result.totalSleepMinutes, 420)
        // No stage samples → stage fields should be nil per v1 contract.
        XCTAssertNil(result.deepSleepMinutes)
        XCTAssertNil(result.remSleepMinutes)
        XCTAssertNil(result.awakeMinutes)
    }

    // MARK: - Third-party

    func testSummarize_thirdPartyAsleepUnspecified() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            sample(value: .asleepUnspecified, minutes: 390, sourceName: "Sleep++", start: base),
            sample(value: .inBed, minutes: 450, sourceName: "Sleep++", start: base),
        ]

        guard let result = HealthKitManager.summarizeSleep(samples: samples, nightOf: base) else {
            return XCTFail("Expected a summary")
        }

        XCTAssertEqual(result.totalSleepMinutes, 390)
        XCTAssertEqual(result.timeInBedMinutes, 450)
        XCTAssertNil(result.deepSleepMinutes)
    }

    // MARK: - In-bed inference

    func testSummarize_approximatesInBedWhenMissing() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            sample(value: .asleepCore, minutes: 300, sourceName: "Apple Watch", start: base),
            sample(value: .awake, minutes: 15, sourceName: "Apple Watch", start: base.addingTimeInterval(3600)),
        ]

        guard let result = HealthKitManager.summarizeSleep(samples: samples, nightOf: base) else {
            return XCTFail("Expected a summary")
        }
        XCTAssertEqual(result.totalSleepMinutes, 300)
        // No inBed sample: approximate as asleep + awake.
        XCTAssertEqual(result.timeInBedMinutes, 300 + 15)
    }
}
