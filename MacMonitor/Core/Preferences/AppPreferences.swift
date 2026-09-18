import AppKit

public enum MetricType: String, Sendable, CaseIterable, Codable {
    case cpu          = "cpu"
    case memory       = "memory"
    case disk         = "disk"
    case network      = "network"
    case battery      = "battery"
    case temperatures = "temperatures"
    case displays     = "displays"
    case weather      = "weather"
    
    public var displayName: String {
        switch self {
        case .cpu:          return "CPU & GPU Activity"
        case .memory:       return "Memory & Swap"
        case .disk:         return "Disk Storage"
        case .network:      return "Network Activity"
        case .battery:      return "Battery & Power"
        case .temperatures: return "Temperatures & Sensors"
        case .displays:     return "Displays & Monitors"
        case .weather:      return "Weather & Forecast"
        }
    }
    
    public var iconSymbolName: String {
        switch self {
        case .cpu:          return "cpu"
        case .memory:       return "memorychip"
        case .disk:         return "internaldrive"
        case .network:      return "network"
        case .battery:      return "battery.100"
        case .temperatures: return "thermometer.medium"
        case .displays:     return "display"
        case .weather:      return "cloud.sun.fill"
        }
    }
}

public enum TemperatureUnit: String, Sendable, CaseIterable {
    case celsius    = "Celsius (°C)"
    case fahrenheit = "Fahrenheit (°F)"
}

public enum MetricDisplayStyle: String, Sendable, CaseIterable, Codable {
    case standard         = "standard"         // Text + Graph/Meter/Icon
    case barOnly          = "barOnly"          // Bars / meter only, no text
    case textOnly         = "textOnly"         // Numeric text only
    case circularGauge    = "circularGauge"    // Single-color circular ring / gauge
    case multicolorCircle = "multicolorCircle" // Multi-colored ring / donut (e.g. breakdown for memory)
    
    public var displayName: String {
        switch self {
        case .standard:         return "Standard (Text & Graphic)"
        case .barOnly:          return "Bar Only"
        case .textOnly:         return "Text Only"
        case .circularGauge:    return "Circular Gauge"
        case .multicolorCircle: return "Multicoloured Circle"
        }
    }
}

public enum MemoryDisplayMode: String, Sendable, CaseIterable {
    case percentage = "percentage" // e.g. "74%"
    case usedAmount = "usedAmount" // e.g. "12.4G"
    case pressure   = "pressure"   // e.g. "NORM" / "WARN"
}

public enum ColorTheme: String, Sendable, CaseIterable {
    case standard   = "Standard macOS"
    case cyberpunk  = "Cyberpunk Neon"
    case emerald    = "Emerald Matrix"
    case sunset     = "Sunset Orange"
    case monochrome = "Monochrome Slate"
    
    public var primaryColor: NSColor {
        switch self {
        case .standard:   return .systemBlue
        case .cyberpunk:  return NSColor(red: 1.0, green: 0.1, blue: 0.6, alpha: 1.0)
        case .emerald:    return NSColor(red: 0.0, green: 0.9, blue: 0.4, alpha: 1.0)
        case .sunset:     return NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0)
        case .monochrome: return NSColor(white: 0.9, alpha: 1.0)
        }
    }
    
    public var secondaryColor: NSColor {
        switch self {
        case .standard:   return .systemTeal
        case .cyberpunk:  return NSColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1.0)
        case .emerald:    return NSColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1.0)
        case .sunset:     return NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0)
        case .monochrome: return NSColor(white: 0.6, alpha: 1.0)
        }
    }
}

public enum BarIconPosition: String, Sendable, CaseIterable {
    case leading  = "Left of value"
    case trailing = "Right of value"
}

public enum BarIconSize: String, Sendable, CaseIterable {
    case small   = "Small"
    case medium  = "Medium"
    case large   = "Large"
    
    public var points: CGFloat {
        switch self {
        case .small:  return 10
        case .medium: return 12
        case .large:  return 14
        }
    }
}

public enum BarIconTint: String, Sendable, CaseIterable {
    case automatic = "Match menu bar"
    case theme     = "Theme colour"
}

/// Per-widget menu bar appearance options (icon, label, padding).
public struct BarOptions: Sendable, Equatable {
    public var showIcon: Bool
    public var iconPosition: BarIconPosition
    public var iconSize: BarIconSize
    public var iconTint: BarIconTint
    public var showLabel: Bool
    public var padding: Double
    
    public static func defaults(for metric: MetricType) -> BarOptions {
        BarOptions(
            showIcon: metric != .weather,   // weather already draws its own condition icon
            iconPosition: .leading,
            iconSize: .medium,
            iconTint: .automatic,
            showLabel: false,
            padding: 0
        )
    }
}

public final class AppPreferences: @unchecked Sendable {
    public static let shared = AppPreferences()
    private let defaults = UserDefaults.standard
    
