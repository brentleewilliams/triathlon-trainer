import XCTest
@testable import IronmanTrainer

// WeatherForecast is now accessed via @testable import, but keeping local copy
// for tests that were written against it. Remove duplicate to avoid conflicts.
/*struct WeatherForecast {
    let highTemp: Int // °F
    let lowTemp: Int
    let condition: String
    let windMph: Int
    let humidity: Int

    static func forecast(for date: Date) -> WeatherForecast {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        // Use day-of-month to generate deterministic variation
        // Same date always gives same forecast, different dates vary
        let seed = UInt32(day)

        // Base conditions for the month
        let (baseTempHigh, baseTempLow, baseTempVariance, baseConditions, baseHumidity): (Int, Int, Int, [String], Int) = {
            switch month {
            case 3: // March - Cool and wet (56°F avg)
                return (56, 44, 8, ["Rainy", "Cloudy", "Drizzle", "Partly Cloudy"], 70)
            case 4: // April - Warming up (64°F avg)
                return (64, 48, 10, ["Partly Cloudy", "Sunny", "Cloudy", "Showers"], 60)
            case 5: // May - Spring conditions (72°F avg)
                return (72, 54, 8, ["Sunny", "Mostly Sunny", "Partly Cloudy", "Fair"], 55)
            case 6: // June - Warm (80°F avg)
                return (80, 62, 7, ["Sunny", "Mostly Sunny", "Fair", "Sunny & Warm"], 48)
            case 7: // July - Hot (87°F avg, race is July 19)
                return (87, 68, 6, ["Sunny & Hot", "Hot & Sunny", "Clear", "Sunny"], 42)
            default:
                return (70, 55, 10, ["Partly Cloudy", "Sunny", "Cloudy"], 60)
            }
        }()

        // Generate variation based on day of month (deterministic)
        let tempVariation = Int(seed % UInt32(baseTempVariance + 1)) - baseTempVariance / 2
        let high = baseTempHigh + tempVariation
        let low = baseTempLow + tempVariation

        let conditionIndex = Int(seed % UInt32(baseConditions.count))
        let condition = baseConditions[conditionIndex]

        let windVariation = Int(seed % 8) + 4 // 4-11 mph
        let humidityVariation = Int((seed * 7) % 15) - 7 // ±7% variation
        let humidity = max(30, min(85, baseHumidity + humidityVariation))

        return WeatherForecast(
            highTemp: high,
            lowTemp: low,
            condition: condition,
            windMph: windVariation,
            humidity: humidity
        )
    }
}*/

final class WeatherForecastTests: XCTestCase {

    // MARK: - Determinism Tests

    func testDeterminism_SameDateProducesSameForecast() {
        // Create a date
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!

        // Call forecast multiple times
        let forecast1 = WeatherForecast.forecast(for: date)
        let forecast2 = WeatherForecast.forecast(for: date)
        let forecast3 = WeatherForecast.forecast(for: date)

        // All should be identical
        XCTAssertEqual(forecast1.highTemp, forecast2.highTemp)
        XCTAssertEqual(forecast1.lowTemp, forecast2.lowTemp)
        XCTAssertEqual(forecast1.condition, forecast2.condition)
        XCTAssertEqual(forecast1.windMph, forecast2.windMph)
        XCTAssertEqual(forecast1.humidity, forecast2.humidity)

        XCTAssertEqual(forecast2.highTemp, forecast3.highTemp)
        XCTAssertEqual(forecast2.lowTemp, forecast3.lowTemp)
        XCTAssertEqual(forecast2.condition, forecast3.condition)
        XCTAssertEqual(forecast2.windMph, forecast3.windMph)
        XCTAssertEqual(forecast2.humidity, forecast3.humidity)
    }

