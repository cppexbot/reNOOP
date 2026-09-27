import SwiftUI
import MarkdownUI
import StrandDesign

/// Coach, the one feature in NOOP that talks to the network, drawn as a Messages conversation (iOS 26):
/// grey reply bubbles, blue question bubbles, a glass field at the bottom with the mic inside it, and
/// suggestion capsules above the field. The provider, model and key live in the settings sheet.
///
/// It is strictly opt-in and bring-your-own-key: the user pastes their own OpenAI, Anthropic or Gemini
/// key (stored in the Keychain by `AICoachEngine`), or points it at their own server, and only a compact
/// text summary of their metrics plus their question ever leaves the device. Nothing is sent until a key
/// is saved and a question asked.
struct CoachView: View {
    @EnvironmentObject var coach: AICoachEngine
    /// K8: used by "Save to Journal" — saves the coach advice as a journal entry with the text in the
    /// notes field, so it appears alongside other journal entries.
    @EnvironmentObject var repo: Repository

    /// Draft text in the composer. K15: persisted to UserDefaults so it survives an app relaunch, keyed
    /// identically to the Android twin.
    private static let draftKey = "coach.composerDraft"
    @State private var draft: String = UserDefaults.standard.string(forKey: "coach.composerDraft") ?? ""
    @FocusState private var composerFocused: Bool

    /// #2243: provider, key, model, data access, instructions and the morning brief, in one sheet. A
    /// sheet behaves the same in all three places CoachView appears (macOS route, Browse push, pillar
    /// sheet), which a push would not.
    @State private var showSettings = false

    // K4: on-device voice input for the composer (iOS only).
    #if os(iOS)
    @StateObject private var voiceInput = CoachVoiceInput()
    #endif