    private let keyShowCPU = "showCPU"
    private let keyShowMemory = "showMemory"
    private let keyShowDisk = "showDisk"
    private let keyShowNetwork = "showNetwork"
    private let keyShowBattery = "showBattery"
    private let keyShowTemperatures = "showTemperatures"
    private let keyShowDisplays = "showDisplays"
    private let keyShowWeather = "showWeather"
    private let keyWeatherApiKey = "weatherApiKey"
    private let keyWeatherCity = "weatherCity"
    private let keyWeatherUpdateInterval = "weatherUpdateInterval"
    private let keyMemoryDisplayMode = "memoryDisplayMode"
    private let keyColorTheme = "colorTheme"
    private let keyPassiveInterval = "passiveInterval"
    private let keyMetricOrder = "metricOrder"
    private let keyTemperatureUnit = "temperatureUnit"
    
    public var onPreferencesChanged: (@Sendable @MainActor () -> Void)?
    public var onOrderChanged: (@Sendable @MainActor () -> Void)?
    
    private init() {
        let defaultOrder = MetricType.allCases.map { $0.rawValue }
        defaults.register(defaults: [
            keyShowCPU: true,
            keyShowMemory: true,
            keyShowDisk: true,
            keyShowNetwork: true,
            keyShowBattery: true,
            keyShowTemperatures: true,
            keyShowDisplays: true,
            keyShowWeather: true,
            keyWeatherApiKey: "",
            keyWeatherCity: "auto",
            keyWeatherUpdateInterval: 1800, // 30 mins
            keyMemoryDisplayMode: MemoryDisplayMode.percentage.rawValue,
            keyColorTheme: ColorTheme.standard.rawValue,
            keyPassiveInterval: 1.5,
            keyMetricOrder: defaultOrder,
            keyTemperatureUnit: TemperatureUnit.celsius.rawValue
        ])
    }
    
    public var showCPU: Bool {
        get { defaults.bool(forKey: keyShowCPU) }
        set { defaults.set(newValue, forKey: keyShowCPU); notifyChange() }
    }
    
    public var showMemory: Bool {
        get { defaults.bool(forKey: keyShowMemory) }
        set { defaults.set(newValue, forKey: keyShowMemory); notifyChange() }
    }
    
    public var showDisk: Bool {
        get { defaults.bool(forKey: keyShowDisk) }
        set { defaults.set(newValue, forKey: keyShowDisk); notifyChange() }
    }
    
    public var showNetwork: Bool {
        get { defaults.bool(forKey: keyShowNetwork) }
        set { defaults.set(newValue, forKey: keyShowNetwork); notifyChange() }
    }
    
    public var showBattery: Bool {
        get { defaults.bool(forKey: keyShowBattery) }
        set { defaults.set(newValue, forKey: keyShowBattery); notifyChange() }
    }
    
    public var showTemperatures: Bool {
        get { defaults.bool(forKey: keyShowTemperatures) }
        set { defaults.set(newValue, forKey: keyShowTemperatures); notifyChange() }
    }
    
    public var showDisplays: Bool {
        get { defaults.bool(forKey: keyShowDisplays) }
        set { defaults.set(newValue, forKey: keyShowDisplays); notifyChange() }
    }
    
    public var showWeather: Bool {
        get { defaults.bool(forKey: keyShowWeather) }
        set { defaults.set(newValue, forKey: keyShowWeather); notifyChange() }
    }
    
    public var weatherApiKey: String {
        get { defaults.string(forKey: keyWeatherApiKey) ?? "" }
        set { defaults.set(newValue, forKey: keyWeatherApiKey); notifyChange() }
    }
    
    public var weatherCity: String {
        get { defaults.string(forKey: keyWeatherCity) ?? "auto" }
        set { defaults.set(newValue, forKey: keyWeatherCity); notifyChange() }
    }
    
    public var weatherUpdateInterval: TimeInterval {
        get {
            let val = defaults.double(forKey: keyWeatherUpdateInterval)
            return val >= 300 ? val : 1800 // Minimum 5 mins, default 30 mins
        }
        set { defaults.set(newValue, forKey: keyWeatherUpdateInterval); notifyChange() }
    }
    
    public func isMetricVisible(_ metric: MetricType) -> Bool {
        switch metric {
        case .cpu: return showCPU
        case .memory: return showMemory
        case .disk: return showDisk
        case .network: return showNetwork
        case .battery: return showBattery
        case .temperatures: return showTemperatures
        case .displays: return showDisplays
        case .weather: return showWeather
        }
    }
    
    public func setMetricVisible(_ metric: MetricType, visible: Bool) {
        switch metric {
        case .cpu: showCPU = visible
        case .memory: showMemory = visible
        case .disk: showDisk = visible
        case .network: showNetwork = visible
        case .battery: showBattery = visible
        case .temperatures: showTemperatures = visible
        case .displays: showDisplays = visible
        case .weather: showWeather = visible
        }
    }
    
    public var metricOrder: [MetricType] {
        get {
            guard let rawList = defaults.stringArray(forKey: keyMetricOrder) else {
                return MetricType.allCases
            }
            var parsed = rawList.compactMap { MetricType(rawValue: $0) }
            for type in MetricType.allCases where !parsed.contains(type) {
                parsed.append(type)
            }
            return parsed
        }
        set {
            defaults.set(newValue.map { $0.rawValue }, forKey: keyMetricOrder)
            notifyOrderChange()
        }
    }
    
