import Foundation
import CoreMotion
import CoreLocation
import Combine
import UIKit

struct SensorReading: Identifiable {
    let id = UUID()
    let timestamp: Date
    let sensor: String
    let values: [String: String]
}

class SensorManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    private let locationManager = CLLocationManager()
    
    @Published var isLogging = false
    @Published var recentReadings: [SensorReading] = []
    @Published var sessionFiles: [URL] = []
    
    // CSV writers keyed by sensor name
    private var csvWriters: [String: CSVWriter] = [:]
    private var sessionStartTime: Date?
    private var updateInterval: TimeInterval = 0.1 // 10 Hz default
    
    private let fileManager = FileManager.default
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        refreshSessionFiles()
    }
    
    // MARK: - File Management
    
    private func sessionsDirectory() -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("SensorSessions")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private func currentSessionDirectory() -> URL? {
        guard let start = sessionStartTime else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "Session_\(formatter.string(from: start))"
        let dir = sessionsDirectory().appendingPathComponent(name)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    func refreshSessionFiles() {
        let dir = sessionsDirectory()
        let contents = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        sessionFiles = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return aDate > bDate
            }
    }
    
    func deleteSession(at url: URL) {
        try? fileManager.removeItem(at: url)
        refreshSessionFiles()
    }
    
    func filesInSession(_ sessionURL: URL) -> [URL] {
        return (try? fileManager.contentsOfDirectory(at: sessionURL, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "csv" }.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }
    
    // MARK: - CSV Writer
    
    private func writerFor(sensor: String, headers: [String]) -> CSVWriter {
        if let existing = csvWriters[sensor] { return existing }
        guard let dir = currentSessionDirectory() else {
            fatalError("No session directory")
        }
        let file = dir.appendingPathComponent("\(sensor).csv")
        let writer = CSVWriter(fileURL: file, headers: ["timestamp", "seconds_elapsed"] + headers)
        csvWriters[sensor] = writer
        return writer
    }
    
    private func elapsed() -> Double {
        guard let start = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    private func addReading(sensor: String, values: [String: String]) {
        let reading = SensorReading(timestamp: Date(), sensor: sensor, values: values)
        DispatchQueue.main.async {
            self.recentReadings.insert(reading, at: 0)
            if self.recentReadings.count > 80 {
                self.recentReadings = Array(self.recentReadings.prefix(80))
            }
        }
    }
    
    // MARK: - Start / Stop
    
    func startLogging() {
        guard !isLogging else { return }
        isLogging = true
        sessionStartTime = Date()
        recentReadings.removeAll()
        csvWriters.removeAll()
        
        startAccelerometer()
        startGyroscope()
        startMagnetometer()
        startDeviceMotion()
        startBarometer()
        startPedometer()
        startActivityRecognition()
        startLocation()
        startBatteryMonitoring()
    }
    
    func stopLogging() {
        guard isLogging else { return }
        isLogging = false
        
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        motionManager.stopMagnetometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        pedometer.stopUpdates()
        locationManager.stopUpdatingLocation()
        
        // Close all CSV files
        csvWriters.values.forEach { $0.close() }
        csvWriters.removeAll()
        sessionStartTime = nil
        
        refreshSessionFiles()
    }
    
    // MARK: - Accelerometer
    
    private func startAccelerometer() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = updateInterval
        motionManager.startAccelerometerUpdates(to: .init()) { [weak self] data, _ in
            guard let self, let data else { return }
            let writer = self.writerFor(sensor: "Accelerometer", headers: ["x", "y", "z"])
            let ts = Date().timeIntervalSince1970
            writer.writeRow([
                String(format: "%.6f", ts),
                String(format: "%.6f", self.elapsed()),
                String(format: "%.6f", data.acceleration.x * 9.80665),
                String(format: "%.6f", data.acceleration.y * 9.80665),
                String(format: "%.6f", data.acceleration.z * 9.80665)
            ])
            self.addReading(sensor: "Accel", values: [
                "x": String(format: "%.3f", data.acceleration.x * 9.80665),
                "y": String(format: "%.3f", data.acceleration.y * 9.80665),
                "z": String(format: "%.3f", data.acceleration.z * 9.80665)
            ])
        }
    }
    
    // MARK: - Gyroscope
    
    private func startGyroscope() {
        guard motionManager.isGyroAvailable else { return }
        motionManager.gyroUpdateInterval = updateInterval
        motionManager.startGyroUpdates(to: .init()) { [weak self] data, _ in
            guard let self, let data else { return }
            let writer = self.writerFor(sensor: "Gyroscope", headers: ["x", "y", "z"])
            let ts = Date().timeIntervalSince1970
            writer.writeRow([
                String(format: "%.6f", ts),
                String(format: "%.6f", self.elapsed()),
                String(format: "%.6f", data.rotationRate.x),
                String(format: "%.6f", data.rotationRate.y),
                String(format: "%.6f", data.rotationRate.z)
            ])
            self.addReading(sensor: "Gyro", values: [
                "x": String(format: "%.3f", data.rotationRate.x),
                "y": String(format: "%.3f", data.rotationRate.y),
                "z": String(format: "%.3f", data.rotationRate.z)
            ])
        }
    }
    
    // MARK: - Magnetometer
    
    private func startMagnetometer() {
        guard motionManager.isMagnetometerAvailable else { return }
        motionManager.magnetometerUpdateInterval = updateInterval
        motionManager.startMagnetometerUpdates(to: .init()) { [weak self] data, _ in
            guard let self, let data else { return }
            let writer = self.writerFor(sensor: "Magnetometer", headers: ["x", "y", "z"])
            let ts = Date().timeIntervalSince1970
            writer.writeRow([
                String(format: "%.6f", ts),
                String(format: "%.6f", self.elapsed()),
                String(format: "%.6f", data.magneticField.x),
                String(format: "%.6f", data.magneticField.y),
                String(format: "%.6f", data.magneticField.z)
            ])
            self.addReading(sensor: "Mag", values: [
                "x": String(format: "%.2f", data.magneticField.x),
                "y": String(format: "%.2f", data.magneticField.y),
                "z": String(format: "%.2f", data.magneticField.z)
            ])
        }
    }
    
    // MARK: - Device Motion (Orientation / Gravity)
    
    private func startDeviceMotion() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .init()) { [weak self] data, _ in
            guard let self, let data else { return }
            let ts = Date().timeIntervalSince1970
            let el = self.elapsed()
            
            // Gravity
            let gravWriter = self.writerFor(sensor: "Gravity", headers: ["x", "y", "z"])
            gravWriter.writeRow([
                String(format: "%.6f", ts),
                String(format: "%.6f", el),
                String(format: "%.6f", data.gravity.x * 9.80665),
                String(format: "%.6f", data.gravity.y * 9.80665),
                String(format: "%.6f", data.gravity.z * 9.80665)
            ])
            
            // Orientation
            let oriWriter = self.writerFor(sensor: "Orientation", headers: ["pitch", "roll", "yaw"])
            oriWriter.writeRow([
                String(format: "%.6f", ts),
                String(format: "%.6f", el),
                String(format: "%.6f", data.attitude.pitch),
                String(format: "%.6f", data.attitude.roll),
                String(format: "%.6f", data.attitude.yaw)
            ])
            
            self.addReading(sensor: "Orient", values: [
                "pitch": String(format: "%.2f", data.attitude.pitch),
                "roll": String(format: "%.2f", data.attitude.roll),
                "yaw": String(format: "%.2f", data.attitude.yaw)
            ])
        }
    }
    
    // MARK: - Barometer / Altimeter
    
    private func startBarometer() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: .init()) { [weak self] data, _ in
            guard let self, let data else { return }
            let writer = self.writerFor(sensor: "Barometer", headers: ["pressure_kPa", "relativeAltitude_m"])
            let ts = Date().timeIntervalSince1970
            writer.writeRow([
                String(format: "%.6f", ts),
                String(format: "%.6f", self.elapsed()),
                String(format: "%.4f", data.pressure.doubleValue),
                String(format: "%.4f", data.relativeAltitude.doubleValue)
            ])
            self.addReading(sensor: "Baro", values: [
                "kPa": String(format: "%.2f", data.pressure.doubleValue),
                "alt": String(format: "%.2f", data.relativeAltitude.doubleValue)
            ])
        }
    }
    
    // MARK: - Pedometer
    
    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: sessionStartTime ?? Date()) { [weak self] data, _ in
            guard let self, let data else { return }
            let writer = self.writerFor(sensor: "Pedometer", headers: ["steps", "distance_m"])
            let ts = Date().timeIntervalSince1970
            writer.writeRow([
                String(format: "%.6f", ts),
                String(format: "%.6f", self.elapsed()),
                "\(data.numberOfSteps)",
                String(format: "%.2f", data.distance?.doubleValue ?? 0)
            ])
            self.addReading(sensor: "Steps", values: [
                "steps": "\(data.numberOfSteps)",
                "dist": String(format: "%.1fm", data.distance?.doubleValue ?? 0)
            ])
        }
    }
    
    // MARK: - Activity Recognition
    
    private func startActivityRecognition() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.startActivityUpdates(to: .init()) { [weak self] activity in
            guard let self, let activity else { return }
            let type: String
            if activity.walking { type = "walking" }
            else if activity.running { type = "running" }
            else if activity.cycling { type = "cycling" }
            else if activity.automotive { type = "automotive" }
            else if activity.stationary { type = "stationary" }
            else { type = "unknown" }
            
            let confidence: String
            switch activity.confidence {
            case .low: confidence = "low"
            case .medium: confidence = "medium"
            case .high: confidence = "high"
            @unknown default: confidence = "unknown"
            }
            
            let writer = self.writerFor(sensor: "Activity", headers: ["activity", "confidence"])
            let ts = Date().timeIntervalSince1970
            writer.writeRow([
                String(format: "%.6f", ts),
                String(format: "%.6f", self.elapsed()),
                type,
                confidence
            ])
            self.addReading(sensor: "Activity", values: ["type": type, "conf": confidence])
        }
    }
    
    // MARK: - Location (GPS)
    
    private func startLocation() {
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            for loc in locations {
                let writer = self.writerFor(sensor: "Location", headers: [
                    "latitude", "longitude", "altitude", "speed", "course",
                    "horizontalAccuracy", "verticalAccuracy"
                ])
                let ts = Date().timeIntervalSince1970
                writer.writeRow([
                    String(format: "%.6f", ts),
                    String(format: "%.6f", self.elapsed()),
                    String(format: "%.8f", loc.coordinate.latitude),
                    String(format: "%.8f", loc.coordinate.longitude),
                    String(format: "%.2f", loc.altitude),
                    String(format: "%.2f", loc.speed),
                    String(format: "%.2f", loc.course),
                    String(format: "%.2f", loc.horizontalAccuracy),
                    String(format: "%.2f", loc.verticalAccuracy)
                ])
                self.addReading(sensor: "GPS", values: [
                    "lat": String(format: "%.5f", loc.coordinate.latitude),
                    "lon": String(format: "%.5f", loc.coordinate.longitude)
                ])
            }
        }
    }
    
    // MARK: - Battery
    
    private func startBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        // Log initial state
        logBattery()
        
        NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.logBattery()
        }
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.logBattery()
        }
    }
    
    private func logBattery() {
        let level = UIDevice.current.batteryLevel * 100
        let state: String
        switch UIDevice.current.batteryState {
        case .charging: state = "charging"
        case .full: state = "full"
        case .unplugged: state = "unplugged"
        case .unknown: state = "unknown"
        @unknown default: state = "unknown"
        }
        
        let writer = writerFor(sensor: "Battery", headers: ["level_percent", "state"])
        let ts = Date().timeIntervalSince1970
        writer.writeRow([
            String(format: "%.6f", ts),
            String(format: "%.6f", elapsed()),
            String(format: "%.0f", level),
            state
        ])
        addReading(sensor: "Battery", values: ["level": "\(Int(level))%", "state": state])
    }
}

// MARK: - CSV Writer Helper

class CSVWriter {
    private var fileHandle: FileHandle?
    
    init(fileURL: URL, headers: [String]) {
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: fileURL)
        let headerLine = headers.joined(separator: ",") + "\n"
        fileHandle?.write(headerLine.data(using: .utf8)!)
    }
    
    func writeRow(_ values: [String]) {
        let line = values.joined(separator: ",") + "\n"
        fileHandle?.write(line.data(using: .utf8)!)
    }
    
    func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}