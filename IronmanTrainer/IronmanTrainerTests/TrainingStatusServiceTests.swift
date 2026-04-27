import XCTest
@testable import Race1_Trainer

@MainActor
final class TrainingStatusServiceTests: XCTestCase {

    // MARK: - HRSS

    func testHRSS_typicalRun() {
        // durationHours=1.0, avgHR=155, maxHR=182
        // LTHR = 182 * 0.89 = 161.98
        // HRSS = 1.0 * (155/161.98)^2 * 100 ≈ 91.9
        let result = TrainingStatusService.computeHRSS(durationHours: 1.0, avgHR: 155, maxHR: 182)
        XCTAssertEqual(result, 91.9, accuracy: 0.5, "HRSS for a typical 1-hour run should be ≈91.9")
    }

    func testHRSS_zeroDuration() {
        let result = TrainingStatusService.computeHRSS(durationHours: 0, avgHR: 155, maxHR: 182)
        XCTAssertEqual(result, 0.0, accuracy: 0.001, "Zero duration should produce zero HRSS")
    }

    func testHRSS_hrAboveLTHR() {
        // avgHR=180 > LTHR=162.18, so score should be > 100
        let result = TrainingStatusService.computeHRSS(durationHours: 1.0, avgHR: 180, maxHR: 182)
        XCTAssertGreaterThan(result, 100, "avgHR above LTHR should produce HRSS > 100")
    }

    // MARK: - EWA

    func testEWA_allZeros() {
        let result = TrainingStatusService.computeEWA(dailyValues: [0, 0, 0, 0, 0], lambda: 0.25)
        XCTAssertEqual(result, 0.0, accuracy: 0.001, "EWA of all zeros should be zero")
    }

    func testEWA_singleDay_seedsFromFirstNonzero() {
        // EWA seeds with the first non-zero value (per PRD §EWA formulas); a single
        // 100-HRSS day leaves ewa = 100 because no subsequent day applies the formula.
        let ctlLambda = 2.0 / 43.0
        let result = TrainingStatusService.computeEWA(dailyValues: [100], lambda: ctlLambda)
        XCTAssertEqual(result, 100, accuracy: 0.001, "A single non-zero day should seed EWA to that value")
    }

    func testEWA_buildRate_ATLOutpacesCTL() {
        // With a rising load (50 → 100), ATL (λ=0.25) should rise faster than CTL (λ≈0.047).
        let ctlLambda = 2.0 / 43.0
        let atlLambda = 0.25
        let ctlResult = TrainingStatusService.computeEWA(dailyValues: [50, 100], lambda: ctlLambda)
        let atlResult = TrainingStatusService.computeEWA(dailyValues: [50, 100], lambda: atlLambda)
        XCTAssertGreaterThan(atlResult, ctlResult, "ATL should respond to rising load faster than CTL")
    }

    func testEWA_decayWithRest() {
        // After a day of 100 HRSS followed by 7 rest days, ATL should decay faster than CTL
        let ctlLambda = 2.0 / 43.0
        let atlLambda = 0.25
        let values = [100.0, 0, 0, 0, 0, 0, 0, 0]
        let ctlResult = TrainingStatusService.computeEWA(dailyValues: values, lambda: ctlLambda)
        let atlResult = TrainingStatusService.computeEWA(dailyValues: values, lambda: atlLambda)
        XCTAssertLessThan(atlResult, ctlResult, "ATL should decay faster than CTL during rest")
    }

    // MARK: - Intensity Pattern

    func testPattern_polarized() {
        // Low Z3, high Z1 + high Z5 → polarized
        let zoneTotals: [String: Double] = ["Z1": 50, "Z2": 30, "Z3": 8, "Z4": 10, "Z5": 2]
        let result = TrainingStatusService.computeIntensityPattern(zoneTotals: zoneTotals)
        XCTAssertEqual(result, .polarized)
    }

    func testPattern_pyramidal() {
        // Descending from Z1 → Z5 → pyramidal
        let zoneTotals: [String: Double] = ["Z1": 40, "Z2": 30, "Z3": 15, "Z4": 10, "Z5": 5]
        let result = TrainingStatusService.computeIntensityPattern(zoneTotals: zoneTotals)
        XCTAssertEqual(result, .pyramidal)
    }