    public func moveMetric(from sourceIndex: Int, to destinationIndex: Int) {
        var current = metricOrder
        guard sourceIndex >= 0 && sourceIndex < current.count,
              destinationIndex >= 0 && destinationIndex < current.count,
              sourceIndex != destinationIndex else { return }
        let item = current.remove(at: sourceIndex)
        current.insert(item, at: destinationIndex)
        self.metricOrder = current
    }
    
    public var temperatureUnit: TemperatureUnit {
        get {
            let raw = defaults.string(forKey: keyTemperatureUnit) ?? TemperatureUnit.celsius.rawValue
            return TemperatureUnit(rawValue: raw) ?? .celsius
        }
        set {
            defaults.set(newValue.rawValue, forKey: keyTemperatureUnit)
            notifyChange()
        }
    }
    
    public var memoryDisplayMode: MemoryDisplayMode {
        get {
            let raw = defaults.string(forKey: keyMemoryDisplayMode) ?? MemoryDisplayMode.percentage.rawValue
            return MemoryDisplayMode(rawValue: raw) ?? .percentage
        }
        set {
            defaults.set(newValue.rawValue, forKey: keyMemoryDisplayMode)
            notifyChange()
        }
    }
    
    public var colorTheme: ColorTheme {
        get {
            let raw = defaults.string(forKey: keyColorTheme) ?? ColorTheme.standard.rawValue
            return ColorTheme(rawValue: raw) ?? .standard
        }
        set {
            defaults.set(newValue.rawValue, forKey: keyColorTheme)
            notifyChange()
        }
    }
    
    public var passiveInterval: Double {
        get {
            let val = defaults.double(forKey: keyPassiveInterval)
            return val > 0 ? val : 1.5
        }
        set {
            defaults.set(newValue, forKey: keyPassiveInterval)
            notifyChange()
        }
    }
    
    public func displayStyle(for metric: MetricType) -> MetricDisplayStyle {
        let key = "displayStyle_\(metric.rawValue)"
        if let raw = defaults.string(forKey: key), let style = MetricDisplayStyle(rawValue: raw) {
            return style
        }
        return .standard
    }
    
    public func setDisplayStyle(_ style: MetricDisplayStyle, for metric: MetricType) {
        let key = "displayStyle_\(metric.rawValue)"
        defaults.set(style.rawValue, forKey: key)
        notifyChange()
    }
    
    public static func availableStyles(for metric: MetricType) -> [MetricDisplayStyle] {
        switch metric {
        case .cpu:
            return [.standard, .barOnly, .circularGauge, .textOnly]
        case .memory:
            return [.standard, .multicolorCircle, .barOnly, .circularGauge, .textOnly]
        case .disk:
            return [.standard, .barOnly, .circularGauge, .textOnly]
        case .battery:
            return [.standard, .barOnly, .textOnly]
        case .network:
            return [.standard, .textOnly]
        case .temperatures:
            return [.standard, .circularGauge, .textOnly]
        case .displays:
            return [.standard, .textOnly]
        case .weather:
            return [.standard, .textOnly, .barOnly, .circularGauge]
        }
    }
    
    // MARK: - Per-widget bar options
    
    public func barOptions(for metric: MetricType) -> BarOptions {
        let d = BarOptions.defaults(for: metric)
        let k = "bar_\(metric.rawValue)_"
        func bool(_ name: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: k + name) == nil ? fallback : defaults.bool(forKey: k + name)
        }
        return BarOptions(
            showIcon: bool("showIcon", d.showIcon),
            iconPosition: defaults.string(forKey: k + "iconPosition").flatMap(BarIconPosition.init(rawValue:)) ?? d.iconPosition,
            iconSize: defaults.string(forKey: k + "iconSize").flatMap(BarIconSize.init(rawValue:)) ?? d.iconSize,
            iconTint: defaults.string(forKey: k + "iconTint").flatMap(BarIconTint.init(rawValue:)) ?? d.iconTint,
            showLabel: bool("showLabel", d.showLabel),
            padding: defaults.object(forKey: k + "widgetPadding") == nil ? d.padding : defaults.double(forKey: k + "widgetPadding")
        )
    }
    
    public func setBarOptions(_ o: BarOptions, for metric: MetricType) {
        let k = "bar_\(metric.rawValue)_"
        defaults.set(o.showIcon, forKey: k + "showIcon")
        defaults.set(o.iconPosition.rawValue, forKey: k + "iconPosition")
        defaults.set(o.iconSize.rawValue, forKey: k + "iconSize")
        defaults.set(o.iconTint.rawValue, forKey: k + "iconTint")
        defaults.set(o.showLabel, forKey: k + "showLabel")
        defaults.set(o.padding, forKey: k + "widgetPadding")
        notifyChange()
    }
    
    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in
            self?.onPreferencesChanged?()
        }
    }
    
    private func notifyOrderChange() {
        DispatchQueue.main.async { [weak self] in
            self?.onPreferencesChanged?()
            self?.onOrderChanged?()
        }
    }
}
