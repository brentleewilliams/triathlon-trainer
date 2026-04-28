import SwiftUI
import HealthKit

// MARK: - App Theme
/// Centralized design constants and helpers. Use as a namespace — never instantiated.
enum AppTheme {

    // MARK: - Sport Colors
    static let swim     = Color(hex: "0077B6")   // blue
    static let bike     = Color(hex: "14B8A6")   // teal
    static let run      = Color(hex: "E67E22")   // orange
    static let brick    = Color(hex: "DB2777")   // rose (distinct from race-ready red)
    static let strength = Color(hex: "8E44AD")   // purple
    static let rest     = Color(hex: "BDC3C7")   // light grey

    // MARK: - Phase Colors
    static let phaseBase  = Color(hex: "007AFF")
    static let phaseBuild = Color(hex: "FF9500")
    static let phasePeak  = Color(hex: "FF3B30")
    static let phaseTaper = Color(hex: "34C759")

    // MARK: - Status Colors
    static let statusGreen = Color(hex: "34C759")
    static let statusAmber = Color(hex: "FFCC00")
    static let statusRed   = Color(hex: "FF3B30")

    // MARK: - Card Style Constants
    static let cardCornerRadius:  CGFloat = 12
    static let cardPadding:       CGFloat = 16
    static let cardSpacing:       CGFloat = 16
    static let cardShadowRadius:  CGFloat = 4
    static let cardShadowOpacity: Double  = 0.07
    static let cardBorderWidth:   CGFloat = 4

    // MARK: - Sport Color Helper
    static func sportColor(for type: String) -> Color {
        let t = type.lowercased()
        if t.contains("swim")                            { return swim }
        if t.contains("brick") || t.contains("race sim") { return brick }
        if t.contains("bike") || t.contains("cycl")     { return bike }
        if t.contains("run")                             { return run }
        if t.contains("strength") || t.contains("gym")  { return strength }
        return rest
    }

    /// HealthKit → sport color. Single bridge so HK-sourced UI (recorded
    /// activities, sport dots on workout rows) uses the same palette as
    /// planned-workout UI. Add new mappings here, never reach for hex.
    static func sportColor(for hk: HKWorkoutActivityType) -> Color {
        switch hk {
        case .swimming, .swimBikeRun: return swim
        case .cycling:                return bike
        case .running:                return run
        case .traditionalStrengthTraining,
             .functionalStrengthTraining,
             .crossTraining:          return strength
        default:                      return rest
        }
    }

    // MARK: - Sport Emoji Helper
    static func sportEmoji(for type: String) -> String {
        let t = type.lowercased()
        if t.contains("swim")                            { return "🏊" }
        if t.contains("brick") || t.contains("race sim") { return "🚴🏃" }
        if t.contains("bike") || t.contains("cycl")     { return "🚴" }
        if t.contains("run")                             { return "🏃" }
        if t.contains("strength") || t.contains("gym")  { return "💪" }
        return "😴"
    }

    // MARK: - Phase Color Helper
    static func phaseColor(for phase: String) -> Color {
        switch phase.lowercased() {
        case let p where p.contains("base"):  return phaseBase
        case let p where p.contains("build"): return phaseBuild
        case let p where p.contains("peak"):  return phasePeak
        case let p where p.contains("taper"): return phaseTaper
        default: return phaseBase
        }
    }
}
