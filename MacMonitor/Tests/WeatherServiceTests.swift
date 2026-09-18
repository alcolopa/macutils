import XCTest
@testable import MacMonitor

final class WeatherServiceTests: XCTestCase {
    
    func testWeatherIconMapping() {
        // Clear Day vs Night
        XCTAssertEqual(WeatherIconMapper.sfSymbol(for: "01d", conditionId: 800), "sun.max.fill")
        XCTAssertEqual(WeatherIconMapper.sfSymbol(for: "01n", conditionId: 800), "moon.stars.fill")
        
        // Clouds
        XCTAssertEqual(WeatherIconMapper.sfSymbol(for: "02d", conditionId: 802), "cloud.sun.fill")
        XCTAssertEqual(WeatherIconMapper.sfSymbol(for: "02n", conditionId: 802), "cloud.moon.fill")
        XCTAssertEqual(WeatherIconMapper.sfSymbol(for: "04d", conditionId: 804), "cloud.fill")
        
        // Rain
        XCTAssertEqual(WeatherIconMapper.sfSymbol(for: "10d", conditionId: 500), "cloud.sun.rain.fill")
        XCTAssertEqual(WeatherIconMapper.sfSymbol(for: "10n", conditionId: 500), "cloud.moon.rain.fill")
        XCTAssertEqual(WeatherIconMapper.sfSymbol(for: "09d", conditionId: 520), "cloud.heavyrain.fill")
        
        // Thunderstorm
        XCTAssertEqual(WeatherIconMapper.sfSymbol(for: "11d", conditionId: 211), "cloud.bolt.rain.fill")
        
        // Snow
        XCTAssertEqual(WeatherIconMapper.sfSymbol(for: "13d", conditionId: 600), "snowflake")
        
        // Fog/Atmosphere
        XCTAssertEqual(WeatherIconMapper.sfSymbol(for: "50d", conditionId: 741), "cloud.fog.fill")
    }
    
    func testWeatherStatsDecodingModel() throws {
        let json = """
        {
            "name": "San Francisco",
            "dt": 1695000000,
            "sys": {
                "country": "US",
                "sunrise": 1694950000,
                "sunset": 1694995000
            },
            "main": {
                "temp": 18.5,
                "feels_like": 17.8,
                "temp_min": 15.2,
                "temp_max": 21.0,
                "pressure": 1013,
                "humidity": 72
            },
            "weather": [
                {
                    "id": 800,
                    "main": "Clear",
                    "description": "clear sky",
                    "icon": "01d"
                }
            ],
            "wind": {
                "speed": 4.1,
                "deg": 280
            },
            "clouds": {
                "all": 5
            }
        }
        """.data(using: .utf8)!
        
        struct DecodableTest: Decodable {
            let name: String
            let main: MainTest
            let weather: [WeatherTest]
            struct MainTest: Decodable {
                let temp: Double
                let feels_like: Double
                let humidity: Int
            }
            struct WeatherTest: Decodable {
                let id: Int
                let main: String
                let description: String
                let icon: String
            }
        }
        
        let testDecoded = try JSONDecoder().decode(DecodableTest.self, from: json)
        XCTAssertEqual(testDecoded.name, "San Francisco")
        XCTAssertEqual(testDecoded.main.temp, 18.5)
        XCTAssertEqual(testDecoded.main.humidity, 72)
        XCTAssertEqual(testDecoded.weather.first?.main, "Clear")
    }
    
    func testWeatherPreferencesIntegration() {
        let prefs = AppPreferences.shared
        
        // Weather preference defaults
        XCTAssertTrue(prefs.isMetricVisible(.weather))
        
        // Custom API key roundtrip
        let testKey = "test_api_key_1234567890"
        prefs.weatherApiKey = testKey
        XCTAssertEqual(prefs.weatherApiKey, testKey)
        
        // Custom city roundtrip
        let testCity = "Paris, FR"
        prefs.weatherCity = testCity
        XCTAssertEqual(prefs.weatherCity, testCity)
        
        // Available styles for Weather
        let styles = AppPreferences.availableStyles(for: .weather)
        XCTAssertTrue(styles.contains(.standard))
        XCTAssertTrue(styles.contains(.textOnly))
        XCTAssertTrue(styles.contains(.barOnly))
        XCTAssertTrue(styles.contains(.circularGauge))
        
        // Display style assignment
        prefs.setDisplayStyle(.circularGauge, for: .weather)
        XCTAssertEqual(prefs.displayStyle(for: .weather), .circularGauge)
        
        prefs.setDisplayStyle(.standard, for: .weather)
        XCTAssertEqual(prefs.displayStyle(for: .weather), .standard)
        
        // Cleanup key to avoid dirtying local storage
        prefs.weatherApiKey = ""
        prefs.weatherCity = "auto"
    }
}
