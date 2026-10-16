import CoreLocation
import Foundation

/// One-shot access to the device's current coordinates via Core Location.
/// Asks for permission at most once and remembers the last coordinate across launches;
/// returns nil when denied or unavailable so callers can fall back to IP geolocation.
@MainActor
public final class LocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    public static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var continuations: [CheckedContinuation<CLLocation?, Never>] = []
    private var cached: CLLocation?
    private var cachedAt: Date?

    private let defaults = UserDefaults.standard
    private let keyLat = "savedLocationLat"
    private let keyLon = "savedLocationLon"
    private let keyPrompted = "locationPermissionPrompted"

    private var saved: CLLocationCoordinate2D? {
        guard defaults.object(forKey: keyLat) != nil, defaults.object(forKey: keyLon) != nil else { return nil }
        return CLLocationCoordinate2D(latitude: defaults.double(forKey: keyLat), longitude: defaults.double(forKey: keyLon))
    }

    private func save(_ coordinate: CLLocationCoordinate2D) {
        defaults.set(coordinate.latitude, forKey: keyLat)
        defaults.set(coordinate.longitude, forKey: keyLon)
    }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    public func currentCoordinate() async -> CLLocationCoordinate2D? {
        if let cached, let cachedAt, Date().timeIntervalSince(cachedAt) < 600 {
            return cached.coordinate
        }
        guard CLLocationManager.locationServicesEnabled() else { return saved }

        switch manager.authorizationStatus {
        case .denied, .restricted:
            return saved
        case .notDetermined:
            // Never prompt twice: after the first ask (or if we already have a location) use what we know.
            if defaults.bool(forKey: keyPrompted) || saved != nil { return saved }
            defaults.set(true, forKey: keyPrompted)
        default:
            // Already authorised: answer from the remembered location and refresh it quietly in the background.
            if let saved {
                Task { [weak self] in _ = await self?.refresh() }
                return saved
            }
        }

        return await refresh()
    }

    /// Fetches a fresh fix (prompting only if permission was never asked) and remembers it.
    private func refresh() async -> CLLocationCoordinate2D? {
        let location = await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            continuations.append(cont)
            guard continuations.count == 1 else { return }
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
        guard let location else { return saved }
        cached = location
        cachedAt = Date()
        save(location.coordinate)
        return location.coordinate
    }

    private func finish(_ location: CLLocation?) {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: location) }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !continuations.isEmpty else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            break
        case .denied, .restricted:
            finish(nil)
        default:
            manager.requestLocation()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}
