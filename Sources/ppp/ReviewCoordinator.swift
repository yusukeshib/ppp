import Foundation

@MainActor
final class ReviewCoordinator {
    private enum Presentation {
        case hidden
        case minimized
        case expanded
    }

    private struct RestorableReview {
        let text: String
        let applicationName: String?
        let anchor: CGRect?
        let result: ReviewResult
        let heading: String

        func matches(_ capture: CapturedText) -> Bool {
            text == capture.text && applicationName == capture.applicationName
        }
    }

    private let settings: AppSettings
    private let panel: SuggestionPanel
    private let triggerPanel: SelectionTriggerPanel
    private let client = ReviewClient()

    private var reviewTask: Task<Void, Never>?
    private var revision = 0
    private var lastCaptureSignature: String?
    private var activeCapture: CapturedText?
    private var selectionIsActive = false
    private var presentation = Presentation.hidden
    private var restorableReview: RestorableReview?
    private var lastRequestKey: String?
    private var cache: [String: ReviewResult] = [:]
    private var cacheOrder: [String] = []

    /// Shortest gap between intermediate frames drawn from a streaming response.
    private static let streamFrameInterval: TimeInterval = 0.1

    init(
        settings: AppSettings,
        panel: SuggestionPanel,
        triggerPanel: SelectionTriggerPanel
    ) {
        self.settings = settings
        self.panel = panel
        self.triggerPanel = triggerPanel
        triggerPanel.onReview = { [weak self] in
            self?.reviewPendingSelection()
        }
    }

    func receive(_ capture: CapturedText) {
        let text = reviewableText(from: capture.text)
        guard !text.isEmpty else {
            lastCaptureSignature = nil
            return
        }

        let normalizedCapture = CapturedText(
            text: text,
            caretBounds: capture.caretBounds,
            applicationName: capture.applicationName
        )
        let anchor = capture.caretBounds
            .map { "\(Int($0.minX)),\(Int($0.minY))" } ?? ""
        let signature = [capture.applicationName ?? "", anchor, text].joined(separator: "\u{1F}")

        if !selectionIsActive,
           let restorableReview,
           restorableReview.matches(normalizedCapture) {
            revision &+= 1
            reviewTask?.cancel()
            reviewTask = nil
            lastRequestKey = nil
            lastCaptureSignature = signature
            activeCapture = normalizedCapture
            selectionIsActive = true
            presentation = .expanded
            triggerPanel.orderOut(nil)
            panel.show(
                result: restorableReview.result,
                near: restorableReview.anchor ?? capture.caretBounds,
                heading: restorableReview.heading
            )
            return
        }

        selectionIsActive = true
        guard signature != lastCaptureSignature else { return }
        lastCaptureSignature = signature
        restorableReview = nil

        revision &+= 1
        reviewTask?.cancel()
        reviewTask = nil
        lastRequestKey = nil
        activeCapture = normalizedCapture
        presentation = .minimized
        panel.orderOut(nil)
        triggerPanel.show(
            near: capture.caretBounds,
            promptName: settings.selectedPrompt.name
        )
    }

    func selectionCleared() {
        revision &+= 1
        reviewTask?.cancel()
        reviewTask = nil
        lastCaptureSignature = nil
        activeCapture = nil
        selectionIsActive = false
        lastRequestKey = nil
        presentation = .hidden
        triggerPanel.orderOut(nil)
        panel.orderOut(nil)
    }

    func temporarilyUnavailable() {
        // Focus and application changes briefly make the accessibility selection
        // unreadable. Keep the current presentation until a capture confirms a
        // new selection or selectionCleared() confirms that it is empty.
    }

    func dismiss() {
        revision &+= 1
        reviewTask?.cancel()
        reviewTask = nil
        lastCaptureSignature = nil
        activeCapture = nil
        selectionIsActive = false
        restorableReview = nil
        lastRequestKey = nil
        presentation = .hidden
        triggerPanel.orderOut(nil)
        panel.orderOut(nil)
    }

    func reset() {
        dismiss()
        cache.removeAll()
        cacheOrder.removeAll()
    }

    private func reviewPendingSelection() {
        guard let capture = activeCapture else { return }
        restorableReview = nil
        triggerPanel.orderOut(nil)
        presentation = .expanded

        let currentRevision = revision
        let promptProfile = settings.selectedPrompt
        panel.showLoading(near: capture.caretBounds, heading: promptProfile.name)
        reviewTask = Task { [weak self] in
            await self?.review(
                text: capture.text,
                capture: capture,
                promptProfile: promptProfile,
                revision: currentRevision
            )
        }
    }

