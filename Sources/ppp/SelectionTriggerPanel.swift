import AppKit

@MainActor
final class SelectionTriggerPanel: NSPanel {
    var onReview: (() -> Void)?
    var onPromptSelection: ((UUID) -> Void)?

    private let runButton = TriggerSegmentButton()
    private let pickerButton = TriggerSegmentButton()
    private let promptMenu = NSMenu()
    private var profiles: [PromptProfile] = []
    private var selectedPromptID: UUID?
    private var anchorRect: CGRect?
    private var reservedPlacementHeight: CGFloat?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 32),
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
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        contentView = effect

        let symbolSize = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        runButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolSize)
        runButton.imagePosition = .imageOnly
        runButton.target = self
        runButton.action = #selector(runSelectedPrompt)

        pickerButton.alignment = .left
        pickerButton.font = .systemFont(ofSize: 12, weight: .semibold)
        pickerButton.cell?.lineBreakMode = .byTruncatingTail
        pickerButton.target = self
        pickerButton.action = #selector(openPromptMenu)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let segments = NSStackView(views: [runButton, divider, pickerButton])
        segments.orientation = .horizontal
        segments.alignment = .centerY
        segments.spacing = 0
        segments.translatesAutoresizingMaskIntoConstraints = false
        pickerButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        effect.addSubview(segments)

        NSLayoutConstraint.activate([
            segments.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 4),
            segments.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -8),
            segments.topAnchor.constraint(equalTo: effect.topAnchor, constant: 2),
            segments.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -2),
            runButton.widthAnchor.constraint(equalToConstant: 32),
            runButton.heightAnchor.constraint(equalTo: segments.heightAnchor),
            pickerButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 42),
            pickerButton.heightAnchor.constraint(equalTo: segments.heightAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 18)
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
        self.profiles = profiles
        self.selectedPromptID = profiles.first(where: { $0.id == selectedPromptID })?.id
            ?? profiles.first?.id
        anchorRect = accessibilityRect
        self.reservedPlacementHeight = reservedPlacementHeight
        rebuildPromptMenu()
        updateRunButton()
        updatePlacement()
        orderFrontRegardless()
    }

    @objc private func runSelectedPrompt() {
        guard selectedPromptID != nil else { return }
        onReview?()
    }

    @objc private func openPromptMenu() {
        guard !promptMenu.items.isEmpty else { return }
        promptMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: pickerButton)
    }

    @objc private func selectPrompt(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID,
              profiles.contains(where: { $0.id == id }) else { return }
        selectedPromptID = id
        for menuItem in promptMenu.items {
            menuItem.state = (menuItem.representedObject as? UUID == id) ? .on : .off
        }
        updateRunButton()
        updatePlacement()
        onPromptSelection?(id)
    }

    private func updatePlacement() {
        let name = profiles.first(where: { $0.id == selectedPromptID })?.name ?? ""
        let nameWidth = (name as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ]).width
        let width = min(max(ceil(nameWidth) + 58, 96), 240)
        let panelSize = NSSize(width: width, height: 32)
        setContentSize(panelSize)
        setFrameOrigin(
            PanelPositioning.origin(
                for: panelSize,
                near: anchorRect,
                gap: 8,
                reservedHeight: reservedPlacementHeight
            )
        )
    }

    private func rebuildPromptMenu() {
        promptMenu.removeAllItems()
        for profile in profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(selectPrompt(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = profile.id == selectedPromptID ? .on : .off
            promptMenu.addItem(item)
        }
    }

    private func updateRunButton() {
        let name = profiles.first(where: { $0.id == selectedPromptID })?.name ?? ""
        pickerButton.title = name
        runButton.isEnabled = selectedPromptID != nil
        pickerButton.isEnabled = !profiles.isEmpty
        let description = L10n.format("Run %@", name)
        runButton.setAccessibilityLabel(description)
        runButton.toolTip = description
        pickerButton.setAccessibilityLabel("\(L10n.string("Prompts")): \(name)")
        pickerButton.toolTip = L10n.string("Prompts")
    }
}

private final class TriggerSegmentButton: NSButton {
    private var tracking: NSTrackingArea?
    private var isHovered = false {
        didSet { updateHover() }
    }

    init() {
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryPushIn)
        wantsLayer = true
        layer?.cornerRadius = 5
        contentTintColor = .labelColor
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHover()
    }

    private func updateHover() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(isHovered ? 0.12 : 0).cgColor
    }
}
