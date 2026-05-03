import SwiftUI
import PhotosUI

/// Filter options for the Chat tab. `all` shows every message; `checkIns`
/// shows only `.checkIn`-tagged messages (Morning Check-In v1).
enum ChatFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case checkIns = "Check-ins"
    var id: String { rawValue }
}

// MARK: - Chat View
struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var filter: ChatFilter = .all

    /// Applies the selected `ChatFilter` to the message list.
    /// Pure so it can be unit-tested via a static helper below.
    private var filteredMessages: [ChatMessage] {
        Self.applyFilter(filter, to: viewModel.messages)
    }

    static func applyFilter(_ filter: ChatFilter, to messages: [ChatMessage]) -> [ChatMessage] {
        switch filter {
        case .all: return messages
        case .checkIns: return messages.filter { $0.kind == .checkIn }
        }
    }

    /// Scrolls the chat transcript to the bottom anchor with an animation.
    /// Used by both the initial appearance and every state-change trigger.
    private static func scrollChatToBottom(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo("chat-bottom", anchor: .bottom) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(ChatFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                if filter == .checkIns && !CheckInManager.shared.enabled {
                    CheckInsOffEmptyState()
                } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if filteredMessages.isEmpty && !viewModel.isLoading {
                            CoachWelcomeView()
                        }

                        ForEach(filteredMessages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }

                        if let proposal = viewModel.pendingProposal,
                           let plan = viewModel.trainingPlan {
                            PlanDiffCard(
                                viewModel: viewModel,
                                enriched: PlanDiffEngine.enrich(proposal, plan: plan)
                            )
                            .id("proposal-card")
                        }

                        if viewModel.isLoading {
                            TypingBubblesView()
                                .padding(.leading, 16)
                                .padding(.vertical, 8)
                        }

                        if let error = viewModel.error {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                        }
                        Color.clear.frame(height: 1).id("chat-bottom")
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.immediately)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        Self.scrollChatToBottom(proxy)
                    }
                }
                // Keep three separate onChange calls (not one combined) so every
                // state transition fires reliably, even when the underlying value
                // types hash equal after mutation.
                .onChange(of: viewModel.messages.count) { Self.scrollChatToBottom(proxy) }
                .onChange(of: viewModel.isLoading) { Self.scrollChatToBottom(proxy) }
                .onChange(of: viewModel.negotiationState) { Self.scrollChatToBottom(proxy) }
                .safeAreaInset(edge: .bottom) {
                    ChatInputBar(viewModel: viewModel)
                }
            }
            } // else
        }
        // Navigation modifiers go on NavigationStack, not on the if/else inside
        // its VStack (ViewBuilder can't chain navigation modifiers to a
        // _ConditionalContent value, which is what the `if/else` produces).
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

// MARK: - Check-ins off empty state

struct CheckInsOffEmptyState: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("Morning Check-Ins are off")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Turn on daily check-ins to get a personalised morning briefing based on your sleep, HRV, and today's workout.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                CheckInManager.shared.enabled = true
                CheckInManager.shared.scheduleLocalFallbackNotification()
            } label: {
                Text("Turn on Check-Ins")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }
}

struct ChatInputBar: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isFocused: Bool
    @State private var text: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingImageData: Data?

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || pendingImageData != nil) && !viewModel.isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Image preview
            if let imageData = pendingImageData, let uiImage = UIImage(data: imageData) {
                HStack {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            pendingImageData = nil
                            selectedPhoto = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .offset(x: 6, y: -6)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                .disabled(viewModel.isLoading)
                .padding(.leading, 12)
                .padding(.bottom, 10)

                TextField(viewModel.isNegotiating ? "What would you like changed?" : "Message your coach...", text: $text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.sentences)
                    .keyboardType(.default)
                    .submitLabel(.send)
                    .padding(.vertical, 12)
                    .padding(.trailing, 16)
                    .focused($isFocused)
                    .disabled(viewModel.isLoading)
                    .onSubmit { if canSend { send() } }
                    .onAppear { consumePendingSeed() }
                    .onChange(of: viewModel.pendingInputText) { _, _ in consumePendingSeed() }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .onChange(of: selectedPhoto) {
            Task {
                guard let item = selectedPhoto,
                      let data = try? await item.loadTransferable(type: Data.self) else { return }
                // Compress to JPEG for API efficiency
                if let uiImage = UIImage(data: data),
                   let jpeg = uiImage.jpegData(compressionQuality: 0.7) {
                    pendingImageData = jpeg
                } else {
                    pendingImageData = data
                }
            }
        }
    }

    private func send() {
        let message = text
        let image = pendingImageData
        text = ""
        pendingImageData = nil
        selectedPhoto = nil
        isFocused = false
        Task {
            await viewModel.sendMessage(message, imageData: image)
        }
    }

    /// Drains `pendingInputText` from the ViewModel into the local TextField.
    /// Called on appear (handles the case where the seed was set before the
    /// input bar mounted, e.g. tapping a coach insight on the home screen)
    /// and on every change to pendingInputText.
    private func consumePendingSeed() {
        if let seed = viewModel.pendingInputText, !seed.isEmpty {
            text = seed
            viewModel.pendingInputText = nil
            isFocused = true
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
        case .swap: return "arrow.left.arrow.right.circle.fill"
        case .replace: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    private var iconColor: Color {
        switch change.action {
        case .add: return .green
        case .drop: return .red
        case .swap: return .orange
        case .replace: return .blue
        }
    }

    private var label: String {
        switch change.action {
        case .add:
            return "Add \(change.type ?? "workout") on \(change.day ?? "?"), Week \(change.week)"
        case .drop:
            return "Drop all workouts on \(change.day ?? "?"), Week \(change.week)"
        case .swap:
            return "Swap \(change.fromDay ?? "?") \u{2194} \(change.toDay ?? "?"), Week \(change.week)"
        case .replace:
            return "Replace \(change.fromType ?? "workout") \u{2192} \(change.type ?? "?") on \(change.day ?? "?"), Week \(change.week)"
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
                        .background(Color(.systemGray3))
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

// MARK: - Coach Welcome View

struct CoachWelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue.opacity(0.6))

            Text("Your AI Coach")
                .font(.title3.weight(.semibold))

            Text("Ask about today's workout, get pacing advice, request schedule changes, or send a photo for form feedback.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 10) {
                SuggestionChip(text: "How should I pace my long run?")
                SuggestionChip(text: "Can I swap today's swim to tomorrow?")
                SuggestionChip(text: "What should I eat before my brick workout?")
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct SuggestionChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.caption)
                .foregroundStyle(.blue)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if !message.text.isEmpty && message.text != "Sent a photo" {
                        Text(message.text)
                            .font(.body)
                    }
                }
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

private struct TypingBubblesView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.gray.opacity(0.7))
                    .frame(width: 10, height: 10)
                    .scaleEffect(animating ? 1.2 : 0.8)
                    .offset(y: animating ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
