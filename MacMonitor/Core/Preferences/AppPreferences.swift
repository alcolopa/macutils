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
    case verticalBar      = "verticalBar"      // Single vertical level bar, no text
    // Weather-only elements
    case humidity         = "humidity"         // e.g. "62%"
    case wind             = "wind"             // e.g. "12 km/h"
    case feelsLike        = "feelsLike"        // e.g. "Feels 21°"
    case highLow          = "highLow"          // today's high over low
    case rainChance       = "rainChance"       // e.g. "40%" chance of precipitation
    
    public var displayName: String {
        switch self {
        case .standard:         return "Standard (Text & Graphic)"
        case .barOnly:          return "Bar Only"
        case .textOnly:         return "Text Only"
        case .circularGauge:    return "Circular Gauge"
        case .multicolorCircle: return "Multicoloured Circle"
        case .verticalBar:      return "Vertical Bar"
        case .humidity:         return "Humidity"
        case .wind:             return "Wind"
        case .feelsLike:        return "Feels Like"
        case .highLow:          return "High / Low"
        case .rainChance:       return "Chance of Rain"
        }
    }
}

public enum WeatherForecastMode: String, Sendable, CaseIterable {
    case daily       = "Daily"
    case threeHourly = "Every 3 hours"
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

extension ColorTheme {
    /// A hue clearly different from `primaryColor`, for a second series on the same graph.
    public var contrastColor: NSColor {
        switch self {
        case .standard:   return .systemOrange
        case .cyberpunk:  return NSColor(red: 1.0, green: 0.9, blue: 0.1, alpha: 1.0)
        case .emerald:    return NSColor(red: 0.9, green: 0.9, blue: 0.2, alpha: 1.0)
        case .sunset:     return NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
        case .monochrome: return NSColor(white: 0.45, alpha: 1.0)
        }
    }
}

extension ColorTheme {
    /// `count` clearly distinct colours (one per CPU core), spread around the hue wheel starting at the theme's
    /// own hue, with the theme's saturation/brightness character.
    public func seriesColors(count: Int) -> [NSColor] {
        guard count > 0 else { return [] }
        let base = primaryColor.usingColorSpace(.deviceRGB) ?? primaryColor
        let startHue: CGFloat = self == .monochrome ? 0.58 : base.hueComponent
        let sat: CGFloat
        let bri: CGFloat
        switch self {
        case .standard:   (sat, bri) = (0.75, 0.95)
        case .cyberpunk:  (sat, bri) = (0.90, 1.00)
        case .emerald:    (sat, bri) = (0.70, 0.90)
        case .sunset:     (sat, bri) = (0.85, 1.00)
        case .monochrome: (sat, bri) = (0.40, 0.85)
        }
        return (0..<count).map { i in
            let hue = (startHue + CGFloat(i) / CGFloat(count)).truncatingRemainder(dividingBy: 1.0)
            return NSColor(hue: hue, saturation: sat, brightness: bri, alpha: 1.0)
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

/// A building block of a menu bar widget: the icon, the short label, or one graphic/text element.
/// A widget is an ordered list of these, so several elements (e.g. text + bar + circle) can be combined.
public enum BarPart: Hashable, Sendable {
    case icon
    case label
    case element(MetricDisplayStyle)
    
    public var token: String {
        switch self {
        case .icon: return "icon"
        case .label: return "label"
        case .element(let style): return "el:" + style.rawValue
        }
    }
    
    public init?(token: String) {
        switch token {
        case "icon": self = .icon
        case "label": self = .label
        default:
            guard token.hasPrefix("el:"), let style = MetricDisplayStyle(rawValue: String(token.dropFirst(3))) else { return nil }
            self = .element(style)
        }
    }
    
    public var style: MetricDisplayStyle? {
        if case .element(let s) = self { return s }
        return nil
    }
}

/// Per-widget menu bar appearance: an ordered list of visible parts plus icon/padding tweaks.
public struct BarOptions: Sendable, Equatable {
    public var iconSize: BarIconSize
    public var iconTint: BarIconTint
    public var padding: Double
    /// Visible parts, left to right. Parts not listed are hidden.
    public var order: [BarPart]
    
    public var showIcon: Bool { order.contains(.icon) }
    public var showLabel: Bool { order.contains(.label) }
    public var styles: [MetricDisplayStyle] { order.compactMap(\.style) }
    
    public static func defaults(for metric: MetricType) -> BarOptions {
        BarOptions(
            iconSize: .medium,
            iconTint: .automatic,
            padding: 0,
            // weather already draws its own condition icon; battery draws its own battery
            order: (metric == .weather ? [] : [.icon]) + [.element(AppPreferences.defaultElement(for: metric))]
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
    private let keyWeatherForecastMode = "weatherForecastMode"
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
            return val >= 300 ? val : 900 // Minimum 5 mins, default 15 mins
        }
        set { defaults.set(newValue, forKey: keyWeatherUpdateInterval); notifyChange() }
    }
    
    public var weatherForecastMode: WeatherForecastMode {
        get { defaults.string(forKey: keyWeatherForecastMode).flatMap(WeatherForecastMode.init(rawValue:)) ?? .daily }
        set { defaults.set(newValue.rawValue, forKey: keyWeatherForecastMode); notifyChange() }
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
    
    /// The first (primary) element of the widget; kept for callers that only care about one style.
    public func displayStyle(for metric: MetricType) -> MetricDisplayStyle {
        barOptions(for: metric).styles.first ?? .standard
    }
    
    /// Replaces all of the widget's elements with a single style (icon/label are kept where they are).
    public func setDisplayStyle(_ style: MetricDisplayStyle, for metric: MetricType) {
        var o = barOptions(for: metric)
        var replaced = false
        o.order = o.order.compactMap { part in
            guard part.style != nil else { return part }
            if replaced { return nil }
            replaced = true
            return .element(style)
        }
        if !replaced { o.order.append(.element(style)) }
        setBarOptions(o, for: metric)
    }
    
    /// Elements a widget can be built from. There are no combined presets: e.g. percentage + icon is
    /// built by dragging the Text and Icon parts into the bar.
    /// `.standard` only remains where it is a single element (CPU graph, battery icon, network up/down, display count).
    public static func availableStyles(for metric: MetricType) -> [MetricDisplayStyle] {
        switch metric {
        case .cpu:
            return [.textOnly, .standard, .barOnly, .verticalBar, .circularGauge]
        case .battery:
            return [.textOnly, .standard, .barOnly, .verticalBar, .circularGauge]
        case .weather:
            // Bars and gauges don't mean anything for weather, so only real weather readings are offered.
            // .textOnly = temperature, .barOnly = condition icon.
            return [.textOnly, .barOnly, .feelsLike, .highLow, .humidity, .wind, .rainChance]
        case .disk, .temperatures:
            return [.textOnly, .barOnly, .verticalBar, .circularGauge]
        case .memory:
            return [.textOnly, .barOnly, .verticalBar, .circularGauge, .multicolorCircle]
        case .network:
            return [.textOnly, .standard, .verticalBar]
        case .displays:
            return [.standard, .verticalBar]
        }
    }
    
    /// The element used when nothing else is chosen (and to replace removed presets).
    public static func defaultElement(for metric: MetricType) -> MetricDisplayStyle {
        availableStyles(for: metric).contains(.textOnly) ? .textOnly : .standard
    }
    
    // MARK: - Per-widget bar options
    
    public func barOptions(for metric: MetricType) -> BarOptions {
        let d = BarOptions.defaults(for: metric)
        let k = "bar_\(metric.rawValue)_"
        return BarOptions(
            iconSize: defaults.string(forKey: k + "iconSize").flatMap(BarIconSize.init(rawValue:)) ?? d.iconSize,
            iconTint: defaults.string(forKey: k + "iconTint").flatMap(BarIconTint.init(rawValue:)) ?? d.iconTint,
            padding: defaults.object(forKey: k + "widgetPadding") == nil ? d.padding : defaults.double(forKey: k + "widgetPadding"),
            order: loadOrder(for: metric, default: d)
        )
    }
    
    /// Reads the stored part list, or migrates the older single-style + icon/label settings.
    private func loadOrder(for metric: MetricType, default d: BarOptions) -> [BarPart] {
        let k = "bar_\(metric.rawValue)_"
        var order: [BarPart]
        if let raw = defaults.string(forKey: k + "order") {
            order = raw.split(separator: ",").compactMap { BarPart(token: String($0)) }
        } else {
            let style = defaults.string(forKey: "displayStyle_\(metric.rawValue)").flatMap(MetricDisplayStyle.init(rawValue:)) ?? .standard
            let showIcon = defaults.object(forKey: k + "showIcon") == nil ? d.showIcon : defaults.bool(forKey: k + "showIcon")
            let showLabel = defaults.bool(forKey: k + "showLabel")
            let trailing = defaults.string(forKey: k + "iconPosition") == BarIconPosition.trailing.rawValue
            var chrome: [BarPart] = []
            if showIcon { chrome.append(.icon) }
            if showLabel { chrome.append(.label) }
            order = trailing ? [.element(style)] + chrome : chrome + [.element(style)]
        }
        // Repair: known parts only, no duplicates, this metric's styles only, at least one element
        let allowed = Set(Self.availableStyles(for: metric))
        let fallback = BarPart.element(Self.defaultElement(for: metric))
        var seen = Set<BarPart>()
        order = order.map { part in
            // Removed presets (e.g. the old Standard text+graphic) become the default element
            if let s = part.style, !allowed.contains(s) { return fallback }
            return part
        }.filter { part in
            if part == .icon && (metric == .battery || metric == .weather) { return false }
            return seen.insert(part).inserted
        }
        if !order.contains(where: { $0.style != nil }) { order.append(fallback) }
        return order
    }
    
    public func setBarOptions(_ o: BarOptions, for metric: MetricType) {
        let k = "bar_\(metric.rawValue)_"
        defaults.set(o.iconSize.rawValue, forKey: k + "iconSize")
        defaults.set(o.iconTint.rawValue, forKey: k + "iconTint")
        defaults.set(o.padding, forKey: k + "widgetPadding")
        defaults.set(o.order.map(\.token).joined(separator: ","), forKey: k + "order")
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
