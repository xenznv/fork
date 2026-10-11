import Foundation
import CoreLocation

// Custom location spoofing state.
//
// The spoof substitutes a user-chosen location for real GPS fixes at the
// app's location plumbing boundaries (DeviceLocationManager, map views).
// It never touches the OS-level location services: other apps are unaffected.
//
// Two lifetime modes:
// - `.session`: kept in memory only, cleared when the app process restarts.
// - `.persistent`: stored in UserDefaults until the user turns it off.

public enum CustomSpoofMode: String, Codable, Equatable {
    case session
    case persistent
}

public struct CustomSpoofState: Equatable, Codable {
    public var enabled: Bool
    public var mode: CustomSpoofMode
    public var latitude: Double
    public var longitude: Double
    public var accuracy: Double

    public init(
        enabled: Bool = false,
        mode: CustomSpoofMode = .session,
        latitude: Double = 40.7128,
        longitude: Double = -74.0060,
        accuracy: Double = 32.0
    ) {
        self.enabled = enabled
        self.mode = mode
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
    }
}

private let customSpoofDefaultsKey = "custom.Spoof.State"

public final class CustomSpoofController {
    public static let shared = CustomSpoofController()

    private let lock = NSLock()
    private var state: CustomSpoofState
    private let defaults: UserDefaults

    // A freshly generated inaccuracy is attached to every fake fix so the
    // spoofed coordinates do not look unnaturally precise.
    private var nextAccuracyRefreshAt: TimeInterval = 0
    private var jitteredAccuracy: Double = 32.0

    private init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults

        // On launch the in-memory state always starts disabled. A previously
        // saved `.persistent` state is restored; `.session` state is dropped
        // by design.
        if let data = defaults.data(forKey: customSpoofDefaultsKey),
            let stored = try? JSONDecoder().decode(CustomSpoofState.self, from: data),
            stored.enabled, stored.mode == .persistent {
            self.state = stored
        } else {
            self.state = CustomSpoofState()
            defaults.removeObject(forKey: customSpoofDefaultsKey)
        }
        self.jitteredAccuracy = self.state.accuracy
    }

    public var currentState: CustomSpoofState {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state
    }

    public var isEnabled: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.enabled
    }

    public func update(_ transform: (inout CustomSpoofState) -> Void) {
        self.lock.lock()
        var updated = self.state
        transform(&updated)
        updated.latitude = max(-90.0, min(90.0, updated.latitude))
        updated.longitude = max(-180.0, min(180.0, updated.longitude))
        self.state = updated
        self.lock.unlock()

        if updated.enabled && updated.mode == .persistent {
            if let data = try? JSONEncoder().encode(updated) {
                self.defaults.set(data, forKey: customSpoofDefaultsKey)
            }
        } else {
            self.defaults.removeObject(forKey: customSpoofDefaultsKey)
        }
    }

    public func setEnabled(_ enabled: Bool) {
        self.update { $0.enabled = enabled }
    }

    public func setCoordinate(latitude: Double, longitude: Double) {
        self.update { state in
            state.latitude = latitude
            state.longitude = longitude
        }
    }

    /// Applies the spoof to a real fix. Returns the input location unchanged
    /// when the spoof is disabled.
    public func apply(_ location: CLLocation?) -> CLLocation? {
        guard let location, let spoof = self.activeSpoof() else {
            return location
        }
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: spoof.latitude, longitude: spoof.longitude),
            altitude: location.altitude,
            horizontalAccuracy: spoof.accuracy,
            verticalAccuracy: location.verticalAccuracy,
            course: -1.0,
            speed: -1.0,
            timestamp: Date()
        )
    }

    public func applyCoordinate(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard let spoof = self.activeSpoof() else {
            return coordinate
        }
        return CLLocationCoordinate2D(latitude: spoof.latitude, longitude: spoof.longitude)
    }

    private func activeSpoof() -> (latitude: Double, longitude: Double, accuracy: Double)? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.state.enabled else {
            return nil
        }
        let now = Date().timeIntervalSince1970
        if now >= self.nextAccuracyRefreshAt {
            // Refresh the reported accuracy every ~90 seconds within a
            // believable 10..65 m band.
            self.jitteredAccuracy = Double.random(in: 10.0 ... 65.0)
            self.nextAccuracyRefreshAt = now + 90.0
        }
        return (self.state.latitude, self.state.longitude, self.jitteredAccuracy)
    }
}
