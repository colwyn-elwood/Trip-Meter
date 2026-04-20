# Trip-Meter

Minimal iOS SwiftUI MVP prototype for a rally-style trip meter.

## Included MVP behavior
- Trip 1 (tap to reset)
- Trip 2 (long press to reset)
- Current speed in mph
- Pause/Resume tracking
- Reset All
- Manual Trip 1 + Trip 2 adjustments (`-0.1`, `-0.01`, `+0.01`, `+0.1`)
- GPS warning when incoming accuracy is poor
- Distance filtering for weak/noisy points and tiny stationary drift

## Architecture
Single-file prototype in `RallyTripMeterApp.swift` with:
- `LocationManager` (CoreLocation updates + validity filtering)
- `TripMeterViewModel` (trip/speed state + actions)
- `ContentView` (high-contrast trip meter UI)

## Run
Open in Xcode as an iOS app target and use `RallyTripMeterApp.swift` as the app entry point.
