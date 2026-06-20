//
//  LocationManager.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/06/20.
//

import CoreLocation
import Combine

@MainActor
class LocationManager: NSObject, ObservableObject {
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []

    private let clManager = CLLocationManager()
    private var isTrackingRoute = false

    override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBest
        clManager.distanceFilter = 5
        authorizationStatus = clManager.authorizationStatus
    }

    func requestAndStart() {
        clManager.requestWhenInUseAuthorization()
        clManager.startUpdatingLocation()
    }

    func startRouteTracking() {
        routeCoordinates = []
        isTrackingRoute = true
    }

    func stopRouteTracking() {
        isTrackingRoute = false
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            if self.isTrackingRoute && location.horizontalAccuracy > 0 && location.horizontalAccuracy <= 50 {
                self.routeCoordinates.append(location.coordinate)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("📍 Location error: \(error.localizedDescription)")
    }
}
