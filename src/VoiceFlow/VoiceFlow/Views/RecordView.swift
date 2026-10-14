import SwiftUI
import VoiceFlowKit

#if canImport(UIKit)
import UIKit
#endif

struct RecordView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.colorScheme) private var colorScheme
    @State private var showOpenCodeInfo = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var showCopyCheckmark = false
    @State private var isEditingTranscript = false
    @State private var toolbarFeedbackTask: Task<Void, Never>?
    @State private var toolbarFeedbackText: String?

    var body: some View {
        ZStack {
            DesignTokens.Palette.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: isEditingTranscript
                    ? DesignTokens.Spacing.s
                    : DesignTokens.Spacing.xxl)

                timerHeader

                Spacer().frame(height: isEditingTranscript
                    ? DesignTokens.Spacing.s
                    : DesignTokens.Spacing.l)

                WaveformView(
                    mode: waveformMode,
                    color: waveformColor,
                    level: appState.audioLevel
                )
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .accessibilityIdentifier("record.waveform")
                .frame(height: isEditingTranscript ? 0 : DesignTokens.Sizing.waveformHeight)
                .opacity(isEditingTranscript ? 0 : 1)

                Spacer().frame(height: isEditingTranscript
                    ? DesignTokens.Spacing.s
                    : DesignTokens.Spacing.xxl)

                transcriptArea

                Spacer(minLength: DesignTokens.Spacing.l)

                primaryAction

                Spacer().frame(height: DesignTokens.Spacing.m)

                secondaryControls

                Spacer().frame(height: DesignTokens.Spacing.l)
            }
            .animation(.easeInOut(duration: 0.3), value: isEditingTranscript)
        }
        .toolbar(.hidden, for: .navigationBar)
        // Tapping anywhere outside the transcript editor dismisses the
        // keyboard (the editor keeps focus for taps inside it). Without
        // this the keyboard had no way to go down on the Record screen.
        .dismissKeyboardOnTapOutsideTextInputs()
        .onDisappear {
            toolbarFeedbackTask?.cancel()
            toolbarFeedbackTask = nil
            toolbarFeedbackText = nil
        }
        #if os(visionOS)
        .frame(minWidth: 400, idealWidth: 600, maxWidth: 800,
               minHeight: 400, idealHeight: 1000, maxHeight: 1500)
        #endif
        .alert(
            Text(localized("record.error.alert.title")),
            isPresented: recordErrorAlertPresented
        ) {
            Button(localized("record.error.alert.ok"), role: .cancel) {
                appState.dismissRecordError()
            }
            .accessibilityIdentifier("record.error.alert.okButton")
        } message: {
            if let key = appState.recordErrorAlertKey {
                Text(localized(key))
            }
        }
        .alert(
            Text(localized("record.sendToOpenCode")),
            isPresented: $showOpenCodeInfo
        ) {
            Button(localized("record.error.alert.ok"), role: .cancel) {}
                .accessibilityIdentifier("record.openCode.info.okButton")
        } message: {
            Text(localized("record.openCode.optional"))
        }
        .alert(
            Text(localized("record.save.confirmation.title")),
            isPresented: savedRecordingAlertPresented
        ) {
            Button(localized("record.error.alert.ok"), role: .cancel) {
                appState.acknowledgeSavedRecordingAlert()
            }
            .accessibilityIdentifier("record.save.confirmation.okButton")
        } message: {
            if let savedRecording = appState.lastSavedRecording {
                Text(
                    String(
                        format: localized("record.save.confirmation.message"),
                        savedRecording.fileName
                    )
                )
            }
        }
    }

    // MARK: - Sections

    private var timerHeader: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            // Timer uses the regular system face (56pt thin) — the Pixelate
            // look is dialed back to a hint, so the big timer stays neutral.
            // monospacedDigit keeps the digits from jittering as they tick.
            // In editing mode the timer shrinks to captionSub to reclaim
            // vertical space for the keyboard-compacted transcript area.
            Text(appState.recordingTimerText)
                .font(isEditingTranscript
                    ? DesignTokens.Typography.captionSub
                    : DesignTokens.Typography.timer)
                .foregroundStyle(DesignTokens.Palette.textPrimary)
                .monospacedDigit()
                .accessibilityIdentifier("record.recordingTimer")

            StatusText(key: statusTextKey, role: statusTextRole)
                .padding(.horizontal, DesignTokens.Spacing.xl)
        }
    }

    private var transcriptArea: some View {
        // The editor is its own view bound to `$appState.transcript`, so a
        // streamed transcript update invalidates only this subview — not the
        // whole RecordView body (which also reads audioLevel, timer text,
        // recordingStatus, button states…). That body-wide invalidation was
        // what made the *whole UI* flash on every partial.
        VStack(spacing: DesignTokens.Spacing.s) {
            if appState.showTranscriptWarning {
                Text(localized("record.signal.shortRecording"))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignTokens.Spacing.xl)
                    .padding(.top, DesignTokens.Spacing.s)
                    .accessibilityIdentifier("record.transcript.warning")
            }
            TranscriptEditor(
                text: $appState.transcript,
                placeholder: localized("record.transcript.placeholder"),
                isLocked: appState.customActionState.isRunning || appState.isTranscriptChunkLocked,
                isEditing: $isEditingTranscript
            )

            transcriptToolbar
        }
        .frame(maxHeight: .infinity)
    }

    /// Transcript toolbar attached to the text surface: custom action on the
    /// left; on the right the transcript-mode toggle sits leftmost of the
    /// document actions (clear, copy). Everything stays muted gray except the
    /// mode toggle when append is active, so nothing competes with the Record
    /// capsule below.
    ///
    /// All actions stay visible on an empty page to keep their positions
    /// stable. Empty copy clears the clipboard; clear/custom action are
    /// harmless no-ops with confirmation in the existing status line.
    private var transcriptToolbar: some View {
        HStack {
            customActionButton
            Spacer()
            transcriptModeButton
            trashButton
            copyButton
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.top, DesignTokens.Spacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("record.transcriptToolbar")
    }

    private var customActionButton: some View {
        let actionName = appState.customActionDisplayLabel
        let isRunning = appState.customActionState.isRunning

        return Button {
            if isRunning {
                appState.cancelCustomAction()
                showToolbarFeedback(localized("record.customAction.cancelled"))
            } else if !appState.canCopyTranscript {
                showToolbarFeedback(localized("record.customAction.empty"))
            } else {
                // A previous mode/copy toast must not delay the new action's
                // running or error status.
                toolbarFeedbackTask?.cancel()
                toolbarFeedbackTask = nil
                toolbarFeedbackText = nil
                appState.runCustomAction()
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else if case .failed = appState.customActionState {
                    Image(systemName: "exclamationmark.triangle")
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(isRunning ? localized("record.customAction.cancel") : actionName)
                    .lineLimit(1)
            }
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Palette.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .buttonStyle(.plain)
        .disabled(!isRunning && !(appState.canRunCustomAction
            || (!appState.canCopyTranscript && appState.canNavigateTranscriptHistory)))
        .accessibilityIdentifier("record.customActionButton")
        .accessibilityLabel(Text(isRunning ? localized("record.customAction.cancel") : actionName))
    }

    private var copyButton: some View {
        Button {
            appState.copyTranscript()
            let didCopy = appState.lastClipboardStatusKey == "record.clipboard.copied"
            showToolbarFeedback(localized(didCopy
                ? (appState.transcript.isEmpty ? "record.clipboard.emptyCopied" : "record.clipboard.copied")
                : "record.clipboard.failed"))
            guard didCopy else { return }
            showCopyCheckmark = true
            copyFeedbackTask?.cancel()
            copyFeedbackTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                if !Task.isCancelled {
                    showCopyCheckmark = false
                }
            }
        } label: {
            Image(systemName: showCopyCheckmark ? "checkmark" : "doc.on.doc")
                .font(.system(size: DesignTokens.Sizing.ghostIcon, weight: .regular))
                .frame(width: 44, height: 44)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("record.copyButton")
        .accessibilityLabel(Text(localized("record.copy")))
    }

    /// Trash: archive the current transcript into history and clear the
    /// transcript area. Works in both modes; the left chevron restores the
    /// just-archived entry, so no confirmation dialog is needed.
    private var trashButton: some View {
        Button {
            let hadText = appState.canCopyTranscript
            appState.clearTranscriptToHistory()
            if hadText { appState.clearCustomActionFailure() }
            showToolbarFeedback(localized(hadText ? "record.clear.cleared" : "record.clear.empty"))
        } label: {
            Image(systemName: "trash")
                .font(.system(size: DesignTokens.Sizing.ghostIcon, weight: .regular))
                .frame(width: 44, height: 44)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!appState.canNavigateTranscriptHistory || appState.chunkInFlight)
        .accessibilityIdentifier("record.clearTranscriptButton")
        .accessibilityLabel(Text(localized("record.clear")))
    }

    private var primaryAction: some View {
        CapsuleButton(
            title: LocalizedStringKey(appState.canStopRecording ? "record.stop" : "record.start"),
            role: appState.canStopRecording ? .secondary : .primary,
            action: toggleRecording,
            isEnabled: appState.canStartRecording || appState.canStopRecording
        )
        .accessibilityIdentifier(appState.canStopRecording ? "record.stopButton" : "record.startButton")
    }

    private var secondaryControls: some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            GhostIconButton(
                systemName: transcriptPreviousIcon,
                action: appState.navigatePreviousTranscript,
                isEnabled: appState.canNavigatePreviousTranscript,
                accessibilityLabel: transcriptPreviousLabel
            )
            .accessibilityIdentifier("record.historyPreviousButton")

            Menu {
                Button(action: { Task { await appState.sendTranscriptToOpenCode() } }) {
                    Label {
                        Text(openCodeMenuLabel)
                    } icon: {
                        Image(systemName: openCodeMenuIcon)
                    }
                }
                .disabled(!appState.canSendToOpenCode || appState.openCodeSendStatus == .sending)
                .accessibilityIdentifier("record.sendOpenCodeButton")

                Button(action: appState.saveCurrentRecording) {
                    Label {
                        Text(localized("record.saveRecording"))
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .disabled(!appState.canSaveRecording)
                .accessibilityIdentifier("record.saveRecordingButton")

                Button(action: { Task { await appState.resendLastRecording() } }) {
                    Label {
                        Text(localized("record.resendRecording"))
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(!appState.canResendRecording)
                .accessibilityIdentifier("record.resendRecordingButton")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: DesignTokens.Sizing.ghostIcon, weight: .regular))
                    .frame(width: DesignTokens.Sizing.ghostButton,
                           height: DesignTokens.Sizing.ghostButton)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .contentShape(.hoverEffect, Circle())
                    .hoverEffect(.lift)
            }
            .accessibilityIdentifier("record.moreButton")

            GhostIconButton(
                systemName: transcriptNextIcon,
                action: appState.navigateNextTranscript,
                isEnabled: appState.canNavigateNextTranscript,
                accessibilityLabel: transcriptNextLabel
            )
            .accessibilityIdentifier("record.historyNextButton")
        }
    }

    /// Transcript-mode toggle, pinned to the left of the clear/copy buttons
    /// in the transcript toolbar. A single icon always shows the current
    /// mode — replace (each recording overwrites the page) or append (new
    /// text accumulates below the document) — so the mode is readable at a
    /// glance without opening a menu. Tapping flips it. Disabled while a
    /// recording is in flight or a custom action runs (the mode is captured
    /// at Start, so a mid-flight switch would not affect the in-flight chunk
    /// anyway); `canChangeTranscriptMode` gates both the action and the
    /// disabled styling.
    private var transcriptModeButton: some View {
        let isAppend = appState.transcriptMode == .append
        let isEnabled = appState.canChangeTranscriptMode
        return Button(action: toggleTranscriptMode) {
            Image(systemName: isAppend ? "text.append" : "arrow.left.arrow.right")
                .font(.system(size: DesignTokens.Sizing.ghostIcon, weight: .regular))
                .frame(width: 44, height: 44)
                .foregroundStyle(modeIconColor(isAppend: isAppend, isEnabled: isEnabled))
                .opacity(isEnabled ? 1.0 : 0.6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier("record.transcriptModeButton")
        .accessibilityLabel(Text(localized("record.transcriptMode.title")))
        .accessibilityValue(Text(modeAccessibilityValue))
        .accessibilityHint(Text(isEnabled ? modeSwitchHint : ""))
    }

    /// Replace is the default, quiet state, so its glyph rides at the same
    /// `textSecondary` weight as clear/copy. Append is the non-default
    /// "accumulate" state, so it takes the amber accent to signal that a
    /// special mode is active. Disabled drops to `textTertiary`.
    private func modeIconColor(isAppend: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return DesignTokens.Palette.textTertiary.color(for: colorScheme)
        }
        return isAppend
            ? DesignTokens.Palette.accent
            : DesignTokens.Palette.textSecondary.color(for: colorScheme)
    }

    private var modeAccessibilityValue: String {
        localized(
            appState.transcriptMode == .append
                ? "record.transcriptMode.append"
                : "record.transcriptMode.replace"
        )
    }

    private var modeSwitchHint: String {
        let otherKey = appState.transcriptMode == .append
            ? "record.transcriptMode.replace"
            : "record.transcriptMode.append"
        return String(format: localized("record.transcriptMode.switchHint"), localized(otherKey))
    }

    private func toggleTranscriptMode() {
        guard appState.canChangeTranscriptMode else { return }
        appState.transcriptMode = appState.transcriptMode == .replace ? .append : .replace
        showModeToast()
    }

    /// Confirm the newly selected mode as a ~2s toast in the status line
    /// (under the timer), then let the status line fall back to its normal
    /// content. Lives in the existing status text rather than the toolbar,
    /// so the toolbar row never shifts when the confirmation appears.
    private func showModeToast() {
        let modeKey = appState.transcriptMode == .append
            ? "record.transcriptMode.append"
            : "record.transcriptMode.replace"
        showToolbarFeedback(String(format: localized("record.transcriptMode.toast"), localized(modeKey)))
    }

    private func showToolbarFeedback(_ text: String) {
        toolbarFeedbackText = text
        toolbarFeedbackTask?.cancel()
        toolbarFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                toolbarFeedbackText = nil
            }
        }
    }

    // MARK: - Transcript history navigation (mode-aware)

    /// In append mode the history stack holds whole-document snapshots, so
    /// stepping through them reads as undo/redo of the document. In replace
    /// mode the same arrows step between individual recordings (history).
    /// The behavior is identical in both modes; only the framing changes.
    private var transcriptPreviousIcon: String {
        appState.transcriptMode == .append ? "arrow.uturn.backward" : "chevron.left"
    }

    private var transcriptNextIcon: String {
        appState.transcriptMode == .append ? "arrow.uturn.forward" : "chevron.right"
    }

    private var transcriptPreviousLabel: LocalizedStringKey {
        appState.transcriptMode == .append ? "record.undo" : "record.history"
    }

    private var transcriptNextLabel: LocalizedStringKey {
        appState.transcriptMode == .append ? "record.redo" : "record.history"
    }

    // MARK: - State derivations

    private var waveformMode: WaveformView.Mode {
        switch appState.recordingStatus {
        case .recording:    return .active
        case .transcribing: return .generating
        default:            return .idle
        }
    }

    private var waveformColor: Color {
        switch appState.recordingStatus {
        case .recording:
            if appState.hasActiveWaveformFeedback {
                return DesignTokens.Palette.accent
            }
            switch appState.streamConnectionPhase {
            case .connected, .generating: return DesignTokens.Palette.accent
            case .connecting, .recovering: return DesignTokens.Palette.textSecondary.color(for: colorScheme)
            case .disconnected: return DesignTokens.Palette.textTertiary.color(for: colorScheme)
            }
        case .transcribing:
            return DesignTokens.Palette.accent
        case .requestingPermission:
            return DesignTokens.Palette.textSecondary.color(for: colorScheme)
        case .idle, .ready:
            return DesignTokens.Palette.textTertiary.color(for: colorScheme)
        }
    }

    private var statusTextKey: LocalizedStringKey {
        // Confirm toolbar actions even when an older clipboard/save status is
        // still displayed. Active recording, transcription and sending win.
        if let toolbarFeedbackText,
           (appState.recordingStatus == .idle || appState.recordingStatus == .ready),
           appState.openCodeSendStatus != .sending {
            return LocalizedStringKey(toolbarFeedbackText)
        }
        if appState.customActionState.isRunning {
            return LocalizedStringKey(String(format: localized("record.customAction.running"), appState.customActionDisplayLabel))
        }
        if case .failed(let messageKey) = appState.customActionState,
           appState.recordingStatus == .idle || appState.recordingStatus == .ready {
            return LocalizedStringKey(messageKey)
        }
        if appState.openCodeSendStatus != .idle {
            return LocalizedStringKey(appState.openCodeSendStatus.localizedKey)
        }
        if let savedRecording = appState.lastSavedRecording {
            return LocalizedStringKey(String(
                format: localized("record.save.statusLine"),
                savedRecording.fileName
            ))
        }
        if let streamKey = appState.streamStatusCaptionKey {
            return LocalizedStringKey(streamKey)
        }
        if let clipboardKey = appState.lastClipboardStatusKey {
            return LocalizedStringKey(clipboardKey)
        }
        return LocalizedStringKey(appState.recordingStatus.localizedKey)
    }

    private var statusTextRole: StatusText.Role {
        switch appState.recordingStatus {
        case .recording:
            switch appState.streamConnectionPhase {
            case .connected, .generating: return .accent
            case .connecting, .recovering: return .neutral
            case .disconnected: return .muted
            }
        case .transcribing:
            return .accent
        case .idle, .ready, .requestingPermission:
            return .neutral
        }
    }

    private var openCodeMenuLabel: String {
        switch appState.openCodeSendStatus {
        case .sending: return localized("record.openCode.sending")
        case .success: return localized("record.openCode.sent")
        case .failed:  return localized("record.openCode.error.sendFailed")
        case .idle:    return localized("record.sendToOpenCode")
        }
    }

    private var openCodeMenuIcon: String {
        switch appState.openCodeSendStatus {
        case .sending: return "paperplane"
        case .success: return "checkmark.circle"
        case .failed:  return "exclamationmark.triangle"
        case .idle:    return "paperplane"
        }
    }

    // MARK: - Bindings

    private var savedRecordingAlertPresented: Binding<Bool> {
        Binding(
            get: { appState.shouldPresentSavedRecordingAlert },
            set: { isPresented in
                if !isPresented {
                    appState.acknowledgeSavedRecordingAlert()
                }
            }
        )
    }

    private var recordErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { appState.recordErrorAlertKey != nil },
            set: { isPresented in
                if !isPresented {
                    appState.dismissRecordError()
                }
            }
        )
    }

    private func toggleRecording() {
        if appState.canStopRecording {
            Task { await appState.stopRecording() }
        } else {
            Task { await appState.startRecording() }
        }
    }

    private func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: localizationBundle)
    }
}