    func testPattern_thresholdHeavy() {
        // High Z3/Z4 relative to other zones → thresholdHeavy
        let zoneTotals: [String: Double] = ["Z1": 20, "Z2": 20, "Z3": 20, "Z4": 15, "Z5": 5]
        let result = TrainingStatusService.computeIntensityPattern(zoneTotals: zoneTotals)
        XCTAssertEqual(result, .thresholdHeavy)
    }

    // MARK: - Load Spike

    func testSpike_none() {
        let spike = TrainingStatusService.computeLoadSpike(currentWeekHRSS: 200, priorWeekHRSS: 190)
        XCTAssertFalse(spike.isSpiked, "A 5% increase should not be flagged as a spike")
    }

    func testSpike_spiked() {
        // 20% increase → spiked
        let spike = TrainingStatusService.computeLoadSpike(currentWeekHRSS: 240, priorWeekHRSS: 200)
        XCTAssertTrue(spike.isSpiked, "A 20% weekly increase should be flagged as a spike")
    }

    func testSpike_critical() {
        // 30% increase → critical
        let spike = TrainingStatusService.computeLoadSpike(currentWeekHRSS: 260, priorWeekHRSS: 200)
        XCTAssertTrue(spike.isCritical, "A 30% weekly increase should be flagged as critical")
    }

    func testSpike_priorZero() {
        // Prior week zero → should not crash, increasePercent == 0
        let spike = TrainingStatusService.computeLoadSpike(currentWeekHRSS: 100, priorWeekHRSS: 0)
        XCTAssertEqual(spike.increasePercent, 0.0, accuracy: 0.001, "Zero prior-week HRSS should yield increasePercent == 0 (no crash)")
    }

    // MARK: - Readiness

    func testReadiness_optimal() {
        // tsb=+15, HRV +12% (≥ +5%), no spike → score ≥ 80
        let hrv = HRVTrend(todaySDNN: 56, sevenDayAvg: 54, sixtyDayBaseline: 50)
        let spike = TrainingStatusService.computeLoadSpike(currentWeekHRSS: 200, priorWeekHRSS: 190)
        let readiness = TrainingStatusService.computeReadiness(tsb: 15, hrvTrend: hrv, loadSpike: spike)
        XCTAssertGreaterThanOrEqual(readiness.score, 80, "Optimal conditions should produce score ≥ 80")
        XCTAssertEqual(readiness.tsbScore, 40, "Positive TSB should yield full tsbScore of 40")
        XCTAssertEqual(readiness.hrvScore, 30, "HRV well above baseline should yield full hrvScore of 30")
        XCTAssertEqual(readiness.loadSpikeScore, 30, "No spike should yield full loadSpikeScore of 30")
    }

    func testReadiness_negativeTSB() {
        let hrv = HRVTrend(todaySDNN: nil, sevenDayAvg: nil, sixtyDayBaseline: nil)
        let spike = TrainingStatusService.computeLoadSpike(currentWeekHRSS: 100, priorWeekHRSS: 90)
        let readiness = TrainingStatusService.computeReadiness(tsb: -25, hrvTrend: hrv, loadSpike: spike)
        XCTAssertEqual(readiness.tsbScore, 0, "Negative TSB should yield tsbScore of 0")
    }

    func testReadiness_lowHRV() {
        // HRV -20% vs baseline (< -10%) → hrvScore == 0
        let hrv = HRVTrend(todaySDNN: 40, sevenDayAvg: 45, sixtyDayBaseline: 50)
        let spike = TrainingStatusService.computeLoadSpike(currentWeekHRSS: 200, priorWeekHRSS: 190)
        let readiness = TrainingStatusService.computeReadiness(tsb: 10, hrvTrend: hrv, loadSpike: spike)
        XCTAssertEqual(readiness.hrvScore, 0, "HRV well below baseline should yield hrvScore of 0")
    }