    var body: some View {
        Group {
            if coach.isConfigured {
                conversation
            } else {
                EmptyStateView(title: Text("Coach"), systemImage: "sparkles",
                               description: Text("Connect your own AI provider.")) {
                    Button("Set Up") { showSettings = true }
                        .buttonStyle(.borderedProminent)
                        .tint(StrandPalette.messageOutgoing)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StrandPalette.messagePage.ignoresSafeArea())
        .navigationTitle(Text("Coach"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // A conversation owns the whole screen, as in Messages: the field sits where the tab bar was.
        .toolbar(.hidden, for: .tabBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(Text("Coach settings"))
            }
        }
        // `repo` rides along because a sheet's view tree does not inherit the presenter's environment.
        .sheet(isPresented: $showSettings) {
            CoachSettingsView()
                .environmentObject(coach)
                .environmentObject(repo)
        }
        // K2 + K5 ordering matters and every step gates on an EMPTY transcript, so this is ONE `.task`
        // running sequentially: restore whatever the prior launch persisted, THEN surface a brief the
        // scheduled notification already generated (if any), THEN the interactive first-open brief — so
        // `startBriefIfNeeded` only ever runs over the network when both of the above left the transcript
        // genuinely empty.
        .task {
            await coach.loadPersistedMessagesIfNeeded()
            // Gated on the transcript BEFORE consuming: `consumeStoredBrief()` clears the unconsumed flag,
            // so consuming on a day with a conversation open would throw the brief away (#2087).
            if coach.messages.isEmpty, let stored = CoachBriefScheduler.consumeStoredBrief() {
                coach.surfaceScheduledBrief(stored)
            }
            CoachBriefScheduler.activateIfEnabled { await coach.generateBrief() }
            await coach.startBriefIfNeeded()
        }
        // #1862: a question handed over by a launcher. Cleared BEFORE sending so a rebuild mid-flight
        // cannot send it twice; an unconfigured handoff degrades to showing setup.
        .task(id: coach.pendingPrompt) {
            guard let prompt = coach.pendingPrompt, !prompt.isEmpty else { return }
            coach.pendingPrompt = nil
            guard coach.isConfigured else { return }
            await coach.send(prompt)
        }
        .onChangeCompat(of: draft) { newValue in
            UserDefaults.standard.set(newValue, forKey: Self.draftKey)
        }
        // K14: haptic feedback when a reply arrives (sending goes true → false).
        .onChangeCompat(of: coach.sending) { isSending in
            if !isSending && !coach.messages.isEmpty { triggerReplyHaptic() }
        }
        // A consent toggle after the initial load re-checks the brief; `startBriefIfNeeded` is a no-op
        // once a conversation exists.
        .onChangeCompat(of: coach.dataConsent) { _ in
            Task { await coach.startBriefIfNeeded() }
        }
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    privacyLine
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    ForEach(Array(coach.messages.enumerated()), id: \.element.id) { index, message in
                        bubble(message, tail: isLastOfGroup(index))
                            .padding(.bottom, isLastOfGroup(index) ? 10 : 2)
                            .id(message.id)
                    }
                    if coach.sending {
                        typingBubble.id("typing")
                    }
                    if let error = coach.errorText, !error.isEmpty {
                        errorLine(error).id("error")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                #if os(macOS)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                #endif
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if coach.messages.isEmpty && !coach.sending {
                    EmptyStateView(title: Text("Coach"), systemImage: "sparkles",
                                   description: Text("Ask about your charge, effort, sleep and workouts."))
                        .allowsHitTesting(false)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .onAppear { scrollToEnd(proxy, animated: false) }
            .onChangeCompat(of: coach.messages.count) { _ in scrollToEnd(proxy) }
            .onChangeCompat(of: coach.sending) { _ in scrollToEnd(proxy) }
        }
    }

    /// The one privacy line, at the head of the conversation where Messages names the service.
    private var privacyLine: some View {
        Label {
            Text(coach.provider == .custom
                 ? "Sent only to your server, only when you ask."
                 : "A summary of your data goes to \(coach.provider.displayName) only when you ask.")
        } icon: {
            Image(systemName: "lock.fill")
        }
        .font(StrandFont.pro(12))
        .foregroundStyle(StrandPalette.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// Messages draws the tail only on the last bubble of a run from one side.
    private func isLastOfGroup(_ index: Int) -> Bool {
        let messages = coach.messages
        guard index + 1 < messages.count else { return !coach.sending || messages[index].role == .user }
        return messages[index + 1].role != messages[index].role
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage, tail: Bool) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 56)
                Text(message.text)
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.messageOutgoingText)
                    .textSelection(.enabled)
                    .modifier(MessageBubble(outgoing: true, tail: tail))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("You said: \(message.text)"))
        case .assistant:
            // Replies arrive as Markdown (bold, lists, headings, tables); questions stay verbatim `Text`
            // so a typed `*` or `#` never turns into formatting.
            HStack {
                Markdown(message.text)
                    .markdownTheme(.strand)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(MessageBubble(outgoing: false, tail: tail))
                    // K8: Copy / Share / Save.
                    .contextMenu {
                        Button {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                            #else
                            UIPasteboard.general.string = message.text
                            #endif
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        ShareLink(item: message.text) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button { saveAdvice(message.text) } label: {
                            Label("Save to Journal", systemImage: "square.and.pencil")
                        }
                    }
                Spacer(minLength: 56)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Coach said: \(message.text)"))
        }
    }

    /// Messages' typing bubble: three grey dots breathing in turn.
    private var typingBubble: some View {
        HStack {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(StrandPalette.messageTypingDot)
                            .frame(width: 9, height: 9)
                            .opacity(0.35 + 0.65 * max(0, sin((t * 4) - Double(i) * 0.9)))
                    }
                }
                .frame(height: 22)
            }
            .modifier(MessageBubble(outgoing: false, tail: true))
            Spacer(minLength: 56)
        }
        .padding(.bottom, 10)
        .accessibilityLabel(Text("Coach is thinking"))
    }

