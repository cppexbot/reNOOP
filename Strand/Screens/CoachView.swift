import SwiftUI
import MarkdownUI
import StrandDesign

/// Coach, the one feature in NOOP that talks to the network, drawn as a Messages conversation (iOS 26):
/// the contact header with the Coach circle, grey reply bubbles and blue question bubbles with the
/// system's tails, "Today 09:41" stamps, "Delivered" / "Not Delivered", the typing bubble, and the
/// "+" circle beside a glass field with the mic inside it. Suggested questions sit behind the "+" and,
/// while the field is empty and active, in an Apple Intelligence row under it. The provider, model and
/// key live in the settings sheet.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Low Power Mode / Quiet Motion pose the typing dots still too.
    @ObservedObject private var motion = NoopMotionState.shared

    /// #2243: provider, key, model, data access, instructions and the morning brief, in one sheet. A
    /// sheet behaves the same in all three places CoachView appears (macOS route, Browse push, pillar
    /// sheet), which a push would not.
    @State private var showSettings = false
    /// Bumped when a reply lands; the system's light impact follows it (`sensoryFeedback`).
    @State private var replyArrived = 0
    /// The "Try Again" menu of a failed question, opened from its red "!".
    @State private var showFailure = false

    /// When each message arrived, for the time stamps; recorded only after the prior launch's
    /// transcript is restored, so restored messages never read as new.
    @State private var times: [UUID: Date] = CoachMessageTimes.load()
    @State private var historyLoaded = false
    /// The transcript's visible size: the blue gradient spans its height, bubbles cap at its width.
    @State private var viewport: CGSize = .zero
    /// The screen's bottom safe area, to seat the field 28 pt from the bottom edge as Messages does.
    @State private var bottomInset: CGFloat = 0

    // Messages' motion. A sent question flies from the field into its place; "Delivered" follows a
    // beat later, and only then the typing bubble grows in; when the reply comes the bubble shrinks
    // away first and the reply fades in where it was.
    @State private var flight: OutgoingFlight?
    /// Where the flight lands. Written by the landing bubble as the transcript scrolls and read by the
    /// flight on each frame, so it lives outside SwiftUI's state: a change must not redraw the screen.
    @State private var flightTarget = FlightTarget()
    @State private var fieldFrame: CGRect = .zero
    /// A question just sent, whose "Delivered" (and the typing bubble after it) waits its beat.
    @State private var awaitingDelivery: UUID?
    @State private var typingShownAt: Date?
    @State private var typingEndedAt: Date?
    /// The reply that arrived while the typing bubble is still shrinking away.
    @State private var heldReply: UUID?

    // K4: on-device voice input for the composer (iOS only).
    #if os(iOS)
    @StateObject private var voiceInput = CoachVoiceInput()
    @ScaledMetric(relativeTo: .body) private var micWidth: CGFloat = 37
    #endif
    @ScaledMetric(relativeTo: .caption2) private var lockSize: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var plusSize: CGFloat = 19
    @ScaledMetric(relativeTo: .body) private var plusDisc: CGFloat = 40
    @ScaledMetric(relativeTo: .title2) private var failureSide: CGFloat = 24
    @ScaledMetric(relativeTo: .callout) private var sendWidth: CGFloat = 38
    @ScaledMetric(relativeTo: .callout) private var sendHeight: CGFloat = 28

    var body: some View {
        Group {
            if coach.isConfigured {
                chrome(conversation)
                    .overlay(alignment: .topLeading) {
                        if let flight {
                            FlyingMessageBubble(flight: flight, target: flightTarget, viewportHeight: viewport.height)
                        }
                    }
                    .coordinateSpace(name: MessageBubbleFill.space)
            } else {
                EmptyStateView(title: Text("Coach"), systemImage: "sparkles",
                               description: Text("Connect your own AI provider.")) {
                    Button("Set Up") { showSettings = true }
                        .buttonStyle(.borderedProminent)
                        .tint(StrandPalette.messageSend)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StrandPalette.plainPage.ignoresSafeArea())
        .navigationTitle(Text("Coach"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // A conversation owns the whole screen, as in Messages: the field sits where the tab bar was.
        .toolbar(.hidden, for: .tabBar)
        #endif
        .toolbar {
            #if os(iOS)
            // The header below carries the name, so the bar keeps only its buttons.
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .barGlyph()
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
            historyLoaded = true
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
            if !isSending && !coach.messages.isEmpty { replyArrived += 1 }
        }
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .light), trigger: replyArrived)
        #endif
        // A consent toggle after the initial load re-checks the brief; `startBriefIfNeeded` is a no-op
        // once a conversation exists.
        .onChangeCompat(of: coach.dataConsent) { _ in
            Task { await coach.startBriefIfNeeded() }
        }
        .onChangeCompat(of: coach.messages.map(\.id)) { ids in
            recordTimes(ids)
            track(ids)
        }
        .onChangeCompat(of: wantsTyping) { updateTyping($0) }
        .onAppear { updateTyping(wantsTyping) }
        // A flight ends when its spring has settled on its own clock; the bubble underneath takes over.
        .task(id: flight?.start) {
            guard let start = flight?.start else { return }
            while flight?.start == start, flightTarget.elapsed < OutgoingFlight.duration {
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            if flight?.start == start { flight = nil }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.bottom }) { bottomInset = $0 }
    }

    // MARK: - Chrome

    /// The header over the transcript and the field under it, as bars the content scrolls beneath
    /// (with the soft scroll-edge blur on iOS 26). The header rises into the navigation bar so the Coach
    /// circle's top lines up with the back button's, as in Messages.
    @ViewBuilder
    private func chrome<Content: View>(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .safeAreaBar(edge: .top, spacing: 0) { header }
                .safeAreaBar(edge: .bottom, spacing: 0) { composer }
        } else {
            legacyChrome(content)
        }
        #else
        legacyChrome(content)
        #endif
    }

    private func legacyChrome<Content: View>(_ content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { header.background(.bar) }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
    }

    private var header: some View {
        CoachConversationHeader { showSettings = true }
            .frame(maxWidth: .infinity)
            #if os(iOS)
            .padding(.top, -Self.headerLift)
            #else
            .padding(.top, 8)
            #endif
            .padding(.bottom, 4)
    }

    /// How far the header reaches up into the navigation bar.
    private static let headerLift: CGFloat = 54

    // MARK: - Conversation

    /// The messages the transcript draws: the streaming reply's empty placeholder is left to the typing
    /// bubble until its first words arrive.
    private var shown: [ChatMessage] {
        coach.messages.filter {
            $0.id != heldReply
                && ($0.role == .user || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// The typing bubble shows while a reply is on its way and none of it is on screen yet, once the
    /// question it answers reads as delivered.
    private var wantsTyping: Bool {
        let replyStarted = coach.messages.last.map {
            $0.role == .assistant && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        return coach.sending && awaitingDelivery == nil && !replyStarted
    }

    private var conversation: some View {
        let messages = shown
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    serviceLine
                        .padding(.top, 18)
                        .padding(.bottom, messages.isEmpty ? 0 : 15)
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        row(message, index: index, in: messages)
                            .id(message.id)
                            // A reply fades in over half a second; a question arrives by its flight.
                            .transition(message.role == .assistant ? .opacity : .identity)
                    }
                    if let typingShownAt {
                        MessageTypingIndicator(still: motion.poseStill(reduceMotion),
                                               appearedAt: typingShownAt, endedAt: typingEndedAt)
                            .padding(.bottom, MessageTypingIndicator.overhang)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 20)
                            .padding(.top, messages.last?.role == .user ? 10 : 0)
                            .accessibilityLabel(Text("Coach is thinking"))
                    }
                    if let error = coach.errorText, !error.isEmpty, messages.last?.role != .user {
                        errorLine(error)
                    }
                    Color.clear.frame(height: 16).id("end")
                }
                .animation(.easeInOut(duration: 0.5), value: messages.map(\.id))
                .animation(.easeInOut(duration: 0.25), value: awaitingDelivery)
                #if os(macOS)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                #endif
            }
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { viewport = $0 }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChangeCompat(of: messages.map(\.id)) { _ in scrollToEnd(proxy) }
            .onChangeCompat(of: typingShownAt) { _ in scrollToEnd(proxy) }
            .onChangeCompat(of: awaitingDelivery) { _ in scrollToEnd(proxy) }
            .onChangeCompat(of: coach.errorText) { _ in scrollToEnd(proxy) }
        }
    }

    /// Where the conversation goes, in place of Messages' "iMessage · Encrypted": the provider, and
    /// that nothing leaves the device until a question is asked.
    private var serviceLine: some View {
        VStack(spacing: 0) {
            if coach.provider == .custom {
                Text("Your server").fontWeight(.medium)
            } else {
                Text(verbatim: coach.provider.displayName).fontWeight(.medium)
            }
            HStack(spacing: 3) {
                Image(systemName: "lock.fill").font(.system(size: lockSize, weight: .semibold))
                Text("Only when you ask")
            }
        }
        .font(StrandFont.pro(11))
        .foregroundStyle(StrandPalette.messageMeta)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// One message with what Messages draws around it: the time stamp above, and the delivery status
    /// (or the failure) below the last question.
    @ViewBuilder
    private func row(_ message: ChatMessage, index: Int, in messages: [ChatMessage]) -> some View {
        let isLast = index == messages.count - 1
        let next = isLast ? nil : messages[index + 1]
        let tail = next?.role != message.role
        let failed = isLast && message.role == .user && !coach.sending && coach.errorText?.isEmpty == false
        let delivered = message.id == deliveredID(in: messages) && !failed
        VStack(spacing: 0) {
            if let stamp = stamp(before: index, in: messages) {
                stampView(stamp)
                    .padding(.top, index == 0 ? 0 : 10)
                    .padding(.bottom, 7)
            }
            if failed {
                HStack(alignment: .center, spacing: 8) {
                    Spacer(minLength: 0)
                    bubble(message, tail: tail)
                    failureButton
                }
                .padding(.trailing, 17)
                Text("Not Delivered")
                    .font(StrandFont.pro(11, weight: .medium))
                    .foregroundStyle(StrandPalette.messageFailure)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 29)
                if coach.keyRejected {
                    Button("Update Key") { showSettings = true }
                        .buttonStyle(.plain)
                        .font(StrandFont.pro(11, weight: .medium))
                        .foregroundStyle(StrandPalette.messageSend)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 29)
                        .padding(.top, 2)
                }
            } else {
                HStack(spacing: 0) {
                    if message.role == .user { Spacer(minLength: 0) }
                    bubble(message, tail: tail)
                    if message.role == .assistant { Spacer(minLength: 0) }
                }
                .padding(.horizontal, 20)
                if delivered {
                    Text("Delivered")
                        .transition(.opacity)
                        .font(StrandFont.pro(11, weight: .medium))
                        .foregroundStyle(StrandPalette.messageMeta)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 40)
                        .padding(.top, -1)
                }
            }
        }
        // Messages' spacing: 4 pt inside a run from one side, 10 pt between runs, counted from the
        // bubble's body (a tail reaches into the gap).
        .padding(.bottom, next.map { next in
            if delivered { return 10 }
            return (next.role == message.role ? 4 : 10) - (tail ? MessageBubbleShape.tailHeight : 0)
        } ?? 0)
    }

    /// The question "Delivered" sits under: the latest one, even after the reply has come in, as
    /// Messages keeps it; while a new question waits for its beat the status stays on the one before,
    /// and then moves across.
    private func deliveredID(in messages: [ChatMessage]) -> UUID? {
        messages.last { $0.role == .user && $0.id != awaitingDelivery && !isLanding($0) }?.id
    }

    /// Messages stamps the head of a conversation and any message that follows the previous one by an
    /// hour or more. Messages with no recorded time get no stamp.
    private func stamp(before index: Int, in messages: [ChatMessage]) -> Date? {
        guard let time = times[messages[index].id] else { return nil }
        guard index > 0 else { return time }
        guard let previous = times[messages[index - 1].id] else { return nil }
        return time.timeIntervalSince(previous) >= 3600 ? time : nil
    }

    private func stampView(_ date: Date) -> some View {
        HStack(spacing: 3) {
            dayWord(date).fontWeight(.medium)
            Text(date, format: .dateTime.hour().minute())
        }
        .font(StrandFont.pro(11))
        .foregroundStyle(StrandPalette.messageMeta)
        .frame(maxWidth: .infinity)
    }

    private func dayWord(_ date: Date) -> Text {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return Text("Today") }
        if calendar.isDateInYesterday(date) { return Text("Yesterday") }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return Text(date, format: .dateTime.weekday(.wide))
        }
        return Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Bubbles cap at 85 % of the transcript less its gutters, as Messages sizes them.
    private var maxBubbleWidth: CGFloat { max(160, 0.85 * (viewport.width - 80)) }

    @ViewBuilder
    private func bubble(_ message: ChatMessage, tail: Bool) -> some View {
        let outgoing = message.role == .user
        let landing = isLanding(message)
        Group {
            if outgoing {
                // Questions stay verbatim `Text`, so a typed `*` or `#` never turns into formatting.
                Text(message.text)
                    .font(StrandFont.pro(17))
                    .foregroundStyle(StrandPalette.messageOutgoingText)
            } else {
                // Replies arrive as Markdown (bold, lists, headings, tables).
                Markdown(message.text)
                    .markdownTheme(.strand)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: MessageBubbleShape.minSide, minHeight: MessageBubbleShape.minSide)
        .padding(.bottom, tail ? MessageBubbleShape.tailHeight : 0)
        .background {
            MessageBubbleFill(outgoing: outgoing, viewportHeight: viewport.height)
                .clipShape(MessageBubbleShape(outgoing: outgoing, tail: tail))
        }
        #if os(iOS)
        // Long-press lifts the bubble itself, tail and all, as Messages does.
        .contentShape(.contextMenuPreview, MessageBubbleShape(outgoing: outgoing, tail: tail))
        #endif
        // While its flight is in the air the bubble holds its place unseen and tells the flight where
        // to land.
        .opacity(landing ? 0 : 1)
        .animation(nil, value: landing)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(MessageBubbleFill.space)) }) { frame in
            if landing { flightTarget.rect = frame }
        }
        // K8: Copy / Share / Save (a reply).
        .contextMenu {
            Button {
                PlatformPasteboard.copy(message.text)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            ShareLink(item: message.text) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            if !outgoing {
                Button { saveAdvice(message.text) } label: {
                    Label("Save to Journal", systemImage: "book")
                }
            }
        }
        .frame(maxWidth: maxBubbleWidth, alignment: outgoing ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(outgoing ? Text("You said: \(message.text)") : Text("Coach said: \(message.text)"))
    }

    /// Messages' red "!" beside an undelivered message; it opens "Try Again" (and the key, when the
    /// provider turned it away).
    private var failureButton: some View {
        Button { showFailure = true } label: {
            Image(systemName: "exclamationmark.circle")
                .font(StrandFont.pro(22))
                .foregroundStyle(StrandPalette.messageFailure)
                .frame(width: failureSide, height: failureSide)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Not Delivered"))
        .confirmationDialog(Text(verbatim: coach.errorText ?? ""), isPresented: $showFailure, titleVisibility: .visible) {
            Button("Try Again") { retry() }
            if coach.keyRejected {
                Button("Update Key") { showSettings = true }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// A failure with no question of its own to mark (the brief, or a reply cut off mid-way): the reason
    /// in the transcript's small grey type, with the key when the provider turned it away.
    private func errorLine(_ message: String) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: message)
                .foregroundStyle(StrandPalette.messageMeta)
            if coach.keyRejected {
                Button("Update Key") { showSettings = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(StrandPalette.messageSend)
            }
        }
        .font(StrandFont.pro(11, weight: .medium))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 10)
    }

    // MARK: - Composer

    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// K7: follow-ups once the coach has answered, contextual questions otherwise.
    private var suggestions: [String] {
        coach.messages.last?.role == .assistant ? AICoachEngine.followUpSuggestions : coach.suggestions
    }

    /// Suggestions under the field while it is empty: when the keyboard is up, and on an empty chat.
    private var showSuggestionRow: Bool {
        !hasDraft && !coach.sending && (composerFocused || coach.messages.isEmpty)
    }

    /// Messages' entry row: the "+" circle, then the glass field with the mic, or the send arrow once
    /// there is something to send.
    private var composer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                plusMenu
                field
            }
            .padding(.horizontal, Self.composerInset)
            if showSuggestionRow {
                suggestionRow
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        #if os(iOS)
        .padding(.top, 8)
        // 28 pt off the screen's bottom edge, concentric with its corners; just above the keyboard
        // while typing.
        .padding(.bottom, composerFocused ? 8 : 28 - bottomInset)
        #else
        .padding(.vertical, 12)
        #endif
        .animation(StrandMotion.fade, value: showSuggestionRow)
    }

    /// The field's side margins: 28 pt on iOS, concentric with the screen's corners.
    #if os(iOS)
    private static let composerInset: CGFloat = 28
    #else
    private static let composerInset: CGFloat = 16
    #endif

    private var plusMenu: some View {
        Menu {
            ForEach(suggestions, id: \.self) { prompt in
                Button { send(Self.localized(prompt)) } label: {
                    Label(Self.localized(prompt), systemImage: "sparkles")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: plusSize))
                .foregroundStyle(StrandPalette.messageIncomingText)
                .frame(width: plusDisc, height: plusDisc)
                .messageGlass(Circle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(coach.sending)
        .accessibilityLabel(Text("Suggestions"))
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("Ask Coach", text: $draft, prompt: placeholder, axis: .vertical)
                .textFieldStyle(.plain)
                .font(StrandFont.pro(17))
                .foregroundStyle(StrandPalette.messageIncomingText)
                .lineLimit(1...6)
                .focused($composerFocused)
                .onSubmit { send(draft) }
                .padding(.vertical, 10)
                .padding(.leading, 14)
                .accessibilityLabel(Text("Question"))
            trailingControl
        }
        .frame(minHeight: MessageBubbleShape.minSide)
        .messageGlass(RoundedRectangle(cornerRadius: 20.14, style: .continuous))
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(MessageBubbleFill.space)) }) { fieldFrame = $0 }
    }

    private var placeholder: Text {
        #if os(iOS)
        Text("Ask Coach").foregroundStyle(StrandPalette.messagePlaceholder)
        #else
        Text("Ask Coach").foregroundColor(StrandPalette.messagePlaceholder)
        #endif
    }

    /// Apple Intelligence's suggestion row: the questions in its wash, hairlines between them.
    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, prompt in
                    if index > 0 {
                        Rectangle()
                            .fill(StrandPalette.hairline)
                            .frame(width: NoopMetrics.hairlineWidth, height: 22)
                    }
                    Button { send(Self.localized(prompt)) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles").font(StrandFont.pro(13, weight: .medium))
                            Text(verbatim: Self.localized(prompt)).font(StrandFont.pro(15))
                        }
                        .foregroundStyle(LinearGradient(colors: [StrandPalette.messageSuggestionStart,
                                                                 StrandPalette.messageSuggestionEnd],
                                                        startPoint: .leading, endPoint: .trailing))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Suggested prompt: \(Self.localized(prompt))"))
                }
            }
            .padding(.horizontal, Self.composerInset)
        }
    }

    /// The suggestion strings come from the engine in English; they read, and are sent, in the app's
    /// language.
    private static func localized(_ prompt: String) -> String {
        String(localized: String.LocalizationValue(prompt))
    }

    /// The send arrow once there is something to send; the mic (iOS) while the field is empty.
    @ViewBuilder
    private var trailingControl: some View {
        if hasDraft {
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(StrandFont.pro(16, weight: .bold))
                    .foregroundStyle(StrandPalette.messageOutgoingText)
                    .frame(width: sendWidth, height: sendHeight)
                    .background(StrandPalette.messageSend, in: Capsule())
                    .opacity(coach.sending ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(coach.sending)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
            .accessibilityLabel(Text("Send"))
        } else {
            #if os(iOS)
            micButton
            #else
            Color.clear.frame(width: 14, height: 1)
            #endif
        }
    }

    // MARK: - K4: Voice input (iOS only)

    #if os(iOS)
    private var micButton: some View {
        Button { toggleVoice() } label: {
            Image(systemName: voiceInput.isRecording ? "stop.circle.fill" : "mic")
                .font(StrandFont.pro(17))
                .foregroundStyle(voiceInput.isRecording ? StrandPalette.messageFailure : StrandPalette.messageFieldGlyph)
                .frame(width: micWidth)
                .frame(minHeight: MessageBubbleShape.minSide)
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
        launch(trimmed)
        draft = ""
        composerFocused = false
        Task { await coach.send(trimmed) }
    }

    /// Sets a question off from the field (unless motion is posed still) and holds its "Delivered"
    /// for the beat Messages takes to show it.
    private func launch(_ text: String) {
        if !motion.poseStill(reduceMotion), fieldFrame != .zero {
            flightTarget.rect = nil
            flightTarget.restart()
            flight = OutgoingFlight(text: text, from: fieldFrame, start: Date())
        }
    }

    /// The question a flight is carrying: bound by id once known, and by its text from the very first
    /// frame it is on screen, so it never shows before its flight lands.
    private func isLanding(_ message: ChatMessage) -> Bool {
        guard let flight, message.role == .user else { return false }
        if let id = flight.messageID { return id == message.id }
        return message.id == coach.messages.last(where: { $0.role == .user })?.id && message.text == flight.text
    }

    /// Follows the transcript: ties a flight to the message it became, and lets a reply that arrives
    /// while the typing bubble is up wait for it to shrink away.
    private func track(_ ids: [UUID]) {
        if var current = flight, current.messageID == nil,
           let landed = coach.messages.last(where: { $0.role == .user && $0.text == current.text }),
           !(times[landed.id].map { $0 < current.start } ?? false) {
            current.messageID = landed.id
            // The clock starts on the frame the message is really there: building the request can hold
            // the main thread for a moment first, and the flight should not skip ahead through it.
            current = OutgoingFlight(text: current.text, from: current.from, start: Date(), messageID: landed.id)
            flightTarget.restart()
            flight = current
            awaitingDelivery = landed.id
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if awaitingDelivery == landed.id { awaitingDelivery = nil }
            }
        }
    }

    /// The typing bubble grows in when it is wanted and shrinks away when it is not; a reply that
    /// ended it waits out the shrink before it fades in.
    private func updateTyping(_ wanted: Bool) {
        if wanted {
            typingEndedAt = nil
            if typingShownAt == nil { typingShownAt = Date() }
            return
        }
        guard typingShownAt != nil, typingEndedAt == nil else { return }
        guard !motion.poseStill(reduceMotion) else { typingShownAt = nil; return }
        let ended = Date()
        typingEndedAt = ended
        if let reply = coach.messages.last, reply.role == .assistant { heldReply = reply.id }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(MessageTypingIndicator.shrinkDuration * 1_000_000_000))
            guard typingEndedAt == ended else { return }
            typingShownAt = nil
            typingEndedAt = nil
            heldReply = nil
        }
    }

    /// "Try Again" on an undelivered question: it leaves the transcript and is asked afresh, landing at
    /// the bottom as Messages resends it.
    private func retry() {
        guard !coach.sending, let failed = coach.messages.last, failed.role == .user else { return }
        coach.messages.removeLast()
        Task { await coach.send(failed.text) }
    }

    /// K8: save a reply to the journal as a note, under a fixed question ("Coach advice").
    private func saveAdvice(_ text: String) {
        let day = Repository.localDayKey(Date())
        Task {
            await repo.saveJournalAnswer(day: day, question: "Coach advice", answeredYes: true, notes: text)
        }
    }

    /// Stamps the messages that arrive while the screen is up; forgets the ones that have left.
    private func recordTimes(_ ids: [UUID]) {
        guard historyLoaded else { return }
        var next = times.filter { ids.contains($0.key) }
        for id in ids where next[id] == nil { next[id] = Date() }
        guard next != times else { return }
        times = next
        CoachMessageTimes.save(next)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        // Messages scrolls a new message in over 0.3 s.
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("end", anchor: .bottom) }
    }
}
