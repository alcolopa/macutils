import AppKit

/// Scrolls horizontally only; predominantly vertical scrolls pass through to the enclosing scroll view.
private final class HorizontalOnlyScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

@MainActor
public final class WeatherPopoverViewController: NSViewController {
    public var onRefresh: (() -> Void)?
    
    private let heroCard = MetricCardView(title: "Current Conditions")
    private let detailsCard = MetricCardView(title: "Atmospheric Details")
    private let forecastCard = MetricCardView(title: "Upcoming Forecast")
    
    // Hero Elements
    private let heroConditionIcon = NSImageView()
    private let heroTempLabel = NSTextField(labelWithString: "--°")
    private let heroCityLabel = NSTextField(labelWithString: "Weather")
    private let heroDescriptionLabel = NSTextField(labelWithString: "Checking conditions...")
    private let heroHiLoLabel = NSTextField(labelWithString: "H: --°  L: --°")
    
    // Detail rows
    private let feelsLikeRow = MetricRowView(label: "Feels Like:", color: .systemOrange)
    private let humidityRow = MetricRowView(label: "Humidity:", color: .systemTeal)
    private let windRow = MetricRowView(label: "Wind Speed:", color: .systemCyan)
    private let pressureRow = MetricRowView(label: "Barometer:", color: .systemIndigo)
    private let sunRow = MetricRowView(label: "Sunrise / Sunset:", color: .systemYellow)
    private let cloudsRow = MetricRowView(label: "Cloud Cover:", color: .systemGray)
    
    // Forecast Scroll Container
    private let forecastStack = NSStackView()
    
    // Footer Elements
    private let statusLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let settingsButton = NSButton(title: "Configure Key...", target: nil, action: nil)
    
    // Empty / Setup card
    private let unconfiguredCard = MetricCardView(title: "Setup Weather")
    
    private let scrollView = NSScrollView()
    private let container = FlippedStackView()
    
