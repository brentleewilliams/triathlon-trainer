import XCTest
@testable import Race1_Trainer

final class CheckInManagerTests: XCTestCase {

    // MARK: - ReadinessScorer

    func testScoreReturnsGreenWithHealthySignals() {
        let snapshot = ReadinessSnapshot(
            sleepHours: 8.0,
            hrvMs: 55,
            hrvBaselineMs: 55,
            restingHR: 52,
            restingHRBaseline: 52
        )
        let score = ReadinessScorer.score(snapshot)
        XCTAssertEqual(score.level, .green)
        XCTAssertTrue(score.flags.isEmpty)
        XCTAssertFalse(score.positives.isEmpty)
    }

    func testScoreReturnsRedOnLowSleep() {
        let snapshot = ReadinessSnapshot(
            sleepHours: 5.0,
            hrvMs: 55,
            hrvBaselineMs: 55,
            restingHR: 52,
            restingHRBaseline: 52
        )
        let score = ReadinessScorer.score(snapshot)
        XCTAssertEqual(score.level, .red)
        XCTAssertTrue(score.flags.contains { $0.contains("Low sleep") })
    }

    func testScoreReturnsYellowOnShortSleep() {
        let snapshot = ReadinessSnapshot(
            sleepHours: 6.5,
            hrvMs: 55,
            hrvBaselineMs: 55,
            restingHR: 52,
            restingHRBaseline: 52
        )
        let score = ReadinessScorer.score(snapshot)
        XCTAssertEqual(score.level, .yellow)
        XCTAssertEqual(score.flags.count, 1)
    }

    func testScoreReturnsRedOnSuppressedHRV() {
        let snapshot = ReadinessSnapshot(
            sleepHours: 8.0,
            hrvMs: 40,                // 27% below baseline
            hrvBaselineMs: 55,
            restingHR: 52,
            restingHRBaseline: 52
        )
        let score = ReadinessScorer.score(snapshot)
        XCTAssertEqual(score.level, .red)
        XCTAssertTrue(score.flags.contains { $0.contains("HRV suppressed") })
    }

    func testScoreReturnsYellowOnMildHRVDrop() {
        let snapshot = ReadinessSnapshot(
            sleepHours: 8.0,
            hrvMs: 48,                // ~13% below baseline
            hrvBaselineMs: 55,
            restingHR: 52,
            restingHRBaseline: 52
        )
        let score = ReadinessScorer.score(snapshot)
        XCTAssertEqual(score.level, .yellow)
    }

    func testScoreReturnsRedOnElevatedRHR() {
        let snapshot = ReadinessSnapshot(
            sleepHours: 8.0,
            hrvMs: 55,
            hrvBaselineMs: 55,
            restingHR: 62,            // +10 bpm
            restingHRBaseline: 52
        )
        let score = ReadinessScorer.score(snapshot)
        XCTAssertEqual(score.level, .red)
        XCTAssertTrue(score.flags.contains { $0.contains("RHR elevated") })
    }

    func testScoreReturnsYellowOnSlightlyElevatedRHR() {
        let snapshot = ReadinessSnapshot(
            sleepHours: 8.0,
            hrvMs: 55,
            hrvBaselineMs: 55,
            restingHR: 57,            // +5 bpm
            restingHRBaseline: 52
        )
        let score = ReadinessScorer.score(snapshot)
        XCTAssertEqual(score.level, .yellow)
    }

    func testTwoYellowFlagsEscalateToRed() {
        let snapshot = ReadinessSnapshot(
            sleepHours: 6.5,          // yellow
            hrvMs: 48,                // yellow (mild HRV drop)
            hrvBaselineMs: 55,
            restingHR: 52,
            restingHRBaseline: 52
        )
        let score = ReadinessScorer.score(snapshot)
        XCTAssertEqual(score.level, .red)
        XCTAssertEqual(score.flags.count, 2)
    }

    func testMissingAllDataReturnsUnknown() {
        let snapshot = ReadinessSnapshot()
        let score = ReadinessScorer.score(snapshot)
        XCTAssertEqual(score.level, .unknown)
        XCTAssertTrue(score.flags.isEmpty)
    }

    func testOnlySleepPresentStillYieldsLevel() {
        // With just one positive data point, we shouldn't promote to green.
        let snapshot = ReadinessSnapshot(sleepHours: 8.0)
        let score = ReadinessScorer.score(snapshot)
        // Sleep is healthy — but only 1 data point, so we return unknown per the >=2 rule.
        XCTAssertEqual(score.level, .unknown)
    }

