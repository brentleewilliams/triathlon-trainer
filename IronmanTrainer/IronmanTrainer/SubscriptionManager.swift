import Foundation
import SwiftUI

// MARK: - Subscription Tier

enum SubscriptionTier: String, Codable, CaseIterable {
    case free
    case pro
    case ultra

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .ultra: return "Ultra"
        }
    }

    var monthlyPrice: String {
        switch self {
        case .free: return "Free"
        case .pro: return "$9.99/mo"
        case .ultra: return "$19.99/mo"
        }
    }

    var color: Color {
        switch self {
        case .free: return .gray
        case .pro: return .blue
        case .ultra: return .purple
        }
    }

    var iconName: String {
        switch self {
        case .free: return "figure.run"
        case .pro: return "flame.fill"
        case .ultra: return "bolt.shield.fill"
        }
    }

    var features: [PlanFeature] {
        switch self {
        case .free:
            return [
                .trainingPlanDisplay,
                .weekNavigation,
                .raceCountdown,
                .basicCompliance
            ]
        case .pro:
            return PlanFeature.allCases.filter { $0 != .trainingLoadTracking && $0 != .raceDayExecution && $0 != .advancedAnalytics && $0 != .multiRaceSupport }
        case .ultra:
            return PlanFeature.allCases
        }
    }

    func hasFeature(_ feature: PlanFeature) -> Bool {
        features.contains(feature)
    }
}

// MARK: - Plan Features

enum PlanFeature: String, Codable, CaseIterable {
    case trainingPlanDisplay       // View weekly training plan
    case weekNavigation            // Navigate between weeks
    case raceCountdown             // Race countdown banner
    case basicCompliance           // Green/yellow/red workout tracking
    case aiCoaching                // Claude AI coaching chat
    case nutritionTargets          // Per-workout nutrition guidance
    case healthKitSync             // HealthKit workout sync
    case weeklyVolumeDeviation     // Weekly volume vs plan comparison
    case hrZoneAnalytics           // HR zone distribution analytics
    case planAdaptation            // Swap days via chat
    case trainingLoadTracking      // TSS/CTL/ATL/TSB tracking
    case raceDayExecution          // Race-day pacing + nutrition plan
    case advancedAnalytics         // Advanced training analytics
    case multiRaceSupport          // Support multiple race distances

    var displayName: String {
        switch self {
        case .trainingPlanDisplay: return "Training Plan"
        case .weekNavigation: return "Week Navigation"
        case .raceCountdown: return "Race Countdown"
        case .basicCompliance: return "Workout Tracking"
        case .aiCoaching: return "AI Coach"
        case .nutritionTargets: return "Nutrition Targets"
        case .healthKitSync: return "HealthKit Sync"
        case .weeklyVolumeDeviation: return "Weekly Volume Alerts"
        case .hrZoneAnalytics: return "HR Zone Analytics"
        case .planAdaptation: return "Plan Adaptation"
        case .trainingLoadTracking: return "Training Load"
        case .raceDayExecution: return "Race Day Plan"
        case .advancedAnalytics: return "Advanced Analytics"
        case .multiRaceSupport: return "Multi-Race Support"
        }
    }

    var description: String {
        switch self {
        case .trainingPlanDisplay: return "View your weekly training plan with workout details"
        case .weekNavigation: return "Navigate between training weeks"
        case .raceCountdown: return "Countdown timer to your race day"
        case .basicCompliance: return "Track workout completion with color-coded compliance"
        case .aiCoaching: return "Chat with Claude AI for personalized coaching advice"
        case .nutritionTargets: return "Progressive carb/hr targets on long rides and bricks"
        case .healthKitSync: return "Automatic workout sync from Apple Health"
        case .weeklyVolumeDeviation: return "Alerts when training volume deviates from plan"
        case .hrZoneAnalytics: return "Heart rate zone distribution per workout and week"
        case .planAdaptation: return "Swap training days via AI chat"
        case .trainingLoadTracking: return "Training stress, fatigue, and form tracking (TSS/CTL/ATL/TSB)"
        case .raceDayExecution: return "AI-generated race-day pacing and nutrition plan"
        case .advancedAnalytics: return "Training load trends, fitness curves, and performance insights"
        case .multiRaceSupport: return "Plan for Sprint, Olympic, 70.3, Full Ironman, or Ultra distances"
        }
    }

    var tierRequired: SubscriptionTier {
        switch self {
        case .trainingPlanDisplay, .weekNavigation, .raceCountdown, .basicCompliance:
            return .free
        case .aiCoaching, .nutritionTargets, .healthKitSync, .weeklyVolumeDeviation,
             .hrZoneAnalytics, .planAdaptation:
            return .pro
        case .trainingLoadTracking, .raceDayExecution, .advancedAnalytics, .multiRaceSupport:
            return .ultra
        }
    }
}

// MARK: - Subscription Manager

class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published var currentTier: SubscriptionTier {
        didSet {
            UserDefaults.standard.set(currentTier.rawValue, forKey: "subscription_tier")
        }
    }

    @Published var trialExpiresAt: Date?
    @Published var subscriptionExpiresAt: Date?

    init() {
        let savedTier = UserDefaults.standard.string(forKey: "subscription_tier") ?? "ultra"
        self.currentTier = SubscriptionTier(rawValue: savedTier) ?? .ultra

        if let trialInterval = UserDefaults.standard.object(forKey: "trial_expires_at") as? TimeInterval {
            self.trialExpiresAt = Date(timeIntervalSince1970: trialInterval)
        }
    }

    var isTrialActive: Bool {
        guard let expires = trialExpiresAt else { return false }
        return Date() < expires
    }

    var effectiveTier: SubscriptionTier {
        if isTrialActive && currentTier == .free {
            return .ultra
        }
        return currentTier
    }

    func hasAccess(to feature: PlanFeature) -> Bool {
        effectiveTier.hasFeature(feature)
    }

    func startTrial(days: Int = 14) {
        let calendar = Calendar.current
        trialExpiresAt = calendar.date(byAdding: .day, value: days, to: Date())
        if let expires = trialExpiresAt {
            UserDefaults.standard.set(expires.timeIntervalSince1970, forKey: "trial_expires_at")
        }
    }

    func upgradeTo(_ tier: SubscriptionTier) {
        currentTier = tier
    }

    var trialDaysRemaining: Int? {
        guard let expires = trialExpiresAt, isTrialActive else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: Date(), to: expires).day
    }
}