    /// A failed send, as Messages marks one: a red line under the conversation. A rejected key carries
    /// the way to fix it, which opens the key field in settings (the transcript is kept).
    private func errorLine(_ message: String) -> some View {
        VStack(spacing: 4) {
            Label {
                Text(message)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
            }
            .font(StrandFont.pro(13))
            .foregroundStyle(StrandPalette.settingsRed)
            .multilineTextAlignment(.center)
            if coach.keyRejected {
                Button("Update Key") { showSettings = true }
                    .font(StrandFont.pro(13, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(StrandPalette.messageOutgoing)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Composer

    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Suggestion capsules over the glass field. K7: follow-ups after a reply, contextual ones otherwise.
    private var composer: some View {
        VStack(spacing: 8) {
            if !hasDraft && !coach.sending {
                suggestionRow
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask Coach", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .onSubmit { send(draft) }
                    .padding(.vertical, 10)
                    .accessibilityLabel(Text("Question"))
                trailingControl
                    .padding(.bottom, 5)
            }
            .padding(.leading, 16)
            .padding(.trailing, 5)
            .messageGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
        .padding(.top, 4)
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(showFollowUps ? AICoachEngine.followUpSuggestions : coach.suggestions, id: \.self) { prompt in
                    Button { send(prompt) } label: {
                        Text(prompt)
                            .font(StrandFont.pro(15))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .messageGlass(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Suggested prompt: \(prompt)"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
    }

    /// K7: follow-ups replace the contextual suggestions once the coach has answered.
    private var showFollowUps: Bool { coach.messages.last?.role == .assistant }

    /// The send arrow once there is something to send; the mic (iOS) while the field is empty.
    @ViewBuilder
    private var trailingControl: some View {
        if hasDraft || coach.sending {
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(StrandPalette.messageOutgoingText)
                    .frame(width: 30, height: 30)
                    .background(StrandPalette.messageOutgoing, in: Circle())
                    .opacity(coach.sending ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(coach.sending || !hasDraft)
            .accessibilityLabel(Text("Send"))
        } else {
            #if os(iOS)
            micButton
            #endif
        }
    }

    // MARK: - K4: Voice input (iOS only)

    #if os(iOS)
    private var micButton: some View {
        Button { toggleVoice() } label: {
            Image(systemName: voiceInput.isRecording ? "stop.circle.fill" : "mic")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(voiceInput.isRecording ? StrandPalette.settingsRed : StrandPalette.textSecondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(!micButtonEnabled)
        .accessibilityLabel(Text(voiceInput.isRecording ? "Stop voice input" : "Voice input"))
        .accessibilityHint(Text(voiceInput.statusMessage ?? String(localized: "Transcribes your question on-device")))
        .task {
            // Pre-check on appear so the button reflects the right state without a tap.
            if voiceInput.authorization == .notDetermined {
                voiceInput.requestAuthorization { _ in }
            }
        }
    }

    /// Tappable while not sending, and only if voice is usable or permission hasn't been asked yet.
    private var micButtonEnabled: Bool {
        !coach.sending && (voiceInput.canUseVoice || voiceInput.authorization == .notDetermined)
    }

    private func toggleVoice() {
        if voiceInput.isRecording {
            voiceInput.stopTranscribing { finalText in
                let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // Append (not replace) so the user can speak into existing text.
                    draft = draft.isEmpty ? trimmed : "\(draft) \(trimmed)"
                }
            }
        } else if voiceInput.authorization == .notDetermined {
            voiceInput.requestAuthorization { state in
                if state == .authorized {
                    voiceInput.startTranscribing { partial in draft = partial }
                }
            }
        } else {
            voiceInput.startTranscribing { partial in draft = partial }
        }
    }
    #endif

    // MARK: - Actions

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !coach.sending else { return }
        draft = ""
        composerFocused = false
        Task { await coach.send(trimmed) }
    }

    /// K14: a light impact when the reply arrives (iOS); no simple equivalent on macOS.
    private func triggerReplyHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// K8: save a reply to the journal as a note, under a fixed question ("Coach advice").
    private func saveAdvice(_ text: String) {
        let day = Repository.localDayKey(Date())
        Task {
            await repo.saveJournalAnswer(day: day, question: "Coach advice", answeredYes: true, notes: text)
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target: AnyHashable? = coach.errorText?.isEmpty == false ? AnyHashable("error")
            : coach.sending ? AnyHashable("typing")
            : coach.messages.last.map { AnyHashable($0.id) }
        guard let target else { return }
        if animated {
            withAnimation(StrandMotion.fade) { proxy.scrollTo(target, anchor: .bottom) }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}

// MARK: - Bubble

/// A Messages bubble: blue on the right for the sender, grey on the left for replies, the tail on the
/// last bubble of a run. The tail's width is reserved on every bubble so a run lines up.
private struct MessageBubble: ViewModifier {
    let outgoing: Bool
    let tail: Bool

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 8)
            .padding(.leading, outgoing ? 13 : 13 + MessageBubbleShape.tailWidth)
            .padding(.trailing, outgoing ? 13 + MessageBubbleShape.tailWidth : 13)
            .frame(minHeight: 36)
            .background(outgoing ? StrandPalette.messageOutgoing : StrandPalette.messageIncoming,
                        in: MessageBubbleShape(outgoing: outgoing, tail: tail))
    }
}

/// The bubble outline: a rounded body and, when asked, the curled tail at the bottom corner on the
/// sender's side. Drawn for the right side and mirrored for the left.
struct MessageBubbleShape: Shape {
    static let tailWidth: CGFloat = 6
    let outgoing: Bool
    let tail: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let bw = w - Self.tailWidth
        let r = min(18, h / 2)
        let k: CGFloat = 0.552 * r
        var p = Path()
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: bw - r, y: 0))
        p.addCurve(to: CGPoint(x: bw, y: r), control1: CGPoint(x: bw - r + k, y: 0), control2: CGPoint(x: bw, y: r - k))
        if tail {
            p.addLine(to: CGPoint(x: bw, y: h - 12))
            p.addCurve(to: CGPoint(x: w, y: h), control1: CGPoint(x: bw, y: h - 4), control2: CGPoint(x: w - 2, y: h))
            p.addCurve(to: CGPoint(x: bw - 8, y: h - 3), control1: CGPoint(x: w - 4, y: h + 0.5), control2: CGPoint(x: bw - 4, y: h - 1))
            p.addCurve(to: CGPoint(x: bw - r, y: h), control1: CGPoint(x: bw - 11, y: h - 0.5), control2: CGPoint(x: bw - r + 4, y: h))
        } else {
            p.addLine(to: CGPoint(x: bw, y: h - r))
            p.addCurve(to: CGPoint(x: bw - r, y: h), control1: CGPoint(x: bw, y: h - r + k), control2: CGPoint(x: bw - r + k, y: h))
        }
        p.addLine(to: CGPoint(x: r, y: h))
        p.addCurve(to: CGPoint(x: 0, y: h - r), control1: CGPoint(x: r - k, y: h), control2: CGPoint(x: 0, y: h - r + k))
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addCurve(to: CGPoint(x: r, y: 0), control1: CGPoint(x: 0, y: r - k), control2: CGPoint(x: r - k, y: 0))
        p.closeSubpath()
        guard !outgoing else { return p.offsetBy(dx: rect.minX, dy: rect.minY) }
        let mirror = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0)
        return p.applying(mirror).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

extension View {
    /// Interactive Liquid Glass in `shape` (iOS 26 / macOS 26); a bar material with a hairline before.
    @ViewBuilder
    func messageGlass<S: InsettableShape>(_ shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.messageMaterial(shape)
        }
        #else
        self.messageMaterial(shape)
        #endif
    }

    private func messageMaterial<S: InsettableShape>(_ shape: S) -> some View {
        self
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
    }
}
