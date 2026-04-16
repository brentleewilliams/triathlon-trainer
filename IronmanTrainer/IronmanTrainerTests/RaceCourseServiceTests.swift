import XCTest
@testable import Race1_Trainer

final class RaceCourseServiceTests: XCTestCase {

    var service: RaceCourseService!

    @MainActor
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "raceCourse.athleteEnvironment")
        UserDefaults.standard.removeObject(forKey: "raceCourse.environmentInferredOnce")
        service = RaceCourseService()
    }

    @MainActor
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "raceCourse.athleteEnvironment")
        UserDefaults.standard.removeObject(forKey: "raceCourse.environmentInferredOnce")
        service = nil
        super.tearDown()
    }

    // MARK: - getAltitudeAdjustment

    func testAltitudeAdjustment_DenverToSalem_IsAdvantage() {
        // Denver 5280ft → Salem 150ft: 5130ft descent.
        let ctx = service.getAltitudeAdjustment(trainingElevation: 5280, raceElevation: 150)
        XCTAssertEqual(ctx.deltaFeet, 5130)
        XCTAssertGreaterThan(ctx.hrAdjustmentBpm, 0, "HR should be lower at lower elevation")
        XCTAssertGreaterThan(ctx.paceAdvantageSecPerMile, 0, "Pace advantage positive descending")
        // 5.13 * 3 = 15.39 → 15
        XCTAssertEqual(ctx.hrAdjustmentBpm, 15)
        // 5.13 * 6 = 30.78 → 30
        XCTAssertEqual(ctx.paceAdvantageSecPerMile, 30)
        XCTAssertTrue(ctx.summary.contains("Advantage") || ctx.summary.lowercased().contains("advantage")
            || ctx.summary.contains("lower HR"))
    }

    func testAltitudeAdjustment_SeaLevelToMexicoCity_IsDisadvantage() {
        // Sea level → Mexico City ~7350ft. Racing at altitude; penalty.
        let ctx = service.getAltitudeAdjustment(trainingElevation: 0, raceElevation: 7350)
        XCTAssertEqual(ctx.deltaFeet, -7350)
        XCTAssertLessThan(ctx.hrAdjustmentBpm, 0, "HR should be higher at higher elevation")
        XCTAssertLessThan(ctx.paceAdvantageSecPerMile, 0, "Pace penalty when racing at altitude")
        // 7.35 * 3 = 22.05 → -22
        XCTAssertEqual(ctx.hrAdjustmentBpm, -22)
        XCTAssertEqual(ctx.paceAdvantageSecPerMile, -44)
    }

    func testAltitudeAdjustment_SameElevation_NoAdjustment() {
        let ctx = service.getAltitudeAdjustment(trainingElevation: 500, raceElevation: 500)
        XCTAssertEqual(ctx.deltaFeet, 0)
        XCTAssertEqual(ctx.hrAdjustmentBpm, 0)
        XCTAssertEqual(ctx.paceAdvantageSecPerMile, 0)
    }

    func testAltitudeAdjustment_NearZeroDelta_NoAdjustment() {
        let ctx = service.getAltitudeAdjustment(trainingElevation: 800, raceElevation: 1000)
        XCTAssertEqual(ctx.hrAdjustmentBpm, 0)
        XCTAssertEqual(ctx.paceAdvantageSecPerMile, 0)
    }

    // MARK: - getPhaseContext

    @MainActor
    func testGetPhaseContext_AtTwelveWeeks_OnlyAlwaysTier() {
        let profile = BundledCourseProfiles.ironman703Oregon2026
        let context = service.getPhaseContext(weeksToRace: 12, profile: profile)
        XCTAssertTrue(context.contains("always"), "Expected Always tier header")
        XCTAssertFalse(context.contains("≤5 weeks"), "Should not include +5wk tier at 12 weeks")
        XCTAssertFalse(context.contains("≤2 weeks"), "Should not include +2wk tier at 12 weeks")
    }

    @MainActor
    func testGetPhaseContext_AtFiveWeeks_IncludesFiveWeekTier() {
        let profile = BundledCourseProfiles.ironman703Oregon2026
        let context = service.getPhaseContext(weeksToRace: 5, profile: profile)
        XCTAssertTrue(context.contains("always"))
        XCTAssertTrue(context.contains("≤5 weeks"), "Expected +5wk tier")
        XCTAssertFalse(context.contains("≤2 weeks"))
    }

    @MainActor
    func testGetPhaseContext_AtTwoWeeks_IncludesAllTiers() {
        let profile = BundledCourseProfiles.ironman703Oregon2026
        let context = service.getPhaseContext(weeksToRace: 2, profile: profile)
        XCTAssertTrue(context.contains("always"))
        XCTAssertTrue(context.contains("≤5 weeks"))
        XCTAssertTrue(context.contains("≤2 weeks"))
    }

    @MainActor
    func testGetPhaseContext_AtZeroWeeks_IncludesAllTiers() {
        let profile = BundledCourseProfiles.ironman703Oregon2026
        let context = service.getPhaseContext(weeksToRace: 0, profile: profile)
        XCTAssertTrue(context.contains("always"))
        XCTAssertTrue(context.contains("≤5 weeks"))
        XCTAssertTrue(context.contains("≤2 weeks"))
    }

    // MARK: - Pacing Strategy

    @MainActor
    func testGetPacingStrategy_NoThresholds_NoNumericTargets() {
        let profile = BundledCourseProfiles.ironman703Oregon2026
        let athlete = AthleteData(
            thresholds: .empty,
            environment: service.athleteEnvironment
        )
        let plan = service.getPacingStrategy(profile: profile, athleteData: athlete)
        XCTAssertFalse(plan.hasNumericTargets)
        XCTAssertEqual(plan.targets.count, 3)
        for target in plan.targets {
            XCTAssertNil(target.numericTarget, "No thresholds → numeric target should be nil")
            XCTAssertFalse(target.effortDescriptor.isEmpty)
        }
    }

    @MainActor
    func testGetPacingStrategy_WithThresholds_NumericTargetsPresent() {
        let profile = BundledCourseProfiles.ironman703Oregon2026
        var t = PerformanceThresholds.empty
        t.ftpWatts = 220
        t.thresholdPaceSecondsPerMile = 450 // 7:30/mi
        t.cssSecondsPer100yd = 95
        let athlete = AthleteData(thresholds: t, environment: service.athleteEnvironment)
        let plan = service.getPacingStrategy(profile: profile, athleteData: athlete)
        XCTAssertTrue(plan.hasNumericTargets)
        let bike = plan.targets.first { $0.discipline == .bike }
        XCTAssertNotNil(bike?.numericTarget)
        XCTAssertTrue(bike?.numericTarget?.contains("W") ?? false)
    }

    // MARK: - Bundled profile sanity

    func testBundledOregonProfile_IsLoadable() {
        // Non-isolated access is fine for read-only static bundle.
        let p = BundledCourseProfiles.ironman703Oregon2026
        XCTAssertEqual(p.raceId, "im703-oregon-2026")
        XCTAssertEqual(p.venueElevationFeet, 150)
        XCTAssertEqual(p.terrain, .rolling)
        XCTAssertEqual(p.dataSource, .bundled)
    }

    // MARK: - formatMinSecPace

    func testFormatMinSecPace_TypicalValues() {
        // 7:30/mi → 450s
        XCTAssertEqual(RaceCourseService.formatMinSecPace(seconds: 450), "7:30")
        // 1:35/100yd → 95s
        XCTAssertEqual(RaceCourseService.formatMinSecPace(seconds: 95), "1:35")
        // Edge: exactly at a minute
        XCTAssertEqual(RaceCourseService.formatMinSecPace(seconds: 60), "1:00")
    }

    func testFormatMinSecPace_PadsSingleDigitSeconds() {
        // 5:05 — critical the seconds are zero-padded.
        XCTAssertEqual(RaceCourseService.formatMinSecPace(seconds: 305), "5:05")
        XCTAssertEqual(RaceCourseService.formatMinSecPace(seconds: 9), "0:09")
    }

    // MARK: - Environment persistence round-trip

    @MainActor
    func testSaveEnvironment_PersistsAcrossInstances() {
        var env = service.athleteEnvironment
        env.trainingElevationFeet = 4321
        env.trainingClimate = "arid desert"
        env.poolAccess = false
        service.saveEnvironment(env)

        // Fresh instance reads from UserDefaults.
        let reloaded = RaceCourseService()
        XCTAssertEqual(reloaded.athleteEnvironment.trainingElevationFeet, 4321)
        XCTAssertEqual(reloaded.athleteEnvironment.trainingClimate, "arid desert")
        XCTAssertFalse(reloaded.athleteEnvironment.poolAccess)
    }

    @MainActor
    func testLoadEnvironment_CorruptDataFallsBackToDefaults() {
        // Simulate a schema-incompatible blob in the persisted env key.
        UserDefaults.standard.set(Data([0x00, 0xFF, 0x00]), forKey: "raceCourse.athleteEnvironment")
        let reloaded = RaceCourseService()
        XCTAssertEqual(reloaded.athleteEnvironment.trainingClimate,
                       AthleteEnvironment.defaultInferred().trainingClimate,
                       "Corrupt env data should not crash; should fall back to defaults")
    }

    // MARK: - Climate classification heuristic

    func testClimateClassification_Oregon_IsTemperateMarine() {
        XCTAssertEqual(RaceCourseService.climateClassification(adminArea: "Oregon"), "temperate marine")
    }

    func testClimateClassification_Colorado_IsSemiArid() {
        XCTAssertEqual(RaceCourseService.climateClassification(adminArea: "Colorado"), "semi-arid, dry heat")
    }

    func testClimateClassification_Florida_IsHumidSubtropical() {
        XCTAssertEqual(RaceCourseService.climateClassification(adminArea: "Florida"), "humid subtropical")
    }

    func testClimateClassification_Unknown_DefaultsToTemperateMarine() {
        XCTAssertEqual(RaceCourseService.climateClassification(adminArea: nil), "temperate marine")
        XCTAssertEqual(RaceCourseService.climateClassification(adminArea: "Mars"), "temperate marine")
    }
}
