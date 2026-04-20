import SwiftUI
import CoreLocation
import Combine

private enum TripMeterConstants {
    static let poorAccuracyThresholdMeters: CLLocationAccuracy = 25
    static let stationarySpeedThresholdMetersPerSecond: CLLocationSpeed = 0.5
    static let stationaryJitterThresholdMeters: CLLocationDistance = 1.5
    static let metersToMiles = 0.000621371
    static let metersPerSecondToMilesPerHour = 2.23694
    static let speedCapMetersPerSecond: CLLocationSpeed = 70
    static let fallbackDistanceThresholdMeters: CLLocationDistance = 3
}

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentSpeedMetersPerSecond: CLLocationSpeed = 0
    @Published var distanceIncrementMeters: CLLocationDistance = 0
    @Published var gpsWarning = false

    private let manager = CLLocationManager()
    private var previousValidLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func startUpdates() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        gpsWarning = true
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            gpsWarning = true
        case .notDetermined:
            break
        @unknown default:
            gpsWarning = true
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            handle(location: location)
        }
    }

    private func handle(location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= TripMeterConstants.poorAccuracyThresholdMeters else {
            gpsWarning = true
            return
        }

        gpsWarning = false

        guard let previous = previousValidLocation else {
            previousValidLocation = location
            currentSpeedMetersPerSecond = max(location.speed, 0)
            return
        }

        let elapsed = location.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return }

        let distance = location.distance(from: previous)
        let measuredSpeed = max(location.speed, 0)

        if measuredSpeed < TripMeterConstants.stationarySpeedThresholdMetersPerSecond,
           distance < TripMeterConstants.stationaryJitterThresholdMeters {
            previousValidLocation = location
            currentSpeedMetersPerSecond = 0
            return
        }

        if measuredSpeed == 0, distance < TripMeterConstants.fallbackDistanceThresholdMeters {
            previousValidLocation = location
            currentSpeedMetersPerSecond = 0
            return
        }

        previousValidLocation = location
        let fallbackSpeed = min(distance / elapsed, TripMeterConstants.speedCapMetersPerSecond)
        currentSpeedMetersPerSecond = measuredSpeed > 0 ? measuredSpeed : fallbackSpeed
        distanceIncrementMeters = distance
    }
}

final class TripMeterViewModel: ObservableObject {
    @Published var trip1Miles: Double = 0
    @Published var trip2Miles: Double = 0
    @Published var currentSpeedMPH: Double = 0
    @Published var isPaused = false
    @Published var gpsWarning = false

    private let locationManager: LocationManager
    private var cancellables = Set<AnyCancellable>()

    init(locationManager: LocationManager = LocationManager()) {
        self.locationManager = locationManager

        locationManager.$distanceIncrementMeters
            .receive(on: RunLoop.main)
            .sink { [weak self] meters in
                guard let self, meters > 0, !self.isPaused else { return }
                let miles = meters * TripMeterConstants.metersToMiles
                self.trip1Miles += miles
                self.trip2Miles += miles
            }
            .store(in: &cancellables)

        locationManager.$currentSpeedMetersPerSecond
            .receive(on: RunLoop.main)
            .map { $0 * TripMeterConstants.metersPerSecondToMilesPerHour }
            .assign(to: &$currentSpeedMPH)

        locationManager.$gpsWarning
            .receive(on: RunLoop.main)
            .assign(to: &$gpsWarning)
    }

    func start() {
        locationManager.startUpdates()
    }

    func togglePause() {
        isPaused.toggle()
    }

    func resetTrip1() {
        trip1Miles = 0
    }

    func resetTrip2() {
        trip2Miles = 0
    }

    func resetAll() {
        resetTrip1()
        resetTrip2()
    }

    func adjustTrip1(by deltaMiles: Double) {
        trip1Miles = max(0, trip1Miles + deltaMiles)
    }

    func adjustTrip2(by deltaMiles: Double) {
        trip2Miles = max(0, trip2Miles + deltaMiles)
    }

    func adjustBothTrips(by deltaMiles: Double) {
        adjustTrip1(by: deltaMiles)
        adjustTrip2(by: deltaMiles)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = TripMeterViewModel()

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.06, blue: 0.04)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                meterBlock(label: "TRIP 1", value: viewModel.trip1Miles)
                    .onTapGesture {
                        viewModel.resetTrip1()
                    }
                    .accessibilityLabel("Trip 1 distance")
                    .accessibilityHint("Double tap to reset Trip 1")
                    .accessibilityAction(named: "Reset Trip 1") {
                        viewModel.resetTrip1()
                    }

                meterBlock(label: "TRIP 2", value: viewModel.trip2Miles)
                    .onLongPressGesture {
                        viewModel.resetTrip2()
                    }
                    .accessibilityLabel("Trip 2 distance")
                    .accessibilityHint("Long press to reset Trip 2")
                    .accessibilityAction(named: "Reset Trip 2") {
                        viewModel.resetTrip2()
                    }

                VStack(spacing: 2) {
                    Text("SPEED")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("\(viewModel.currentSpeedMPH, specifier: "%.1f") mph")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }

                if viewModel.gpsWarning {
                    Text("GPS signal weak — accuracy reduced")
                        .font(.footnote)
                        .foregroundColor(.yellow)
                }

                HStack(spacing: 12) {
                    Button("-0.1") { viewModel.adjustBothTrips(by: -0.1) }
                        .accessibilityLabel("Decrease Trip 1 and Trip 2 by one tenth of a mile")
                    Button("-0.01") { viewModel.adjustBothTrips(by: -0.01) }
                        .accessibilityLabel("Decrease Trip 1 and Trip 2 by one hundredth of a mile")
                    Button("+0.01") { viewModel.adjustBothTrips(by: 0.01) }
                        .accessibilityLabel("Increase Trip 1 and Trip 2 by one hundredth of a mile")
                    Button("+0.1") { viewModel.adjustBothTrips(by: 0.1) }
                        .accessibilityLabel("Increase Trip 1 and Trip 2 by one tenth of a mile")
                }
                .buttonStyle(TripButtonStyle())

                HStack(spacing: 12) {
                    Button(viewModel.isPaused ? "Resume" : "Pause") {
                        viewModel.togglePause()
                    }
                    Button("Reset All") {
                        viewModel.resetAll()
                    }
                }
                .buttonStyle(TripButtonStyle())
            }
            .padding(20)
        }
        .onAppear {
            viewModel.start()
        }
    }

    @ViewBuilder
    private func meterBlock(label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.green)
            Text("\(value, specifier: "%.3f") mi")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.35))
        .cornerRadius(16)
    }
}

private struct TripButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? Color.green.opacity(0.5) : Color.green.opacity(0.85))
            .cornerRadius(10)
    }
}

@main
struct RallyTripMeterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
