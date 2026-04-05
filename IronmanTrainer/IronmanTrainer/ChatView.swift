import SwiftUI

// MARK: - Chat View
struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject var trainingPlan: TrainingPlanManager
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }

                        if let proposal = viewModel.pendingProposal {
                            PlanChangeCard(viewModel: viewModel, proposal: proposal)
                                .id("proposal-card")
                        }

                        if viewModel.isLoading {
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { i in
                                    Circle()
                                        .fill(Color.gray.opacity(0.6))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.leading, 16)
                            .padding(.vertical, 8)
                        }

                        if let error = viewModel.error {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: viewModel.messages.count) {
                    withAnimation {
                        proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ChatInputBar(viewModel: viewModel)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            viewModel.clearChatHistory()
                        } label: {
                            Label("Clear History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

struct ChatInputBar: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 0) {
                TextField("Message your coach...", text: $text)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .focused($isFocused)
                    .disabled(viewModel.isLoading)
                    .onSubmit { if canSend { send() } }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func send() {
        let message = text
        text = ""
        isFocused = false
        Task {
            await viewModel.sendMessage(message)
        }
    }
}

// MARK: - Plan Change Confirmation UI

struct PlanChangeRow: View {
    let change: PlanChange

    private var icon: String {
        switch change.action {
        case .add: return "plus.circle.fill"
        case .drop: return "minus.circle.fill"
        case .modify: return "pencil.circle.fill"
        }
    }

    private var iconColor: Color {
        switch change.action {
        case .add: return .green
        case .drop: return .red
        case .modify: return .orange
        }
    }

    private var label: String {
        let type = change.type ?? "workout"
        switch change.action {
        case .add:
            return "Add \(type) on \(change.day), Week \(change.week)"
        case .drop:
            return "Drop \(type) on \(change.day), Week \(change.week)"
        case .modify:
            let field = change.field ?? ""
            let from = change.from ?? ""
            let to = change.to ?? ""
            return "Modify \(type) on \(change.day), Week \(change.week): \(field) \(from) → \(to)"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.body)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

struct PlanChangeCard: View {
    @ObservedObject var viewModel: ChatViewModel
    let proposal: PlanChangeProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(proposal.summary)
                .font(.body)
                .bold()

            ForEach(proposal.changes) { change in
                PlanChangeRow(change: change)
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.executePlanChanges(proposal)
                } label: {
                    Text("Apply Changes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Button {
                    viewModel.dismissPlanChanges()
                } label: {
                    Text("Dismiss")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()

                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            } else {
                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(16)

                Spacer()
            }
        }
    }
}