    func testDeterminism_DifferentDatesProduceDifferentForecasts() {
        let date1 = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let date2 = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 20))!

        let forecast1 = WeatherForecast.forecast(for: date1)
        let forecast2 = WeatherForecast.forecast(for: date2)

        // At least one value should differ (not guaranteed all differ, but at least one)
        let isDifferent = (forecast1.highTemp != forecast2.highTemp) ||
                         (forecast1.lowTemp != forecast2.lowTemp) ||
                         (forecast1.condition != forecast2.condition) ||
                         (forecast1.windMph != forecast2.windMph) ||
                         (forecast1.humidity != forecast2.humidity)

        XCTAssertTrue(isDifferent, "Different dates should produce different forecasts")
    }

    // MARK: - Seasonal Progression Tests

    func testSeasonalProgression_MarchTemperaturesAreCool() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let forecast = WeatherForecast.forecast(for: date)

        // March should be cool: high around 56°F ± 8
        XCTAssertGreaterThanOrEqual(forecast.highTemp, 48, "March high should be at least 48°F")
        XCTAssertLessThanOrEqual(forecast.highTemp, 64, "March high should be at most 64°F")

        // Low should be cool: around 44°F ± 8
        XCTAssertGreaterThanOrEqual(forecast.lowTemp, 36, "March low should be at least 36°F")
        XCTAssertLessThanOrEqual(forecast.lowTemp, 52, "March low should be at most 52°F")
    }

    func testSeasonalProgression_JulyTemperaturesAreHot() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15))!
        let forecast = WeatherForecast.forecast(for: date)

        // July should be hot: high around 87°F ± 6
        XCTAssertGreaterThanOrEqual(forecast.highTemp, 81, "July high should be at least 81°F")
        XCTAssertLessThanOrEqual(forecast.highTemp, 93, "July high should be at most 93°F")

        // Low should be warm: around 68°F ± 6
        XCTAssertGreaterThanOrEqual(forecast.lowTemp, 62, "July low should be at least 62°F")
        XCTAssertLessThanOrEqual(forecast.lowTemp, 74, "July low should be at most 74°F")
    }

    func testSeasonalProgression_TemperaturesIncreaseOverSeasons() {
        let datesMidMonth: [Date] = [
            Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 15))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 15))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15))!,
        ]

        let forecasts = datesMidMonth.map { WeatherForecast.forecast(for: $0) }
        let highTemps = forecasts.map { $0.highTemp }

        // General trend should be increasing (allowing for daily variation)
        // Check that July is warmer than March
        XCTAssertGreaterThan(highTemps[4], highTemps[0], "July should be warmer than March")

        // May should be warmer than March
        XCTAssertGreaterThan(highTemps[2], highTemps[0], "May should be warmer than March")
    }

    // MARK: - Weather Condition Tests

    func testWeatherConditions_MarchHasRainRelatedConditions() {
        // Sample multiple days in March
        let marchDates = (1...28).map { day in
            Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: day))!
        }

        let conditions = Set(marchDates.map { WeatherForecast.forecast(for: $0).condition })
        let expectedMarchConditions = Set(["Rainy", "Cloudy", "Drizzle", "Partly Cloudy"])

        // All found conditions should be in the expected set
        XCTAssertTrue(conditions.isSubset(of: expectedMarchConditions),
                     "March conditions should be from: \(expectedMarchConditions), but found: \(conditions)")
    }

    func testWeatherConditions_JulyHasSunnyConditions() {
        // Sample multiple days in July
        let julyDates = (1...28).map { day in
            Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: day))!
        }

        let conditions = Set(julyDates.map { WeatherForecast.forecast(for: $0).condition })
        let expectedJulyConditions = Set(["Sunny & Hot", "Hot & Sunny", "Clear", "Sunny"])

        // All found conditions should be in the expected set
        XCTAssertTrue(conditions.isSubset(of: expectedJulyConditions),
                     "July conditions should be from: \(expectedJulyConditions), but found: \(conditions)")
    }

    func testWeatherConditions_ConditionIsNotEmpty() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let forecast = WeatherForecast.forecast(for: date)

        XCTAssertFalse(forecast.condition.isEmpty, "Condition should not be empty")
    }

    // MARK: - Temperature Bounds Tests

    func testTemperatureBounds_HighTempAlwaysGreaterThanLowTemp() {
        // Test across multiple dates and months
        let testDates = [
            Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 15))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 28))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 10))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 19))!,
        ]

        for date in testDates {
            let forecast = WeatherForecast.forecast(for: date)
            XCTAssertGreaterThan(forecast.highTemp, forecast.lowTemp,
                               "High temp should be greater than low temp for \(date)")
        }
    }

    func testTemperatureBounds_March() {
        let testDates = (1...28).map { day in
            Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: day))!
        }

        for date in testDates {
            let forecast = WeatherForecast.forecast(for: date)
            XCTAssertGreaterThanOrEqual(forecast.highTemp, 40, "March high should be at least 40°F")
            XCTAssertLessThanOrEqual(forecast.highTemp, 70, "March high should be at most 70°F")
            XCTAssertGreaterThanOrEqual(forecast.lowTemp, 30, "March low should be at least 30°F")
            XCTAssertLessThanOrEqual(forecast.lowTemp, 60, "March low should be at most 60°F")
        }
    }

    func testTemperatureBounds_July() {
        let testDates = (1...31).map { day in
            Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: day))!
        }

        for date in testDates {
            let forecast = WeatherForecast.forecast(for: date)
            XCTAssertGreaterThanOrEqual(forecast.highTemp, 75, "July high should be at least 75°F")
            XCTAssertLessThanOrEqual(forecast.highTemp, 100, "July high should be at most 100°F")
            XCTAssertGreaterThanOrEqual(forecast.lowTemp, 55, "July low should be at least 55°F")
            XCTAssertLessThanOrEqual(forecast.lowTemp, 85, "July low should be at most 85°F")
        }
    }

    // MARK: - Humidity Tests

    func testHumidity_WithinValidRange() {
        // Test across multiple dates
        let testDates = (1...31).map { day in
            Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: day))!
        }

        for date in testDates {
            let forecast = WeatherForecast.forecast(for: date)
            XCTAssertGreaterThanOrEqual(forecast.humidity, 30, "Humidity should be at least 30%")
            XCTAssertLessThanOrEqual(forecast.humidity, 85, "Humidity should be at most 85%")
        }
    }

    func testHumidity_JulyHasLowerHumidityThanMarch() {
        // Sample midmonth dates
        let marchDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let julyDate = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15))!

        let marchForecast = WeatherForecast.forecast(for: marchDate)
        let julyForecast = WeatherForecast.forecast(for: julyDate)

        // July should generally have lower humidity (base: 42) than March (base: 70)
        XCTAssertLessThan(julyForecast.humidity, marchForecast.humidity,
                         "July should have lower humidity than March")
    }

    // MARK: - Wind Tests

    func testWind_WithinValidRange() {
        // Test across multiple dates
        let testDates = (1...31).map { day in
            Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: day))!
        }

        for date in testDates {
            let forecast = WeatherForecast.forecast(for: date)
            XCTAssertGreaterThanOrEqual(forecast.windMph, 4, "Wind should be at least 4 mph")
            XCTAssertLessThanOrEqual(forecast.windMph, 11, "Wind should be at most 11 mph")
        }
    }

    // MARK: - Daily Variation Tests

    func testDailyVariation_VariationExistsWithinMonth() {
        // Sample all days in May
        let mayDates = (1...31).map { day in
            Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: day))!
        }

        let forecasts = mayDates.map { WeatherForecast.forecast(for: $0) }
        let highTemps = forecasts.map { $0.highTemp }
        let conditions = forecasts.map { $0.condition }

        // Should have variation in temps
        let uniqueHighTemps = Set(highTemps)
        XCTAssertGreaterThan(uniqueHighTemps.count, 1, "Should have variation in high temps throughout month")

        // Should have variety in conditions (at least 2 different conditions)
        let uniqueConditions = Set(conditions)
        XCTAssertGreaterThan(uniqueConditions.count, 1, "Should have variety in conditions throughout month")
    }

    func testDailyVariation_DateWithinMonthDeterminesVariation() {
        // Same day of month in different years should have same forecast
        let date1 = Calendar.current.date(from: DateComponents(year: 2025, month: 5, day: 15))!
        let date2 = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 15))!
        let date3 = Calendar.current.date(from: DateComponents(year: 2027, month: 5, day: 15))!

        let forecast1 = WeatherForecast.forecast(for: date1)
        let forecast2 = WeatherForecast.forecast(for: date2)
        let forecast3 = WeatherForecast.forecast(for: date3)

        // All should be the same since they use the same day and month
        XCTAssertEqual(forecast1.highTemp, forecast2.highTemp)
        XCTAssertEqual(forecast2.highTemp, forecast3.highTemp)
        XCTAssertEqual(forecast1.condition, forecast2.condition)
        XCTAssertEqual(forecast2.condition, forecast3.condition)
    }

    // MARK: - Month Boundary Tests

    func testMonthBoundary_LastDayOfMarch() {
        let marchLastDay = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 31))!
        let forecast = WeatherForecast.forecast(for: marchLastDay)

        // Should still be March-like
        XCTAssertGreaterThanOrEqual(forecast.highTemp, 40, "Last day of March should have reasonable March temps")
        XCTAssertLessThanOrEqual(forecast.highTemp, 70)
    }

    func testMonthBoundary_FirstDayOfApril() {
        let aprilFirstDay = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let forecast = WeatherForecast.forecast(for: aprilFirstDay)

        // Should be April-like (warmer than March)
        XCTAssertGreaterThanOrEqual(forecast.highTemp, 45, "First day of April should have reasonable April temps")
        XCTAssertLessThanOrEqual(forecast.highTemp, 75)
    }

    func testMonthBoundary_RaceDay() {
        // July 19, 2026 - Race day
        let raceDay = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 19))!
        let forecast = WeatherForecast.forecast(for: raceDay)

        // Should be hot and sunny (July conditions)
        XCTAssertGreaterThanOrEqual(forecast.highTemp, 80, "Race day should be warm")
        XCTAssertLessThanOrEqual(forecast.humidity, 50, "Race day July humidity should be relatively low")

        // Condition should be from July set
        let julyConditions = ["Sunny & Hot", "Hot & Sunny", "Clear", "Sunny"]
        XCTAssertTrue(julyConditions.contains(forecast.condition),
                     "Race day should have sunny/hot condition")
    }

    // MARK: - Edge Cases

    func testEdgeCase_Day1OfMonth() {
        let dates = [
            Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1))!,
        ]

        for date in dates {
            let forecast = WeatherForecast.forecast(for: date)
            // Should produce valid forecast
            XCTAssertGreaterThan(forecast.highTemp, forecast.lowTemp)
            XCTAssertFalse(forecast.condition.isEmpty)
            XCTAssertGreaterThanOrEqual(forecast.humidity, 30)
        }
    }

    func testEdgeCase_LastDayOfMonth() {
        let dates = [
            Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 31))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 31))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 31))!,
        ]

        for date in dates {
            let forecast = WeatherForecast.forecast(for: date)
            // Should produce valid forecast
            XCTAssertGreaterThan(forecast.highTemp, forecast.lowTemp)
            XCTAssertFalse(forecast.condition.isEmpty)
            XCTAssertLessThanOrEqual(forecast.humidity, 85)
        }
    }

    // MARK: - Comprehensive Determinism Verification

    func testDeterminism_ComprehensiveMultipleCalls() {
        // Create dates spanning the training period
        let trainingDates = [
            Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 23))!, // Start
            Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 15))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 10))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1))!,
            Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 19))!, // Race
        ]

        for date in trainingDates {
            // Call forecast 5 times
            let results = (0..<5).map { _ in WeatherForecast.forecast(for: date) }

            // All should be identical
            let first = results[0]
            for i in 1..<results.count {
                let current = results[i]
                XCTAssertEqual(first.highTemp, current.highTemp, "Determinism failed for date: \(date)")
                XCTAssertEqual(first.lowTemp, current.lowTemp, "Determinism failed for date: \(date)")
                XCTAssertEqual(first.condition, current.condition, "Determinism failed for date: \(date)")
                XCTAssertEqual(first.windMph, current.windMph, "Determinism failed for date: \(date)")
                XCTAssertEqual(first.humidity, current.humidity, "Determinism failed for date: \(date)")
            }
        }
    }
}
