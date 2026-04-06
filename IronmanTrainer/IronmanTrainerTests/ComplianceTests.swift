import XCTest
@testable import IronmanTrainer

final class ComplianceTests: XCTestCase {

    // MARK: - complianceLevelFromDeviation Tests

    func testDeviation_ZeroIsGreen() {
        XCTAssertEqual(complianceLevelFromDeviation(0.0), .green)
    }

    func testDeviation_TenPercentIsGreen() {
        XCTAssertEqual(complianceLevelFromDeviation(0.10), .green)
    }

    func testDeviation_TwentyPercentIsGreen() {
        XCTAssertEqual(complianceLevelFromDeviation(0.20), .green)
    }

    func testDeviation_TwentyOnePercentIsOver() {
        XCTAssertEqual(complianceLevelFromDeviation(0.21), .over)
    }

    func testDeviation_FiftyPercentIsOver() {
        XCTAssertEqual(complianceLevelFromDeviation(0.50), .over)
    }

    func testDeviation_FiftyOnePercentIsOver() {
        XCTAssertEqual(complianceLevelFromDeviation(0.51), .over)
    }

    func testDeviation_OneHundredPercentIsOver() {
        XCTAssertEqual(complianceLevelFromDeviation(1.0), .over)
    }

    // MARK: - Direction-Aware Compliance Tests

    func testComplianceValues_Overtraining() {
        XCTAssertEqual(complianceLevelFromValues(actual: 90, planned: 60), .over)
    }

    func testComplianceValues_Undertraining() {
        XCTAssertEqual(complianceLevelFromValues(actual: 30, planned: 60), .under)
    }

    func testComplianceValues_OnTarget() {
        XCTAssertEqual(complianceLevelFromValues(actual: 55, planned: 60), .green)
        XCTAssertEqual(complianceLevelFromValues(actual: 70, planned: 60), .green)
    }

    // MARK: - parseYardDistance Tests

    func testParseYardDistance_Standard() {
        XCTAssertEqual(parseYardDistance("1,800yd"), 1800.0)
    }

    func testParseYardDistance_TwoThousand() {
        XCTAssertEqual(parseYardDistance("2,000yd"), 2000.0)
    }

    func testParseYardDistance_ThreeThousandTwo() {
        XCTAssertEqual(parseYardDistance("3,200yd"), 3200.0)
    }

    func testParseYardDistance_NoComma() {
        XCTAssertEqual(parseYardDistance("1800yd"), 1800.0)
    }

    func testParseYardDistance_MinutesReturnsNil() {
        XCTAssertNil(parseYardDistance("60min"))
    }

    func testParseYardDistance_ColonFormatReturnsNil() {
        XCTAssertNil(parseYardDistance("1:00"))
    }

    func testParseYardDistance_RestReturnsNil() {
        XCTAssertNil(parseYardDistance("Rest"))
    }

    func testParseYardDistance_DashReturnsNil() {
        XCTAssertNil(parseYardDistance("-"))
    }

    // MARK: - ComplianceLevel Properties

    func testComplianceLevel_GreenIconName() {
        XCTAssertEqual(ComplianceLevel.green.iconName, "checkmark.circle.fill")
    }

    func testComplianceLevel_OverIconName() {
        XCTAssertEqual(ComplianceLevel.over.iconName, "arrow.up.circle.fill")
    }

    func testComplianceLevel_UnderIconName() {
        XCTAssertEqual(ComplianceLevel.under.iconName, "arrow.down.circle.fill")
    }

    func testComplianceLevel_MissedIconName() {
        XCTAssertEqual(ComplianceLevel.missed.iconName, "xmark.circle.fill")
    }

    func testComplianceLevel_MissedColor() {
        XCTAssertEqual(ComplianceLevel.missed.color, .red)
    }

    func testComplianceLevel_OverColor() {
        XCTAssertEqual(ComplianceLevel.over.color, .yellow)
    }

    func testComplianceLevel_UnderColor() {
        XCTAssertEqual(ComplianceLevel.under.color, .yellow)
    }

    func testComplianceLevel_FutureIconName() {
        XCTAssertEqual(ComplianceLevel.future.iconName, "circle")
    }

    // MARK: - calculateCompliance Edge Cases

    func testCompliance_RestDay_ReturnsFuture() {
        let rest = DayWorkout(day: "Mon", type: "Rest", duration: "-", zone: "-", status: nil, nutritionTarget: nil)
        let result = calculateCompliance(for: rest, on: Date(), from: [])
        XCTAssertEqual(result.level, .future)
    }

    func testCompliance_FutureDay_ReturnsFuture() {
        let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let workout = DayWorkout(day: "Mon", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: nil)
        let result = calculateCompliance(for: workout, on: futureDate, from: [])
        XCTAssertEqual(result.level, .future)
    }

    func testCompliance_PastDayNoMatch_ReturnsMissed() {
        let pastDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let workout = DayWorkout(day: "Mon", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: nil)
        let result = calculateCompliance(for: workout, on: pastDate, from: [])
        XCTAssertEqual(result.level, .missed)
    }

    func testCompliance_TodayNoMatch_ReturnsFuture() {
        let workout = DayWorkout(day: "Mon", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: nil)
        let result = calculateCompliance(for: workout, on: Date(), from: [], today: Date())
        XCTAssertEqual(result.level, .future)
    }

    // MARK: - Equatable Conformance (for test assertions)
}

extension ComplianceLevel: Equatable {}
