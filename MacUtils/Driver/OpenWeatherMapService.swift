import Foundation

public final class OpenWeatherMapService: Sendable {
    public static let shared = OpenWeatherMapService()
    
    private init() {}
    
    // MARK: - OpenWeatherMap API Responses
    
    private struct CurrentWeatherResponse: Decodable {
        let name: String
        let sys: SysInfo
        let main: MainInfo
        let weather: [WeatherInfo]
        let wind: WindInfo?
        let clouds: CloudsInfo?
        let dt: TimeInterval
        
        struct SysInfo: Decodable {
            let country: String?
            let sunrise: TimeInterval?
            let sunset: TimeInterval?
        }
        
        struct MainInfo: Decodable {
            let temp: Double
            let feels_like: Double
            let temp_min: Double
            let temp_max: Double
            let pressure: Int
            let humidity: Int
        }
        
        struct WeatherInfo: Decodable {
            let id: Int
            let main: String
            let description: String
            let icon: String
        }
        
        struct WindInfo: Decodable {
            let speed: Double?
            let deg: Int?
        }
        
        struct CloudsInfo: Decodable {
            let all: Int?
        }
    }
    
    private struct ForecastResponse: Decodable {
        let list: [ForecastItem]
        
        struct ForecastItem: Decodable {
            let dt: TimeInterval
            let main: CurrentWeatherResponse.MainInfo
            let weather: [CurrentWeatherResponse.WeatherInfo]
            let pop: Double? // Probability of precipitation 0..1
        }
    }
    
    // MARK: - Public Fetch Methods
    
    public func fetchWeather(apiKey: String, location: String) async throws -> WeatherStats {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLoc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKey.isEmpty else {
            return WeatherStats.unconfigured
        }
        
        let locQuery = trimmedLoc.isEmpty ? "auto" : trimmedLoc
        
        // 1. If location is "auto" or empty, try IP geolocation fallback
        let targetLocation: String
        if locQuery == "auto" {
            if let coord = await LocationProvider.shared.currentCoordinate() {
                targetLocation = "coord:\(coord.latitude),\(coord.longitude)"
            } else {
                targetLocation = try await fetchAutoLocation()
            }
        } else {
            targetLocation = locQuery
        }
        
        // 2. Fetch Current Weather
        async let currentTask = fetchCurrentWeather(apiKey: trimmedKey, location: targetLocation)
        async let forecastTask = fetchForecast(apiKey: trimmedKey, location: targetLocation)
        
        let (current, forecast) = try await (currentTask, forecastTask)
        
        return WeatherStats(
            current: current,
            forecast: forecast,
            lastUpdated: Date(),
            errorMessage: nil,
            isConfigured: true
        )
    }
    
    public func validateApiKey(_ apiKey: String) async -> Result<String, Error> {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return .failure(NSError(domain: "OpenWeatherMap", code: 400, userInfo: [NSLocalizedDescriptionKey: "API key cannot be empty"]))
        }
        