    private func review(
        text: String,
        capture: CapturedText,
        promptProfile: PromptProfile,
        revision: Int
    ) async {
        guard revision == self.revision else { return }

        if settings.diagnosticMode {
            let source = capture.applicationName.map {
                L10n.format("Captured from %@", $0)
            } ?? L10n.string("Captured text")
            panel.show(
                result: ReviewResult(feedback: text, suggestion: ""),
                near: capture.caretBounds,
                heading: source
            )
            return
        }

        let provider = settings.provider
        let model = settings.model
        let configuredThinkingLevel = settings.thinkingLevel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let thinkingLevel = provider.supportsThinkingLevel && !configuredThinkingLevel.isEmpty
            ? configuredThinkingLevel
            : nil
        let prompt = promptProfile.prompt
        let heading = promptProfile.name
        let apiKey = KeychainStore.apiKey(for: provider)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            panel.show(
                result: ReviewResult(
                    feedback: L10n.format(
                        "Open ppp Settings and add a %@ API key.",
                        provider.displayName
                    ),
                    suggestion: ""
                ),
                near: capture.caretBounds,
                heading: heading
            )
            return
        }

        let requestKey = [
            provider.rawValue,
            model,
            thinkingLevel ?? "",
            prompt,
            capture.applicationName ?? "",
            text
        ].joined(separator: "\u{1F}")
        guard requestKey != lastRequestKey else { return }
        lastRequestKey = requestKey

        if let cached = cache[requestKey] {
            if cached.shouldDisplay {
                restorableReview = RestorableReview(
                    text: text,
                    applicationName: capture.applicationName,
                    anchor: capture.caretBounds,
                    result: cached,
                    heading: heading
                )
                panel.show(result: cached, near: capture.caretBounds, heading: heading)
            } else {
                minimize()
            }
            return
        }

        do {
            let events = client.reviewStream(
                text: text,
                applicationName: capture.applicationName,
                prompt: prompt,
                provider: provider,
                model: model,
                thinkingLevel: thinkingLevel,
                apiKey: apiKey
            )
            var lastFrame = Date.distantPast

            for try await event in events {
                guard !Task.isCancelled,
                      revision == self.revision,
                      requestKey == lastRequestKey
                else { return }

                switch event {
                case .partial(let partial):
                    // Redrawing per token would thrash layout for no benefit, and
                    // a dropped frame costs nothing because the final event always
                    // renders. Nothing is drawn until the model commits to showing
                    // a review, so an excluded selection never flashes into view.
                    guard partial.show != false, partial.hasContent else { continue }
                    let now = Date()
                    guard now.timeIntervalSince(lastFrame) >= Self.streamFrameInterval else {
                        continue
                    }
                    lastFrame = now
                    panel.showStreaming(
                        partial,
                        near: capture.caretBounds,
                        heading: heading
                    )
                case .final(let result):
                    store(result, for: requestKey)
                    guard result.shouldDisplay else {
                        minimize()
                        return
                    }
                    restorableReview = RestorableReview(
                        text: text,
                        applicationName: capture.applicationName,
                        anchor: capture.caretBounds,
                        result: result,
                        heading: heading
                    )
                    panel.show(
                        result: result,
                        near: capture.caretBounds,
                        heading: heading,
                        preservingScroll: true
                    )
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard revision == self.revision else { return }
            lastRequestKey = nil
            panel.show(
                result: ReviewResult(
                    feedback: error.localizedDescription,
                    suggestion: ""
                ),
                near: capture.caretBounds,
                heading: L10n.string("ppp Error")
            )
        }
    }

    private func minimize() {
        guard let capture = activeCapture else {
            dismiss()
            return
        }

        revision &+= 1
        reviewTask?.cancel()
        reviewTask = nil
        lastRequestKey = nil
        restorableReview = nil
        presentation = .minimized
        panel.orderOut(nil)
        triggerPanel.show(
            near: capture.caretBounds,
            promptName: settings.selectedPrompt.name
        )
    }

    private func reviewableText(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.suffix(4_000))
    }

    private func store(_ result: ReviewResult, for key: String) {
        cache[key] = result
        cacheOrder.append(key)
        while cacheOrder.count > 50 {
            let oldest = cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}
