import AppKit

final class ActionControl: NSView {
    var onClick: (() -> Void)?

    private let icon = NSImageView()
    private let label: NSTextField

    init(title: String, systemSymbol: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        icon.image = NSImage(systemSymbolName: systemSymbol, accessibilityDescription: nil)
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .labelColor

        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            icon.widthAnchor.constraint(equalToConstant: 13),
            icon.heightAnchor.constraint(equalToConstant: 13)
        ])
        setAccessibilityLabel(title)
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        alphaValue = 0.65
        onClick?()
        DispatchQueue.main.async { [weak self] in self?.alphaValue = 1 }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func setTitle(_ value: String) {
        label.stringValue = value
        setAccessibilityLabel(value)
    }

    private func updateColors() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.3).cgColor
    }
}
