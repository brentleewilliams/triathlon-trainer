import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
    let timestamp: Date = Date()
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading = false
    @Published var error: String?

    private let claudeService = ClaudeService.shared

    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        await MainActor.run {
            inputText = ""
            messages.append(ChatMessage(isUser: true, text: text))
            isLoading = true
            error = nil
        }

        do {
            let context = getContextForClaude()
            let history = getWorkoutHistoryForClaude()
            let response = try await claudeService.sendMessage(userMessage: text, trainingContext: context, workoutHistory: history)

            await MainActor.run {
                messages.append(ChatMessage(isUser: false, text: response))
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func getContextForClaude() -> String {
        """
        CURRENT WEEK PLAN:
        Week 5 (Apr 20): Build 1 Phase
        - Monday: Rest
        - Tuesday: Bike 1:15 Z4 intervals + Swim 2,200yd
        - Wednesday: Run 50min Z2 + Strength 40min
        - Thursday: Bike 1:00 Z2 + mini-brick 10min
        - Friday: Swim 2,400yd
        - Saturday: Bike 2:30 Z2 + Brick 25min (Gut: 50-60g carbs/hr)
        - Sunday: Long Run 70min Z2

        KEY FOCUS: Introducing Z4 bike intervals, extending weekend bricks, gut training starts.
        """
    }

    private func getWorkoutHistoryForClaude() -> String {
        """
        RECENT WORKOUTS (Last 4 Weeks):
        - Consistent Z2 base building
        - Swimming 2,000-2,400yd per session
        - Bike 1:00-2:30 per session
        - Running 40-60min per session
        - Completing brick sessions (bike + run back-to-back)

        No major injuries, shoulder tightness manageable with prehab.
        """
    }
}