        // Test with a lightweight query (London)
        let urlString = "https://api.openweathermap.org/data/2.5/weather?q=London&units=metric&appid=\(trimmedKey)"
        guard let url = URL(string: urlString) else {
            return .failure(NSError(domain: "OpenWeatherMap", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL structure"]))
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpRes = response as? HTTPURLResponse {
                if httpRes.statusCode == 200 {
                    return .success("API Key is valid and active!")
                } else if httpRes.statusCode == 401 {
                    return .failure(NSError(domain: "OpenWeatherMap", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid API key. Please check your key on openweathermap.org"]))
                } else {
                    let errMsg = String(data: data, encoding: .utf8) ?? "Server returned error \(httpRes.statusCode)"
                    return .failure(NSError(domain: "OpenWeatherMap", code: httpRes.statusCode, userInfo: [NSLocalizedDescriptionKey: errMsg]))
                }
            }
            return .success("Connected successfully")
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Private API Calls
    
    private func fetchCurrentWeather(apiKey: String, location: String) async throws -> WeatherData {
        guard let locQuery = Self.locationQuery(location),
              let url = URL(string: "https://api.openweathermap.org/data/2.5/weather?\(locQuery)&units=metric&appid=\(apiKey)") else {
            throw NSError(domain: "OpenWeatherMap", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid location encoding"])
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpRes = response as? HTTPURLResponse, httpRes.statusCode != 200 {
            if httpRes.statusCode == 404 {
                throw NSError(domain: "OpenWeatherMap", code: 404, userInfo: [NSLocalizedDescriptionKey: "City '\(location)' not found. Check spelling or try 'City, Country'"])
            } else if httpRes.statusCode == 401 {
                throw NSError(domain: "OpenWeatherMap", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid API key."])
            } else {
                throw NSError(domain: "OpenWeatherMap", code: httpRes.statusCode, userInfo: [NSLocalizedDescriptionKey: "Weather service error (code \(httpRes.statusCode))"])
            }
        }
        
        let decoded = try JSONDecoder().decode(CurrentWeatherResponse.self, from: data)
        let condition = decoded.weather.first.map {
            WeatherCondition(id: $0.id, main: $0.main, description: $0.description.capitalized, icon: $0.icon)
        } ?? WeatherCondition(id: 800, main: "Clear", description: "Clear Sky", icon: "01d")
        
        let sunriseDate = decoded.sys.sunrise.map { Date(timeIntervalSince1970: $0) }
        let sunsetDate = decoded.sys.sunset.map { Date(timeIntervalSince1970: $0) }
        
        return WeatherData(
            cityName: decoded.name,
            country: decoded.sys.country ?? "",
            temperature: decoded.main.temp,
            feelsLike: decoded.main.feels_like,
            tempMin: decoded.main.temp_min,
            tempMax: decoded.main.temp_max,
            humidity: decoded.main.humidity,
            pressure: decoded.main.pressure,
            windSpeed: decoded.wind?.speed ?? 0.0,
            windDeg: decoded.wind?.deg ?? 0,
            cloudiness: decoded.clouds?.all ?? 0,
            condition: condition,
            sunrise: sunriseDate,
            sunset: sunsetDate,
            timestamp: Date(timeIntervalSince1970: decoded.dt)
        )
    }
    
    private func fetchForecast(apiKey: String, location: String) async throws -> [WeatherForecastItem] {
        guard let locQuery = Self.locationQuery(location),
              let url = URL(string: "https://api.openweathermap.org/data/2.5/forecast?\(locQuery)&units=metric&appid=\(apiKey)") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            return []
        }
        
        guard let decoded = try? JSONDecoder().decode(ForecastResponse.self, from: data) else {
            return []
        }
        
        if AppPreferences.shared.weatherForecastMode == .threeHourly {
            // Next 24 hours in the API's native 3-hour steps
            return decoded.list.prefix(8).map { entry in
                let cond = entry.weather.first.map {
                    WeatherCondition(id: $0.id, main: $0.main, description: $0.description.capitalized, icon: $0.icon)
                } ?? WeatherCondition(id: 800, main: "Clear", description: "Clear Sky", icon: "01d")
                return WeatherForecastItem(
                    date: Date(timeIntervalSince1970: entry.dt),
                    temperature: entry.main.temp,
                    tempMin: entry.main.temp_min,
                    tempMax: entry.main.temp_max,
                    condition: cond,
                    precipitationChance: entry.pop ?? 0.0
                )
            }
        }
        
        // Aggregate the 3-hourly entries into one item per local calendar day
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: decoded.list) {
            calendar.startOfDay(for: Date(timeIntervalSince1970: $0.dt))
        }

        return grouped.keys.sorted().prefix(5).compactMap { day in
            guard let entries = grouped[day], !entries.isEmpty else { return nil }

            // Representative entry: the one closest to midday
            let noon = day.addingTimeInterval(12 * 3600)
            let rep = entries.min {
                abs(Date(timeIntervalSince1970: $0.dt).timeIntervalSince(noon)) <
                abs(Date(timeIntervalSince1970: $1.dt).timeIntervalSince(noon))
            }!
            let cond = rep.weather.first.map {
                WeatherCondition(id: $0.id, main: $0.main, description: $0.description.capitalized, icon: $0.icon.replacingOccurrences(of: "n", with: "d"))
            } ?? WeatherCondition(id: 800, main: "Clear", description: "Clear Sky", icon: "01d")

            return WeatherForecastItem(
                date: day,
                temperature: rep.main.temp,
                tempMin: entries.map { $0.main.temp_min }.min() ?? rep.main.temp_min,
                tempMax: entries.map { $0.main.temp_max }.max() ?? rep.main.temp_max,
                condition: cond,
                precipitationChance: entries.compactMap { $0.pop }.max() ?? 0.0
            )
        }
    }
    
    /// Builds the OpenWeatherMap location query: `lat=..&lon=..` for "coord:lat,lon", otherwise `q=<name>`.
    private static func locationQuery(_ location: String) -> String? {
        if location.hasPrefix("coord:") {
            let parts = location.dropFirst("coord:".count).split(separator: ",")
            guard parts.count == 2 else { return nil }
            return "lat=\(parts[0])&lon=\(parts[1])"
        }
        guard let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return "q=\(encoded)"
    }

    private func fetchAutoLocation() async throws -> String {
        // Lightweight IP geolocation fallback using free ip-api endpoint
        guard let url = URL(string: "http://ip-api.com/json/?fields=city,country") else {
            return "New York, US"
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        
        struct IPLocationResponse: Decodable {
            let city: String?
            let country: String?
        }
        
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let res = try? JSONDecoder().decode(IPLocationResponse.self, from: data),
              let city = res.city, !city.isEmpty else {
            return "London, UK"
        }
        
        if let country = res.country, !country.isEmpty {
            return "\(city), \(country)"
        }
        return city
    }
}