    public override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 360, height: 530))
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        self.view = root
        
        setupLayout()
    }
    
    public override func viewWillAppear() {
        super.viewWillAppear()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    
    private func setupLayout() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        container.orientation = .vertical
        container.alignment = .width
        container.spacing = 12
        container.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = container
        scrollView.contentView = clipView
        
        // 1. Hero Card
        setupHeroCard()
        container.addArrangedSubview(heroCard)
        
        // 2. Unconfigured / Setup Warning Card
        setupUnconfiguredCard()
        container.addArrangedSubview(unconfiguredCard)
        
        // 3. Details Card
        let detailsStack = NSStackView(views: [feelsLikeRow, humidityRow, windRow, pressureRow, cloudsRow, sunRow])
        detailsStack.orientation = .vertical
        detailsStack.spacing = 5
        detailsCard.addContentSubview(detailsStack)
        container.addArrangedSubview(detailsCard)
        
        // 4. Forecast Card
        setupForecastCard()
        container.addArrangedSubview(forecastCard)
        
        // 5. Footer actions
        let footerRow = NSStackView()
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 8
        footerRow.translatesAutoresizingMaskIntoConstraints = false
        
        statusLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footerRow.addArrangedSubview(statusLabel)
        
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshButton.target = self
        refreshButton.action = #selector(onRefreshClicked)
        footerRow.addArrangedSubview(refreshButton)
        
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .small
        settingsButton.target = self
        settingsButton.action = #selector(onOpenSettings)
        footerRow.addArrangedSubview(settingsButton)
        
        container.addArrangedSubview(footerRow)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            heroCard.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28),
            unconfiguredCard.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28),
            detailsCard.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28),
            forecastCard.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28),
            footerRow.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28)
        ])
    }
    
    private func setupHeroCard() {
        let heroRow = NSStackView()
        heroRow.orientation = .horizontal
        heroRow.alignment = .centerY
        heroRow.spacing = 14
        heroRow.translatesAutoresizingMaskIntoConstraints = false
        
        heroConditionIcon.imageScaling = .scaleProportionallyUpOrDown
        heroConditionIcon.translatesAutoresizingMaskIntoConstraints = false
        heroConditionIcon.widthAnchor.constraint(equalToConstant: 44).isActive = true
        heroConditionIcon.heightAnchor.constraint(equalToConstant: 44).isActive = true
        heroConditionIcon.contentTintColor = .systemOrange
        heroRow.addArrangedSubview(heroConditionIcon)
        
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        
        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 8
        
        heroTempLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .bold)
        titleRow.addArrangedSubview(heroTempLabel)
        
        heroCityLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        heroCityLabel.textColor = NSColor.secondaryLabelColor
        titleRow.addArrangedSubview(heroCityLabel)
        
        textStack.addArrangedSubview(titleRow)
        
        heroDescriptionLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        heroDescriptionLabel.textColor = NSColor.labelColor
        textStack.addArrangedSubview(heroDescriptionLabel)
        
        heroHiLoLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        heroHiLoLabel.textColor = NSColor.secondaryLabelColor
        textStack.addArrangedSubview(heroHiLoLabel)
        
        heroRow.addArrangedSubview(textStack)
        
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        heroRow.addArrangedSubview(spacer)
        
        heroCard.addContentSubview(heroRow)
    }
    
    private func setupUnconfiguredCard() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        let msg = NSTextField(labelWithString: "An OpenWeatherMap API Key is needed to display live weather. Free keys take 1 minute to get from openweathermap.org.")
        msg.font = NSFont.systemFont(ofSize: 11)
        msg.textColor = NSColor.secondaryLabelColor
        msg.lineBreakMode = .byWordWrapping
        msg.preferredMaxLayoutWidth = 310
        stack.addArrangedSubview(msg)
        
        let actionBtn = NSButton(title: "Add API Key in Settings...", target: self, action: #selector(onOpenSettings))
        actionBtn.bezelStyle = .rounded
        actionBtn.controlSize = .small
        stack.addArrangedSubview(actionBtn)
        
        unconfiguredCard.addContentSubview(stack)
    }
    
    private func setupForecastCard() {
        let scroll = HorizontalOnlyScrollView()
        scroll.drawsBackground = false
        scroll.verticalScrollElasticity = .none
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .allowed
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 104).isActive = true
        
        forecastStack.orientation = .horizontal
        forecastStack.spacing = 10
        forecastStack.alignment = .centerY
        forecastStack.translatesAutoresizingMaskIntoConstraints = false
        
        let clip = NSClipView()
        clip.drawsBackground = false
        clip.documentView = forecastStack
        scroll.contentView = clip

        NSLayoutConstraint.activate([
            forecastStack.topAnchor.constraint(equalTo: clip.topAnchor),
            forecastStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            forecastStack.bottomAnchor.constraint(equalTo: clip.bottomAnchor)
        ])

        forecastCard.addContentSubview(scroll)
    }
    
    public func update(stats: WeatherStats) {
        let hasKey = !AppPreferences.shared.weatherApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        unconfiguredCard.isHidden = hasKey
        
        let isFahrenheit = AppPreferences.shared.temperatureUnit == .fahrenheit
        func fmtTemp(_ c: Double) -> String {
            if isFahrenheit {
                return "\(Int(round(c * 9.0 / 5.0 + 32.0)))°F"
            } else {
                return "\(Int(round(c)))°C"
            }
        }
        
        let multiConfig = NSImage.SymbolConfiguration.preferringMulticolor()
        
        if let current = stats.current {
            heroTempLabel.stringValue = fmtTemp(current.temperature)
            heroCityLabel.stringValue = current.country.isEmpty ? current.cityName : "\(current.cityName), \(current.country)"
            heroDescriptionLabel.stringValue = current.condition.description
            heroHiLoLabel.stringValue = "H: \(fmtTemp(current.tempMax))   L: \(fmtTemp(current.tempMin))"
            
            let symbol = WeatherIconMapper.sfSymbol(for: current.condition.icon, conditionId: current.condition.id)
            if let baseImg = NSImage(systemSymbolName: symbol, accessibilityDescription: current.condition.description) {
                heroConditionIcon.image = baseImg.withSymbolConfiguration(multiConfig) ?? baseImg
            }
            heroConditionIcon.contentTintColor = nil
            
            heroCard.setBadge(current.condition.main)
            
            feelsLikeRow.setValue(fmtTemp(current.feelsLike))
            humidityRow.setValue("\(current.humidity)%")
            windRow.setValue(String(format: "%.1f m/s", current.windSpeed))
            pressureRow.setValue("\(current.pressure) hPa")
            cloudsRow.setValue("\(current.cloudiness)%")
            
            let timeFmt = DateFormatter()
            timeFmt.timeStyle = .short
            let riseStr = current.sunrise.map { timeFmt.string(from: $0) } ?? "--"
            let setStr = current.sunset.map { timeFmt.string(from: $0) } ?? "--"
            sunRow.setValue("\(riseStr) / \(setStr)")
        } else {
            heroTempLabel.stringValue = "--°"
            heroCityLabel.stringValue = "OpenWeatherMap"
            heroDescriptionLabel.stringValue = stats.errorMessage ?? "No weather data"
            heroHiLoLabel.stringValue = "H: --°   L: --°"
            heroConditionIcon.image = NSImage(systemSymbolName: "cloud.sun.fill", accessibilityDescription: nil)
            heroConditionIcon.contentTintColor = .secondaryLabelColor
        }
        
        // Update forecast strip
        forecastStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if stats.forecast.isEmpty {
            let label = NSTextField(labelWithString: "No forecast data available")
            label.font = NSFont.systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            forecastStack.addArrangedSubview(label)
        } else {
            let hourFmt = DateFormatter()
            hourFmt.dateFormat = AppPreferences.shared.weatherForecastMode == .threeHourly ? "ha" : "EEE"
            
            for item in stats.forecast {
                let cell = makeForecastCell(item: item, hourFmt: hourFmt, tempStr: fmtTemp(item.tempMax), lowStr: fmtTemp(item.tempMin))
                forecastStack.addArrangedSubview(cell)
            }
        }
        
        if let updated = stats.lastUpdated {
            let df = DateFormatter()
            df.timeStyle = .short
            statusLabel.stringValue = "Updated: \(df.string(from: updated))"
        } else if let err = stats.errorMessage {
            statusLabel.stringValue = err
        } else {
            statusLabel.stringValue = ""
        }
    }
    
    private func makeForecastCell(item: WeatherForecastItem, hourFmt: DateFormatter, tempStr: String, lowStr: String) -> NSView {
        let card = NSBox()
        card.boxType = .custom
        card.cornerRadius = 6
        card.borderColor = NSColor.separatorColor.withAlphaComponent(0.2)
        card.borderWidth = 1.0
        card.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35)
        card.translatesAutoresizingMaskIntoConstraints = false
        
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView = stack
        
        let timeLbl = NSTextField(labelWithString: hourFmt.string(from: item.date))
        timeLbl.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        timeLbl.textColor = NSColor.secondaryLabelColor
        stack.addArrangedSubview(timeLbl)
        
        let symbol = WeatherIconMapper.sfSymbol(for: item.condition.icon, conditionId: item.condition.id)
        let iconView = NSImageView()
        let multiConfig = NSImage.SymbolConfiguration.preferringMulticolor()
        if let baseImg = NSImage(systemSymbolName: symbol, accessibilityDescription: item.condition.description) {
            iconView.image = baseImg.withSymbolConfiguration(multiConfig) ?? baseImg
        }
        iconView.contentTintColor = nil
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 22).isActive = true
        stack.addArrangedSubview(iconView)
        
        let tempLbl = NSTextField(labelWithString: tempStr)
        tempLbl.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        stack.addArrangedSubview(tempLbl)
        
        let lowLbl = NSTextField(labelWithString: lowStr)
        lowLbl.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        lowLbl.textColor = .secondaryLabelColor
        stack.addArrangedSubview(lowLbl)
        
        // Always present so every card has the same height; blank when no rain expected
        let showRain = item.precipitationChance > 0.15
        let rainLbl = NSTextField(labelWithString: showRain ? "\(Int(round(item.precipitationChance * 100)))%" : " ")
        rainLbl.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        rainLbl.textColor = .systemCyan
        stack.addArrangedSubview(rainLbl)
        
        card.widthAnchor.constraint(equalToConstant: 62).isActive = true
        card.heightAnchor.constraint(equalToConstant: 100).isActive = true
        return card
    }
    
    @objc private func onRefreshClicked() {
        onRefresh?()
    }
    
    @objc private func onOpenSettings() {
        view.window?.performClose(nil)
        PreferencesWindowController.shared.showPreferences(selecting: .weather)
    }
}
