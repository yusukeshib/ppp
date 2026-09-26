import AppKit

@MainActor
final class SelectionTriggerPanel: NSPanel {
    var onReview: (() -> Void)?
    var onPromptSelection: ((UUID) -> Void)?

    private let promptButton = NSButton()
    private let runButton = NSButton()
    private let promptMenu = NSMenu()
    private var profiles: [PromptProfile] = []
    private var selectedPromptID: UUID?
    private var anchorRect: CGRect?
    private var reservedPlacementHeight: CGFloat?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 150, height: 38),
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

        promptButton.bezelStyle = .rounded
        promptButton.controlSize = .small
        promptButton.cell?.lineBreakMode = .byTruncatingTail
        promptButton.target = self
        promptButton.action = #selector(openPromptMenu)
        promptButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        runButton.title = L10n.string("Run")
        runButton.bezelStyle = .rounded
        runButton.controlSize = .small
        runButton.target = self
        runButton.action = #selector(runSelectedPrompt)

        let stack = NSStackView(views: [promptButton, runButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -5),
            promptButton.widthAnchor.constraint(lessThanOrEqualToConstant: 200)
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
        updateButtons()
        updatePlacement()
        orderFrontRegardless()
    }

    @objc private func runSelectedPrompt() {
        guard selectedPromptID != nil else { return }
        onReview?()
    }

    @objc private func openPromptMenu() {
        guard !promptMenu.items.isEmpty else { return }
        promptMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: promptButton)
    }

    @objc private func selectPrompt(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID,
              profiles.contains(where: { $0.id == id }) else { return }
        selectedPromptID = id
        for menuItem in promptMenu.items {
            menuItem.state = (menuItem.representedObject as? UUID == id) ? .on : .off
        }
        updateButtons()
        updatePlacement()
        onPromptSelection?(id)
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

    private func updateButtons() {
        let name = profiles.first(where: { $0.id == selectedPromptID })?.name ?? ""
        promptButton.title = name
        promptButton.isEnabled = selectedPromptID != nil
        promptButton.setAccessibilityLabel("\(L10n.string("Prompts")): \(name)")
        runButton.isEnabled = selectedPromptID != nil
        let description = L10n.format("Run %@", name)
        runButton.setAccessibilityLabel(description)
        runButton.toolTip = description
    }

    private func updatePlacement() {
        let promptWidth = min(max(promptButton.fittingSize.width, 64), 200)
        let width = promptWidth + runButton.fittingSize.width + 18
        let height = max(promptButton.fittingSize.height, runButton.fittingSize.height) + 10
        let panelSize = NSSize(width: width, height: height)
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
}