/// The transcript text editor as its own view. Bound to the transcript string,
/// so a streamed update re-evaluates only this view rather than the entire
/// RecordView body — which is what stops the whole screen flashing per partial.
private struct TranscriptEditor: View {
    @Binding var text: String
    let placeholder: String
    var isLocked: Bool = false
    @Binding var isEditing: Bool

    var body: some View {
        ZStack {
            AutoScrollingTextEditor(text: $text, isLocked: isLocked, isEditing: $isEditing)
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .accessibilityIdentifier("record.transcript")

            if text.isEmpty {
                // The hint is symmetric to the timer and waveform above it —
                // every element on the screen is centered. A lone left-aligned
                // placeholder reads as orphaned, especially in dark mode.
                Text(placeholder)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Palette.textTertiary)
                    .allowsHitTesting(false)
            }
        }
    }
}

#if canImport(UIKit)
private struct AutoScrollingTextEditor: UIViewRepresentable {
    @Binding var text: String
    var isLocked: Bool = false
    @Binding var isEditing: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 17, weight: .regular)
        textView.textColor = .label
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.accessibilityIdentifier = "record.transcript"
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.isEditable = !isLocked
        let oldText = textView.text ?? ""
        guard oldText != text else { return }
        textView.text = text
        // Streaming append (new text extends the old) scrolls to the bottom
        // so the user follows the growing transcript. A whole-document
        // replacement (e.g. custom action result) scrolls to the top so the
        // user starts reading from the beginning.
        if !oldText.isEmpty, text.hasPrefix(oldText) {
            scrollToBottom(textView)
        } else {
            scrollToTop(textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isEditing: $isEditing)
    }

    private func scrollToBottom(_ textView: UITextView) {
        DispatchQueue.main.async {
            guard !textView.text.isEmpty else { return }
            let length = (textView.text as NSString).length
            let endRange = NSRange(location: max(length - 1, 0), length: 1)
            textView.scrollRangeToVisible(endRange)
        }
    }

    private func scrollToTop(_ textView: UITextView) {
        DispatchQueue.main.async {
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>
        private var isEditing: Binding<Bool>

        init(text: Binding<String>, isEditing: Binding<Bool>) {
            self.text = text
            self.isEditing = isEditing
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing.wrappedValue = false
        }
    }
}
#else
private struct AutoScrollingTextEditor: View {
    @Binding var text: String
    @Binding var isEditing: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(DesignTokens.Typography.body)
            .foregroundStyle(DesignTokens.Palette.textPrimary)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
    }
}
#endif

#Preview {
    NavigationStack {
        RecordView()
            .environmentObject(AppState())
    }
}
