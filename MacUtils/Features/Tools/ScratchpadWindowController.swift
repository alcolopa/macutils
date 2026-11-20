import AppKit

@MainActor
public final class ScratchpadWindowController: NSWindowController, NSTextViewDelegate {
    public static let shared = ScratchpadWindowController()
    
    private let keyScratchpadText = "scratchpadSavedContent"
    private let textView = NSTextView()
    private let counterLabel = NSTextField(labelWithString: "0 words • 0 characters")
    
    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 440, height: 320),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Quick Scratchpad"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 320, height: 200)
        
        super.init(window: panel)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    private func setupUI() {
        guard let window = window else { return }
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .sidebar
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        window.contentView = visualEffect
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.delegate = self
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        let saved = UserDefaults.standard.string(forKey: keyScratchpadText) ?? ""
        textView.string = saved
        scrollView.documentView = textView
        visualEffect.addSubview(scrollView)
        
        // Bottom action bar
        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(bottomBar)
        
        counterLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        counterLabel.textColor = .secondaryLabelColor
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(counterLabel)
        
        let copyBtn = NSButton(title: "Copy All", target: self, action: #selector(copyAll))
        copyBtn.bezelStyle = .inline
        copyBtn.controlSize = .small
        copyBtn.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(copyBtn)
        
        let clearBtn = NSButton(title: "Clear", target: self, action: #selector(clearText))
        clearBtn.bezelStyle = .inline
        clearBtn.controlSize = .small
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(clearBtn)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -6),
            
            bottomBar.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 10),
            bottomBar.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -10),
            bottomBar.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -8),
            bottomBar.heightAnchor.constraint(equalToConstant: 24),
            
            counterLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            counterLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            
            clearBtn.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            clearBtn.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            
            copyBtn.trailingAnchor.constraint(equalTo: clearBtn.leadingAnchor, constant: -6),
            copyBtn.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor)
        ])
        
        updateCounters()
    }
    
    public func showScratchpad() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func textDidChange(_ notification: Notification) {
        UserDefaults.standard.set(textView.string, forKey: keyScratchpadText)
        updateCounters()
    }
    
    private func updateCounters() {
        let text = textView.string
        let chars = text.count
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        counterLabel.stringValue = "\(words) words • \(chars) characters"
    }
    
    @objc private func copyAll() {
        let text = textView.string
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        ClipboardStore.shared.add(text)
        NSSound.beep()
    }
    
    @objc private func clearText() {
        textView.string = ""
        UserDefaults.standard.set("", forKey: keyScratchpadText)
        updateCounters()
    }
}