    func testHRVPresentWithoutBaselineIsNeutralPositive() {
        let snapshot = ReadinessSnapshot(
            sleepHours: 8.0,
            hrvMs: 55,
            hrvBaselineMs: nil,
            restingHR: nil,
            restingHRBaseline: nil
        )
        let score = ReadinessScorer.score(snapshot)
        // sleep positive + hrv positive → green (2 data points)
        XCTAssertEqual(score.level, .green)
        XCTAssertTrue(score.positives.contains { $0.contains("HRV") })
    }

    // MARK: - Codability (persistence round-trip)

    func testReadinessSnapshotRoundTrip() throws {
        let original = ReadinessSnapshot(
            sleepHours: 7.5,
            hrvMs: 48,
            hrvBaselineMs: 55,
            restingHR: 55,
            restingHRBaseline: 52,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReadinessSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDailyCheckInRoundTrip() throws {
        let snapshot = ReadinessSnapshot(
            sleepHours: 7.5,
            hrvMs: 48,
            hrvBaselineMs: 55,
            restingHR: 55,
            restingHRBaseline: 52
        )
        let original = DailyCheckIn(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            readinessLevel: .yellow,
            flags: ["Short sleep"],
            positives: ["HRV 48ms"],
            snapshot: snapshot,
            workoutSummary: "Run 45min · Z2",
            coachMessage: "Ease into today.",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DailyCheckIn.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testFreshnessCheck() {
        let today = Calendar.current.startOfDay(for: Date())
        let checkIn = DailyCheckIn(
            date: today,
            readinessLevel: .green,
            flags: [],
            positives: [],
            snapshot: ReadinessSnapshot(),
            workoutSummary: nil,
            coachMessage: nil,
            generatedAt: Date()
        )
        XCTAssertTrue(checkIn.isFreshFor(date: Date()))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        XCTAssertFalse(checkIn.isFreshFor(date: tomorrow))
    }

    // MARK: - ReadinessLevel mapping

    func testReadinessLevelEmojiAndLabel() {
        XCTAssertEqual(ReadinessLevel.green.label, "Ready")
        XCTAssertEqual(ReadinessLevel.yellow.label, "Caution")
        XCTAssertEqual(ReadinessLevel.red.label, "Recover")
        XCTAssertEqual(ReadinessLevel.unknown.label, "Unknown")
        XCTAssertFalse(ReadinessLevel.green.emoji.isEmpty)
        XCTAssertFalse(ReadinessLevel.yellow.emoji.isEmpty)
        XCTAssertFalse(ReadinessLevel.red.emoji.isEmpty)
        XCTAssertFalse(ReadinessLevel.unknown.emoji.isEmpty)
    }

    // MARK: - Scheduler math

    func testSchedulerReturnsFutureDate() {
        let cal = Calendar.current
        var components = DateComponents(year: 2026, month: 4, day: 14, hour: 10, minute: 0)
        components.timeZone = TimeZone.current
        let reference = cal.date(from: components)!

        // Reminder at 6:30 AM → today's check-in time already passed, so we
        // schedule for tomorrow 6:00 AM (30 min before).
        var reminderComps = DateComponents(year: 2026, month: 4, day: 14, hour: 6, minute: 30)
        reminderComps.timeZone = TimeZone.current
        let reminder = cal.date(from: reminderComps)!

        let next = CheckInScheduler.nextRefreshDate(reminderTime: reminder, reference: reference)
        XCTAssertGreaterThan(next, reference)

        // Should be 30m before tomorrow's 6:30 = tomorrow 6:00
        let diff = next.timeIntervalSince(reference)
        // ~20 hours ahead (10 AM today → 6 AM tomorrow)
        XCTAssertGreaterThan(diff, 19 * 3600)
        XCTAssertLessThan(diff, 21 * 3600)
    }

    func testSchedulerUsesTodayWhenReminderStillFuture() {
        let cal = Calendar.current
        var refComps = DateComponents(year: 2026, month: 4, day: 14, hour: 5, minute: 0)
        refComps.timeZone = TimeZone.current
        let reference = cal.date(from: refComps)!

        var reminderComps = DateComponents(year: 2026, month: 4, day: 14, hour: 6, minute: 30)
        reminderComps.timeZone = TimeZone.current
        let reminder = cal.date(from: reminderComps)!

        let next = CheckInScheduler.nextRefreshDate(reminderTime: reminder, reference: reference)
        // Should be today at 6:00 (30m before 6:30)
        let diff = next.timeIntervalSince(reference)
        XCTAssertGreaterThan(diff, 59 * 60)
        XCTAssertLessThan(diff, 61 * 60)
    }
}
