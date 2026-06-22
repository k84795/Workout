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
    @Published var startCoordinate: CLLocationCoordinate2D?

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

    /// ワークアウト選択時点の現在地をスタート座標として確定する
    func captureStartCoordinate() {
        guard let current = currentLocation,
              current.horizontalAccuracy > 0,
              current.horizontalAccuracy <= 50 else { return }
        startCoordinate = current.coordinate
    }

    func startRouteTracking() {
        routeCoordinates = []
        // startCoordinate は captureStartCoordinate() で事前取得済みの場合は保持する。
        // 未取得の場合は最初の有効な GPS 更新時に設定される。
        isTrackingRoute = true
    }

    func stopRouteTracking() {
        isTrackingRoute = false
        startCoordinate = nil
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            if self.isTrackingRoute && location.horizontalAccuracy > 0 && location.horizontalAccuracy <= 50 {
                if self.startCoordinate == nil {
                    self.startCoordinate = location.coordinate
                }
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
