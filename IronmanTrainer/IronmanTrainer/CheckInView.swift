import SwiftUI

// MARK: - Morning Check-In View (v1)
//
// Focused SwiftUI view for the Morning Check-In flow (PRD §3.6.2).
//
// v1 behavior:
//  - Displays today's workout as a persistent header card.
//  - Shows the cached opening message instantly when available, otherwise
//    kicks off live regeneration (tier 2). Static fallback (tier 3) is used
//    when the LLM call fails.
//  - Caps interaction at a max of 3 message exchanges.
//  - Accept Adjustment / Keep as Planned buttons reuse the existing
//    PlanChangeProposal pipeline when Claude has proposed a change.
struct CheckInView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var checkIn: CheckInManager
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.dismiss) private var dismiss

    /// Maximum number of message exchanges visible in the focused view.
    /// (Opening question + one follow-up + recommendation.)
    private let maxExchanges = 3

    @State private var replyText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal)
                    .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if checkIn.isGeneratingOpeningMessage && checkInMessages.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Coach is thinking…")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                            .padding()
                        }

                        ForEach(visibleMessages) { msg in
                            ChatBubble(message: msg)
                        }

                        if let proposal = viewModel.pendingProposal {
                            planActionBar(for: proposal)
                        }
                    }
                    .padding()
                }

                replyBar
            }
            .navigationTitle("Morning Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Keep as Planned") {
                        checkIn.completeCheckIn(accepted: false)
                        dismiss()
                    }
                }
            }
            .task {
                // `.task` fires once per view identity, so no manual guard is needed.
                await loadOpeningMessage()
            }
        }
    }

    // MARK: - Header card

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's workout")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(todaysPlanSummary)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private var todaysPlanSummary: String {
        guard let week = trainingPlan.getWeek(trainingPlan.currentWeekNumber) else {
            return "No plan loaded"
        }
        let today = DayNames.from(Date())
        let todayWorkouts = week.workouts.filter { $0.day == today && $0.type.lowercased() != "rest" }
        if todayWorkouts.isEmpty {
            return "Rest day"
        }
        return todayWorkouts
            .map { "\($0.type) \($0.duration) \($0.zone)" }
            .joined(separator: " + ")
    }

    // MARK: - Messages

    /// Only check-in-tagged messages.
    private var checkInMessages: [ChatMessage] {
        viewModel.messages.filter { $0.kind == .checkIn }
    }

    /// The last `maxExchanges` check-in messages, so the view stays focused.
    private var visibleMessages: [ChatMessage] {
        let msgs = checkInMessages
        guard msgs.count > maxExchanges else { return msgs }
        return Array(msgs.suffix(maxExchanges))
    }

    private var canReply: Bool {
        // Two-exchange max (§3.4): user bubbles capped at 2.
        let userCount = checkInMessages.filter { $0.isUser }.count
        return userCount < 2 && !viewModel.isLoading
    }

    // MARK: - Reply bar

    private var replyBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                TextField(canReply ? "Reply to your coach…" : "Max replies reached", text: $replyText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!canReply)
                Button {
                    sendReply()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canReply && !replyText.isEmpty ? .blue : .gray)
                }
                .disabled(!canReply || replyText.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: - Plan action bar

    private func planActionBar(for proposal: PlanChangeProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(proposal.summary)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                Button {
                    viewModel.executePlanChanges(proposal)
                    checkIn.completeCheckIn(accepted: true)
                    dismiss()
                } label: {
                    Text("Accept Adjustment")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                Button {
                    viewModel.dismissPlanChanges()
                    checkIn.completeCheckIn(accepted: false)
                    dismiss()
                } label: {
                    Text("Keep as Planned")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray4))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    // MARK: - Actions

    private func loadOpeningMessage() async {
        // 1. If a cached message is still fresh, show it instantly.
        if let cached = checkIn.loadCachedOpeningMessage() {
            appendAssistant(cached.openingMessage)
            return
        }

        // 2. Live-regenerate (tier 2).
        let generated = await checkIn.generateOpeningMessage(
            trainingPlan: trainingPlan,
            healthKit: healthKit
        )
        appendAssistant(generated.openingMessage)
    }

    private func appendAssistant(_ text: String) {
        let msg = ChatMessage(isUser: false, text: text, kind: .checkIn)
        viewModel.messages.append(msg)
        viewModel.saveChatHistory()
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyText = ""

        // Append a .checkIn-tagged user message immediately so the view updates.
        let userMsg = ChatMessage(isUser: true, text: text, kind: .checkIn)
        viewModel.messages.append(userMsg)
        viewModel.saveChatHistory()

        Task {
            // Reuse the coaching pipeline; mark the subsequent assistant
            // message as .checkIn so it shows in the filter chip.
            let countBefore = viewModel.messages.count
            await viewModel.sendMessage("[check_in] " + text)
            // Retag any assistant messages appended by sendMessage.
            if viewModel.messages.count > countBefore {
                for i in countBefore..<viewModel.messages.count {
                    let m = viewModel.messages[i]
                    if !m.isUser && m.kind == .general {
                        viewModel.messages[i] = ChatMessage(
                            id: m.id,
                            isUser: m.isUser,
                            text: m.text,
                            timestamp: m.timestamp,
                            imageData: m.imageData,
                            kind: .checkIn
                        )
                    }
                }
                viewModel.saveChatHistory()
            }
        }
    }
}
