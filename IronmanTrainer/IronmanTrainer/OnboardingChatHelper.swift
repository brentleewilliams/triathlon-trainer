import Foundation

// MARK: - Onboarding Chat Helper

/// Builds onboarding-specific Claude context for fitness assessment and plan generation.
struct OnboardingChatHelper {

    // MARK: - Onboarding System Prompt

    /// Build system prompt for onboarding fitness assessment chat.
    /// Includes user's HK training history, race details, and goal so Claude can
    /// assess fitness and ask targeted follow-up questions.
    static func buildOnboardingSystemPrompt(
        profile: HealthKitOnboardingProfile?,
        userName: String,
        race: Race?,
        goal: GoalType?,
        skillLevels: (swim: SkillLevel, bike: SkillLevel, run: SkillLevel)? = nil
    ) -> String {
        var sections: [String] = []

        // Header
        sections.append("""
        You are an expert endurance coaching assistant conducting an onboarding fitness assessment.
        Your job is to learn about the athlete, assess their readiness, and help design a personalized training plan.
        Be friendly, concise, and ask ONE focused question at a time.
        """)

        // Athlete info
        let name = userName.isEmpty ? "the athlete" : userName
        sections.append("ATHLETE: \(name)")

        // Race details
        if let race = race {
            var raceInfo = "TARGET RACE: \(race.name) on \(Formatters.fullDate.string(from: race.date)) in \(race.location)"
            raceInfo += "\nRace Type: \(race.type.rawValue)"

            if !race.distances.isEmpty {
                let distParts = race.distances.map { "\($0.key): \($0.value) mi" }
                raceInfo += "\nDistances: \(distParts.joined(separator: ", "))"
            }

            raceInfo += "\nCourse: \(race.courseType)"

            if let elev = race.elevationGainM {
                raceInfo += "\nElevation Gain: \(Int(elev))m"
            }
            if let venueElev = race.elevationAtVenueM {
                raceInfo += "\nVenue Elevation: \(Int(venueElev))m"
            }
            if let weather = race.historicalWeather {
                raceInfo += "\nTypical Race Day Weather: \(weather)"
            }

            // Weeks until race
            let weeksOut = Calendar.current.dateComponents([.weekOfYear], from: Date(), to: race.date).weekOfYear ?? 0
            raceInfo += "\nWeeks Until Race: \(weeksOut)"

            sections.append(raceInfo)
        }

        // Goal
        if let goal = goal {
            switch goal {
            case .timeTarget(let interval):
                let hours = Int(interval) / 3600
                let minutes = (Int(interval) % 3600) / 60
                sections.append("GOAL: Finish in \(hours)h \(String(format: "%02d", minutes))m")
            case .justComplete:
                sections.append("GOAL: Complete the race (no specific time target)")
            }
        }

        // Per-sport skill levels
        if let skills = skillLevels {
            sections.append("""
            SELF-ASSESSED SKILL LEVELS:
            - Swim: \(skills.swim.rawValue) (\(skills.swim.description))
            - Bike: \(skills.bike.rawValue) (\(skills.bike.description))
            - Run: \(skills.run.rawValue) (\(skills.run.description))
            Use these to calibrate workout difficulty: beginners need more technique work and lower volume, advanced athletes can handle higher intensity and specificity.
            """)
        }

        // Prep races
        if let prepContext = PrepRacesManager.shared.contextString() {
            sections.append(prepContext + "\nUse these to structure training peaks and mini-tapers around prep races.")
        }

        // HealthKit training history
        if let profile = profile {
            var hkSection = "HEALTHKIT TRAINING HISTORY:\n"

            if let dob = profile.dateOfBirth {
                let age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
                hkSection += "Age: \(age)\n"
            }
            if let sex = profile.biologicalSex {
                hkSection += "Sex: \(sex)\n"
            }
            if let weight = profile.weightKg {
                hkSection += "Weight: \(String(format: "%.1f", weight)) kg\n"
            }
            if let rhr = profile.restingHR {
                hkSection += "Resting HR: \(rhr) bpm\n"
            }
            if let vo2 = profile.vo2Max {
                hkSection += "VO2 Max: \(String(format: "%.1f", vo2)) ml/kg/min\n"
            }

            // Weekly volume averages (last 3 months)
            if let vol = profile.recentWeeklyVolume {
                hkSection += "\nWEEKLY AVERAGES (last \(vol.periodWeeks) weeks):\n"
                hkSection += "- Swim: \(Int(vol.avgSwimYardsPerWeek)) yd/wk\n"
                hkSection += "- Bike: \(String(format: "%.1f", vol.avgBikeHoursPerWeek)) hrs/wk\n"
                hkSection += "- Run: \(String(format: "%.1f", vol.avgRunMilesPerWeek)) mi/wk\n"
                hkSection += "- Avg Workouts: \(String(format: "%.1f", vol.avgWorkoutsPerWeek))/wk\n"
            }

            // Monthly volume trends
            if !profile.monthlyTrends.isEmpty {
                hkSection += "\nMONTHLY TRENDS:\n"
                for trend in profile.monthlyTrends {
                    let totalSessions = trend.swimSessions + trend.bikeSessions + trend.runSessions
                    hkSection += "- \(trend.month): \(totalSessions) workouts, "
                    hkSection += "\(String(format: "%.1f", trend.totalDurationHours)) hrs total"
                    if trend.swimSessions > 0 { hkSection += ", \(trend.swimSessions) swim" }
                    if trend.bikeSessions > 0 { hkSection += ", \(trend.bikeSessions) bike" }
                    if trend.runSessions > 0 { hkSection += ", \(trend.runSessions) run" }
                    hkSection += "\n"
                }
            }

            // Recent individual workouts (last 2 weeks)
            if !profile.recentWorkoutDetails.isEmpty {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d"
                hkSection += "\nRECENT WORKOUTS (last 2 weeks):\n"
                for workout in profile.recentWorkoutDetails {
                    hkSection += "- \(dateFormatter.string(from: workout.date)): \(workout.type) \(Int(workout.durationMinutes))min"
                    if let dist = workout.distanceMiles {
                        hkSection += " \(String(format: "%.1f", dist))mi"
                    }
                    if let cal = workout.calories {
                        hkSection += " \(Int(cal))kcal"
                    }
                    hkSection += "\n"
                }
            }

            sections.append(hkSection)
        } else {
            sections.append("HEALTHKIT DATA: Not available - ask the athlete about their training background manually.")
        }

        // Assessment instructions
        sections.append("""
        ASSESSMENT GUIDELINES:
        1. Review the HealthKit data to understand current training volume and consistency
        2. Ask about training background, injury history, and experience level
        3. Ask about weekly schedule constraints (work, family, preferred workout times)
        4. Ask about access to facilities (pool, bike trainer, gym)
        5. Assess if the goal is realistic given current fitness and time to race
        6. If the goal seems too aggressive, gently suggest a more realistic target
        7. Discuss training plan structure: phases, key workouts, rest days
        8. Keep the conversation to 4-6 exchanges before offering to generate the plan

        FEASIBILITY ASSESSMENT:
        - Consider weeks until race vs current fitness level
        - Factor in injury risk from ramping too quickly (max 10% weekly volume increase)
        - Account for the athlete's training history consistency
        - For triathlons: ensure adequate preparation across all three disciplines

        When you've gathered enough information, say something like:
        "I have a great picture of where you are. I'm ready to build your personalized training plan whenever you are!"
        """)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Plan Conversion Prompt

    /// Build a prompt that instructs Claude to convert the discussed plan into structured JSON
    /// matching the TrainingWeek/DayWorkout schema used by the app.
    static func buildPlanConversionPrompt(
        chatHistory: [ChatMessage],
        race: Race,
        profile: UserProfile,
        skillLevels: (swim: SkillLevel, bike: SkillLevel, run: SkillLevel)? = nil
    ) -> String {
        // Summarize chat history
        let chatSummary = chatHistory.map { msg in
            let role = msg.isUser ? "Athlete" : "Coach"
            return "\(role): \(msg.text)"
        }.joined(separator: "\n")

        let weeksUntilRace = Calendar.current.dateComponents([.weekOfYear], from: Date(), to: race.date).weekOfYear ?? 0
        let startDate = Calendar.current.startOfDay(for: Date())

        return """
        Based on the coaching conversation below, generate a structured training plan as JSON.

        CONVERSATION:
        \(chatSummary)

        RACE: \(race.name) on \(Formatters.fullDate.string(from: race.date))
        LOCATION: \(race.location)
        TYPE: \(race.type.rawValue)
        DISTANCES: \(race.distances.map { "\($0.key): \($0.value) mi" }.joined(separator: ", "))
        COURSE: \(race.courseType)
        WEEKS AVAILABLE: \(weeksUntilRace)
        PLAN START DATE: \(Formatters.fullDate.string(from: startDate))

        ATHLETE PROFILE:
        - Name: \(profile.name)
        \(profile.biologicalSex.map { "- Sex: \($0)" } ?? "")
        \(profile.weightKg.map { "- Weight: \(String(format: "%.1f", $0)) kg" } ?? "")
        \(profile.restingHR.map { "- Resting HR: \($0) bpm" } ?? "")
        \(profile.vo2Max.map { "- VO2 Max: \(String(format: "%.1f", $0))" } ?? "")
        \(skillLevels.map { "- Swim Skill: \($0.swim.rawValue)\n- Bike Skill: \($0.bike.rawValue)\n- Run Skill: \($0.run.rawValue)" } ?? "")

        GOAL: \({
            switch race.userGoal {
            case .timeTarget(let t):
                let h = Int(t) / 3600
                let m = (Int(t) % 3600) / 60
                return "Finish in \(h)h \(String(format: "%02d", m))m"
            case .justComplete:
                return "Complete the race"
            }
        }())

        Generate the plan as a JSON array of weeks. Each week must match this schema:
        ```json
        [
            {
                "weekNumber": 1,
                "phase": "Base|Build|Peak|Taper|Race",
                "startDate": "YYYY-MM-DD",
                "endDate": "YYYY-MM-DD",
                "workouts": [
                    {
                        "day": "Mon|Tue|Wed|Thu|Fri|Sat|Sun",
                        "type": "Swim|Bike|Run|Brick|Rest|Strength",
                        "duration": "45 min|1:30|2,400 yd|etc",
                        "zone": "Z1|Z2|Z2-Z3|Z3|Z4|Z5|Mixed|Recovery|N/A",
                        "status": null,
                        "nutritionTarget": null or "60g carbs/hr"
                    }
                ]
            }
        ]
        ```

        \(PrepRacesManager.shared.contextString().map { "\nPREP RACES:\n\($0)\n" } ?? "")

        RULES:
        - Each week has 7 days (Mon-Sun)
        - Include at least 1 rest day per week
        - Prep race day AND the day before must be Rest days (no training)
        - Nutrition targets for workouts >= 60 min: Bike 60-75min -> "60g carbs/hr", Bike >75min -> "60-80g carbs/hr", Run >=60min -> "30-45g carbs/hr"
        - Phase names: "Base" (first ~30%), "Build" (next ~35%), "Peak" (next ~20%), "Taper" (last ~15%)
        - Max 10% weekly volume increase from week to week
        - Start dates should be Mondays, ending on Sundays

        Return ONLY the JSON array, no other text.
        """
    }
}
