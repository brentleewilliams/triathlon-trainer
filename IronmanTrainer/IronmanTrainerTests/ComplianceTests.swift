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

    func testDeviation_TwentyOnePercentIsYellow() {
        XCTAssertEqual(complianceLevelFromDeviation(0.21), .yellow)
    }

    func testDeviation_FiftyPercentIsYellow() {
        XCTAssertEqual(complianceLevelFromDeviation(0.50), .yellow)
    }

    func testDeviation_FiftyOnePercentIsRed() {
        XCTAssertEqual(complianceLevelFromDeviation(0.51), .red)
    }

    func testDeviation_OneHundredPercentIsRed() {
        XCTAssertEqual(complianceLevelFromDeviation(1.0), .red)
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

    func testComplianceLevel_YellowIconName() {
        XCTAssertEqual(ComplianceLevel.yellow.iconName, "exclamationmark.circle.fill")
    }

    func testComplianceLevel_RedIconName() {
        XCTAssertEqual(ComplianceLevel.red.iconName, "xmark.circle.fill")
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

    func testCompliance_PastDayNoMatch_ReturnsRed() {
        let pastDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let workout = DayWorkout(day: "Mon", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: nil)
        let result = calculateCompliance(for: workout, on: pastDate, from: [])
        XCTAssertEqual(result.level, .red)
    }

    func testCompliance_TodayNoMatch_ReturnsFuture() {
        let workout = DayWorkout(day: "Mon", type: "\u{1F6B4} Bike", duration: "1:00", zone: "Z2", status: nil, nutritionTarget: nil)
        let result = calculateCompliance(for: workout, on: Date(), from: [], today: Date())
        XCTAssertEqual(result.level, .future)
    }

    // MARK: - Equatable Conformance (for test assertions)
}

extension ComplianceLevel: Equatable {}
