import AppKit

private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor
final class SuggestionPanel: NSPanel {
    var onPromptSelection: ((UUID) -> Void)?

    private let headingLabel = NSTextField(labelWithString: "ppp")
    private let promptPopUp = PromptPopUpButton()
    private let feedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let suggestionLabel = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: L10n.string("Reviewing selection…"))
    private let progressRow = NSStackView()
    private let copyButton = ActionControl(
        title: L10n.string("Copy result"),
        systemSymbol: "doc.on.doc"
    )
    private let bodyScrollView = NSScrollView()
    private let bodyStack = FlippedStackView()
    private let stack = NSStackView()
    private var bodyHeightConstraint: NSLayoutConstraint!
    private var currentSuggestion = ""

    /// Set for the duration of a review so every frame of a growing response is
    /// placed on the same side of the caret.
    private var reservedPlacementHeight: CGFloat?

    static let placementFootprint = NSSize(width: 380, height: 460)

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = false

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        contentView = effect

        headingLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headingLabel.textColor = .secondaryLabelColor

        promptPopUp.target = self
        promptPopUp.action = #selector(promptSelectionChanged)
        promptPopUp.isHidden = true

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        progressLabel.font = .systemFont(ofSize: 12)
        progressLabel.textColor = .secondaryLabelColor

        progressRow.orientation = .horizontal
        progressRow.alignment = .centerY
        progressRow.spacing = 7
        progressRow.addArrangedSubview(progressIndicator)
        progressRow.addArrangedSubview(progressLabel)
        progressRow.isHidden = true

        feedbackLabel.font = .systemFont(ofSize: 13)
        feedbackLabel.textColor = .labelColor
        feedbackLabel.allowsEditingTextAttributes = true
        feedbackLabel.maximumNumberOfLines = 0
        feedbackLabel.lineBreakMode = .byWordWrapping

        suggestionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        suggestionLabel.textColor = .labelColor
        suggestionLabel.maximumNumberOfLines = 0
        suggestionLabel.lineBreakMode = .byWordWrapping

        copyButton.onClick = { [weak self] in
            self?.copySuggestion()
        }
        copyButton.toolTip = L10n.string("Copy the result")

        let headerRow = NSStackView(views: [headingLabel, promptPopUp])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 6

        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 7
        bodyStack.addArrangedSubview(progressRow)
        bodyStack.addArrangedSubview(feedbackLabel)
        bodyStack.addArrangedSubview(suggestionLabel)
        bodyStack.addArrangedSubview(copyButton)
        bodyStack.frame = NSRect(x: 0, y: 0, width: 352, height: 18)

        bodyScrollView.borderType = .noBorder
        bodyScrollView.drawsBackground = false
        bodyScrollView.hasVerticalScroller = true
        bodyScrollView.hasHorizontalScroller = false
        bodyScrollView.autohidesScrollers = true
        bodyScrollView.scrollerStyle = .overlay
        bodyScrollView.documentView = bodyStack
        bodyScrollView.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(headerRow)
        stack.addArrangedSubview(bodyScrollView)
        effect.addSubview(stack)

        bodyHeightConstraint = bodyScrollView.heightAnchor.constraint(equalToConstant: 18)
        bodyHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -12),
            headerRow.widthAnchor.constraint(equalToConstant: 352),
            promptPopUp.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            bodyScrollView.widthAnchor.constraint(equalToConstant: 352),
            progressIndicator.widthAnchor.constraint(equalToConstant: 14),
            progressIndicator.heightAnchor.constraint(equalToConstant: 14),
            feedbackLabel.widthAnchor.constraint(equalToConstant: 352),
            suggestionLabel.widthAnchor.constraint(equalToConstant: 352)
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setPromptProfiles(_ profiles: [PromptProfile], selectedPromptID: UUID) {
        promptPopUp.setProfiles(profiles, selectedPromptID: selectedPromptID)
    }

    /// Draws a response that is still arriving.
    ///
    /// The scroll position is left alone so text streaming in below the fold
    /// cannot yank the reader back to the top mid-sentence, and the rewrite stays
    /// uncopyable until it is known to be complete.
    func showStreaming(
        _ partial: PartialReview,
        near accessibilityRect: CGRect?,
        heading: String = "ppp"
    ) {
        showHeader(heading, usesPromptPicker: true)
        let feedback = partial.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestion = partial.suggestion.trimmingCharacters(in: .whitespacesAndNewlines)

        if !feedback.isEmpty || !suggestion.isEmpty {
            progressIndicator.stopAnimation(nil)
            progressRow.isHidden = true
        }

        feedbackLabel.attributedStringValue = FeedbackMarkdown.render(feedback)
        feedbackLabel.isHidden = feedback.isEmpty
        suggestionLabel.stringValue = suggestion
        suggestionLabel.isHidden = suggestion.isEmpty
        copyButton.isHidden = true
        currentSuggestion = ""
        present(near: accessibilityRect, resetScroll: false)
    }

    /// - Parameter preservingScroll: Keeps the reader where they are, for the
    ///   final frame of a response they have already begun scrolling through.
    func show(
        result: ReviewResult,
        near accessibilityRect: CGRect?,
        heading: String = "ppp",
        preservingScroll: Bool = false,
        usesPromptPicker: Bool = true
    ) {
        progressIndicator.stopAnimation(nil)
        progressRow.isHidden = true
        showHeader(heading, usesPromptPicker: usesPromptPicker)
        let feedback = result.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        feedbackLabel.attributedStringValue = FeedbackMarkdown.render(feedback)
        feedbackLabel.isHidden = feedback.isEmpty
        currentSuggestion = result.suggestion
        suggestionLabel.stringValue = result.suggestion
        suggestionLabel.isHidden = !result.hasSuggestion
        copyButton.setTitle(L10n.string("Copy result"))
        copyButton.isHidden = !result.hasSuggestion
        present(near: accessibilityRect, resetScroll: !preservingScroll)
    }

    func showLoading(near accessibilityRect: CGRect?, heading: String = "ppp") {
        showHeader(heading, usesPromptPicker: true)
        feedbackLabel.isHidden = true
        suggestionLabel.isHidden = true
        copyButton.isHidden = true
        currentSuggestion = ""
        progressRow.isHidden = false
        progressIndicator.startAnimation(nil)
        reservedPlacementHeight = Self.placementFootprint.height
        present(near: accessibilityRect)
    }

    override func orderOut(_ sender: Any?) {
        reservedPlacementHeight = nil
        super.orderOut(sender)
    }

    private func showHeader(_ heading: String, usesPromptPicker: Bool) {
        headingLabel.stringValue = heading
        headingLabel.isHidden = usesPromptPicker
        promptPopUp.isHidden = !usesPromptPicker
    }

    @objc private func promptSelectionChanged() {
        guard let id = promptPopUp.selectedPromptID else { return }
        onPromptSelection?(id)
    }

    private func present(near accessibilityRect: CGRect?, resetScroll: Bool = true) {
        // The scroll view draws no background, so AppKit cannot infer contrast
        // from the vibrant material behind it and falls back to the knob meant
        // for light content — a near-black bar over a dark panel. Match the knob
        // to the appearance the labels are already drawn for.
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        bodyScrollView.verticalScroller?.knobStyle = isDark ? .light : .dark

        // Preserve the origin before resizing, and never collapse the document
        // view just to measure it: doing so clamps an in-progress scroll to the top.
        let preservedScrollOrigin = resetScroll ? nil : bodyScrollView.contentView.bounds.origin
        bodyStack.layoutSubtreeIfNeeded()
        let bodyHeight = max(bodyStack.fittingSize.height, 18)
        bodyStack.setFrameSize(NSSize(width: 352, height: bodyHeight))
        bodyHeightConstraint.constant = min(bodyHeight, 400)
        bodyScrollView.contentView.scroll(to: preservedScrollOrigin ?? .zero)
        bodyScrollView.reflectScrolledClipView(bodyScrollView.contentView)

        contentView?.layoutSubtreeIfNeeded()
        let fittingHeight = stack.fittingSize.height + 24
        let panelSize = NSSize(
            width: Self.placementFootprint.width,
            height: min(max(fittingHeight, 72), Self.placementFootprint.height)
        )
        setContentSize(panelSize)
        setFrameOrigin(
            PanelPositioning.origin(
                for: panelSize,
                near: accessibilityRect,
                gap: 8,
                reservedHeight: reservedPlacementHeight
            )
        )
        orderFrontRegardless()
    }

    private func copySuggestion() {
        guard !currentSuggestion.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentSuggestion, forType: .string)
        copyButton.setTitle(L10n.string("Copied"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.copyButton.setTitle(L10n.string("Copy result"))
        }
    }

}