    func testReadiness_criticalSpike() {
        // 30% spike → loadSpikeScore == 0
        let hrv = HRVTrend(todaySDNN: nil, sevenDayAvg: nil, sixtyDayBaseline: nil)
        let spike = TrainingStatusService.computeLoadSpike(currentWeekHRSS: 260, priorWeekHRSS: 200)
        let readiness = TrainingStatusService.computeReadiness(tsb: 5, hrvTrend: hrv, loadSpike: spike)
        XCTAssertEqual(readiness.loadSpikeScore, 0, "A critical load spike should yield loadSpikeScore of 0")
    }

    // MARK: - Decoupling

    func testDecoupling_raceReady() {
        let result = DecouplingResult(
            workoutDate: Date(),
            discipline: .run,
            decouplingPercent: 1.8,
            durationMinutes: 65
        )
        XCTAssertTrue(result.isRaceReady, "1.8% decoupling on a 65-min run should be race-ready (threshold ≤ ~5%)")
    }

    func testDecoupling_notRaceReady() {
        let result = DecouplingResult(
            workoutDate: Date(),
            discipline: .bike,
            decouplingPercent: 13.6,
            durationMinutes: 90
        )
        XCTAssertFalse(result.isRaceReady, "13.6% decoupling on a 90-min bike should not be race-ready")
    }

    // MARK: - Discipline Gap

    func testGap_missing() {
        let gap = DisciplineGap(
            discipline: .swim,
            daysSinceLastSession: 20,
            weeklySessionCount: 0,
            ctlVsHighest: 0.1
        )
        XCTAssertTrue(gap.isMissing, "0 sessions and 20 days since last swim should be flagged as missing")
        XCTAssertEqual(gap.severity, .critical, "A missing discipline should be critical severity")
    }

    func testGap_undertrained() {
        let gap = DisciplineGap(
            discipline: .run,
            daysSinceLastSession: 5,
            weeklySessionCount: 1,
            ctlVsHighest: 0.20
        )
        XCTAssertTrue(gap.isUndertrained, "1 session/week with CTL only 20% of highest should be flagged as undertrained")
        XCTAssertEqual(gap.severity, .warning, "An undertrained discipline should be warning severity")
    }

    func testGap_healthy() {
        let gap = DisciplineGap(
            discipline: .bike,
            daysSinceLastSession: 3,
            weeklySessionCount: 3,
            ctlVsHighest: 0.8
        )
        XCTAssertEqual(gap.severity, .none, "Adequate sessions and CTL ratio should report no severity")
    }

    // MARK: - HRV Trend

    func testHRV_improving() {
        // sevenDayAvg 58 vs baseline 50 → +16% — should be .improving
        let hrv = HRVTrend(todaySDNN: 60, sevenDayAvg: 58, sixtyDayBaseline: 50)
        XCTAssertEqual(hrv.direction, .improving, "HRV 20% above baseline should be direction == .improving")
    }

    func testHRV_declining() {
        // sevenDayAvg 42 vs baseline 50 → -16% — should be .declining
        let hrv = HRVTrend(todaySDNN: 40, sevenDayAvg: 42, sixtyDayBaseline: 50)
        XCTAssertEqual(hrv.direction, .declining, "HRV 20% below baseline should be direction == .declining")
    }

    func testHRV_noData() {
        let hrv = HRVTrend(todaySDNN: nil, sevenDayAvg: nil, sixtyDayBaseline: nil)
        XCTAssertEqual(hrv.direction, .insufficient, "No HRV data should report direction == .insufficient")
    }

    // MARK: - Context String

