import Foundation
import AppKit

public struct WeatherCondition: Sendable, Codable {
    public let id: Int
    public let main: String
    public let description: String
    public let icon: String
    
    public init(id: Int, main: String, description: String, icon: String) {
        self.id = id
        self.main = main
        self.description = description
        self.icon = icon
    }
}

public struct WeatherData: Sendable, Codable {
    public let cityName: String
    public let country: String
    public let temperature: Double       // Celsius
    public let feelsLike: Double         // Celsius
    public let tempMin: Double           // Celsius
    public let tempMax: Double           // Celsius
    public let humidity: Int             // Percentage 0-100
    public let pressure: Int             // hPa
    public let windSpeed: Double         // m/s
    public let windDeg: Int              // Degrees
    public let cloudiness: Int          // Percentage 0-100
    public let condition: WeatherCondition
    public let sunrise: Date?
    public let sunset: Date?
    public let timestamp: Date
    
    public init(
        cityName: String,
        country: String,
        temperature: Double,
        feelsLike: Double,
        tempMin: Double,
        tempMax: Double,
        humidity: Int,
        pressure: Int,
        windSpeed: Double,
        windDeg: Int,
        cloudiness: Int,
        condition: WeatherCondition,
        sunrise: Date?,
        sunset: Date?,
        timestamp: Date
    ) {
        self.cityName = cityName
        self.country = country
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.tempMin = tempMin
        self.tempMax = tempMax
        self.humidity = humidity
        self.pressure = pressure
        self.windSpeed = windSpeed
        self.windDeg = windDeg
        self.cloudiness = cloudiness
        self.condition = condition
        self.sunrise = sunrise
        self.sunset = sunset
        self.timestamp = timestamp
    }
}

public struct WeatherForecastItem: Sendable, Codable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let temperature: Double       // Celsius
    public let tempMin: Double           // Celsius
    public let tempMax: Double           // Celsius
    public let condition: WeatherCondition
    public let precipitationChance: Double // 0.0 - 1.0 (pop)
    
    public init(
        date: Date,
        temperature: Double,
        tempMin: Double,
        tempMax: Double,
        condition: WeatherCondition,
        precipitationChance: Double
    ) {
        self.date = date
        self.temperature = temperature
        self.tempMin = tempMin
        self.tempMax = tempMax
        self.condition = condition
        self.precipitationChance = precipitationChance
    }
}

public struct WeatherStats: Sendable {
    public let current: WeatherData?
    public let forecast: [WeatherForecastItem]
    public let lastUpdated: Date?
    public let errorMessage: String?
    public let isConfigured: Bool
    
    public init(
        current: WeatherData? = nil,
        forecast: [WeatherForecastItem] = [],
        lastUpdated: Date? = nil,
        errorMessage: String? = nil,
        isConfigured: Bool = false
    ) {
        self.current = current
        self.forecast = forecast
        self.lastUpdated = lastUpdated
        self.errorMessage = errorMessage
        self.isConfigured = isConfigured
    }
    
    public static var unconfigured: WeatherStats {
        WeatherStats(
            current: nil,
            forecast: [],
            lastUpdated: nil,
            errorMessage: "OpenWeatherMap API Key Required",
            isConfigured: false
        )
    }
}

public enum WeatherIconMapper {
    /// Maps OpenWeatherMap icon codes (like "01d", "10n") and weather condition IDs to Apple SF Symbols.
    public static func sfSymbol(for iconCode: String, conditionId: Int = 800) -> String {
        let isNight = iconCode.hasSuffix("n")
        
        switch conditionId {
        case 200...232:
            return isNight ? "cloud.moon.bolt.fill" : "cloud.bolt.rain.fill"
        case 300...321:
            return "cloud.drizzle.fill"
        case 500...504:
            return isNight ? "cloud.moon.rain.fill" : "cloud.sun.rain.fill"
        case 511:
            return "snowflake"
        case 520...531:
            return "cloud.heavyrain.fill"
        case 600...622:
            return "snowflake"
        case 701...781:
            return "cloud.fog.fill"
        case 800:
            return isNight ? "moon.stars.fill" : "sun.max.fill"
        case 801:
            return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        case 802:
            return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        case 803, 804:
            return "cloud.fill"
        default:
            return isNight ? "moon.fill" : "sun.max.fill"
        }
    }
    
    public static func conditionColor(for conditionId: Int, isNight: Bool = false) -> NSColor {
        switch conditionId {
        case 200...232:
            return .systemPurple
        case 300...531:
            return .systemBlue
        case 600...622:
            return .systemTeal
        case 701...781:
            return .systemGray
        case 800:
            return isNight ? .systemIndigo : .systemYellow
        case 801...804:
            return isNight ? .systemIndigo : .systemCyan
        default:
            return .systemBlue
        }
    }
}
