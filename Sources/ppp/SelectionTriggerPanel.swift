import AppKit

@MainActor
final class SelectionTriggerPanel: NSPanel {
    var onReview: (() -> Void)?
    var onPromptSelection: ((UUID) -> Void)?

    private let promptPopUp = PromptPopUpButton()
    private let runControl = ActionControl(
        title: L10n.string("Run"),
        systemSymbol: "text.bubble"
    )

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 88, height: 34),
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

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 9
        effect.layer?.masksToBounds = true
        contentView = effect

        promptPopUp.target = self
        promptPopUp.action = #selector(promptSelectionChanged)

        runControl.onClick = { [weak self] in
            self?.onReview?()
        }

        let stack = NSStackView(views: [promptPopUp, runControl])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 7),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -7),
            promptPopUp.widthAnchor.constraint(lessThanOrEqualToConstant: 180)
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(
        near accessibilityRect: CGRect?,
        profiles: [PromptProfile],
        selectedPromptID: UUID,
        reservedPlacementHeight: CGFloat? = nil
    ) {
        promptPopUp.setProfiles(profiles, selectedPromptID: selectedPromptID)
        let promptName = promptPopUp.titleOfSelectedItem ?? ""
        runControl.toolTip = L10n.format("Run %@", promptName)
        let contentWidth = max(
            promptPopUp.intrinsicContentSize.width,
            runControl.fittingSize.width
        ) + 16
        let width = min(max(contentWidth, 100), 196)
        let panelSize = NSSize(width: width, height: 60)
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

    @objc private func promptSelectionChanged() {
        guard let id = promptPopUp.selectedPromptID else { return }
        runControl.toolTip = L10n.format("Run %@", promptPopUp.titleOfSelectedItem ?? "")
        onPromptSelection?(id)
    }

}