    private func makeTrainingStatus() -> TrainingStatus {
        let hrv = HRVTrend(todaySDNN: 54, sevenDayAvg: 52, sixtyDayBaseline: 50)
        let spike = LoadSpike(currentWeekHRSS: 200, priorWeekHRSS: 190)
        let readiness = CompositeReadiness(score: 72, tsbScore: 32, hrvScore: 22, loadSpikeScore: 30)
        let combined = FitnessMetrics(discipline: .combined, ctl: 85, atl: 92, lastSessionDaysAgo: 1, weeklySessionCount: 5)
        let swimM = FitnessMetrics(discipline: .swim, ctl: 12, atl: 0, lastSessionDaysAgo: 18, weeklySessionCount: 0)
        let bikeM = FitnessMetrics(discipline: .bike, ctl: 95, atl: 105, lastSessionDaysAgo: 1, weeklySessionCount: 3)
        let runM = FitnessMetrics(discipline: .run, ctl: 78, atl: 82, lastSessionDaysAgo: 2, weeklySessionCount: 2)
        let swimGap = DisciplineGap(discipline: .swim, daysSinceLastSession: 18, weeklySessionCount: 0, ctlVsHighest: 0.12)
        return TrainingStatus(
            computedAt: Date(),
            fitnessPerDiscipline: [combined, swimM, bikeM, runM],
            disciplineGaps: [swimGap],
            disciplineVolumeStatuses: [],
            hrvTrend: hrv,
            recentDecoupling: [],
            intensityPattern: .pyramidal,
            loadSpike: spike,
            readiness: readiness
        )
    }

    func testContextString_brief() {
        let ts = makeTrainingStatus()
        let brief = ts.contextString(brief: true)
        let nonEmptyLines = brief.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertLessThanOrEqual(nonEmptyLines.count, 3, "Brief context string should have ≤ 3 non-empty lines, got \(nonEmptyLines.count)")
    }

    func testContextString_full() {
        let ts = makeTrainingStatus()
        let full = ts.contextString(brief: false)
        XCTAssertTrue(full.contains("CTL"), "Full context string should contain 'CTL'")
        XCTAssertTrue(full.contains("ATL"), "Full context string should contain 'ATL'")
        XCTAssertTrue(full.contains("Form"), "Full context string should contain 'Form'")
    }

    // MARK: - Volume status

    /// When no plan exists, fall back to baseline minutes for all 6 weeks
    /// and produce 100% if the user actually trained the baseline amount.
    func testVolume_noPlan_usesBaseline() {
        let now = Date()
        let cal = Calendar.current

        // No HK workouts at all → 0 actual.
        let result = TrainingStatusService.computeVolumeStatuses(
            workouts: [],
            planWeeks: [],
            baselineMinutes: (swim: 60, bike: 120, run: 90),
            now: now,
            calendar: cal,
            disciplineFor: { _ in nil }
        )
        let swim = result.first { $0.discipline == .swim }!
        XCTAssertEqual(swim.plannedMinutes, 60 * 6, "6 weeks × 60 min baseline")
        XCTAssertEqual(swim.actualMinutes,  0)
        XCTAssertTrue(swim.usedBaselineFallback)
        XCTAssertEqual(swim.severity, .behind)
    }

    /// Taper weeks must drop out of both numerator and denominator.
    func testVolume_taperWeekExcluded() {
        let now = Date()
        var cal = Calendar.current
        cal.firstWeekday = 2

        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let thisMonday = cal.date(from: comps)!

        // Build 6 plan weeks; mark the week 2 weeks ago as Taper.
        var planWeeks: [TrainingWeek] = []
        for offset in (-5...0) {
            let monday = cal.date(byAdding: .weekOfYear, value: offset, to: thisMonday)!
            let sunday = cal.date(byAdding: .day, value: 6, to: monday)!
            let phase = (offset == -2) ? "Taper" : "Build"
            // 60 min planned swim per non-taper week
            let workouts = [
                DayWorkout(day: "Tue", type: "Swim", duration: "60 min", zone: "Z2",
                           status: nil, nutritionTarget: nil)
            ]
            planWeeks.append(TrainingWeek(
                weekNumber: offset + 6,
                phase: phase,
                startDate: monday,
                endDate: sunday,
                workouts: workouts
            ))
        }

        let result = TrainingStatusService.computeVolumeStatuses(
            workouts: [],
            planWeeks: planWeeks,
            baselineMinutes: (swim: 0, bike: 0, run: 0),
            now: now,
            calendar: cal,
            disciplineFor: { _ in nil }
        )
        let swim = result.first { $0.discipline == .swim }!
        XCTAssertEqual(swim.weeksConsidered, 5, "Taper week should drop out of the count")
        XCTAssertEqual(swim.plannedMinutes, 60 * 5, "Taper week's 60 min should be excluded")
        XCTAssertFalse(swim.usedBaselineFallback)
    }
}
