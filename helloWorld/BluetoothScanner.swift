import Foundation
import CoreBluetooth
import Combine

struct DiscoveredDevice: Identifiable {
    let id = UUID()
    let name: String
    let rssi: Int
    let identifier: UUID
    let timestamp: Date
}

class BluetoothScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager!
    @Published var isScanning = false
    @Published var discoveredDevices: [DiscoveredDevice] = []
    
    // CSV logging support
    private var csvWriter: CSVWriter?
    private var sessionStartTime: Date?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning(sessionDir: URL? = nil, startTime: Date? = nil) {
        if centralManager.state == .poweredOn {
            isScanning = true
            discoveredDevices.removeAll()
            sessionStartTime = startTime
            
            if let dir = sessionDir {
                let fileURL = dir.appendingPathComponent("BLE_Scan.csv")
                csvWriter = CSVWriter(fileURL: fileURL, headers: ["timestamp", "seconds_elapsed", "device_name", "mac_address", "rssi_dBm"])
            }
            
            centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
        csvWriter?.close()
        csvWriter = nil
        sessionStartTime = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Do not auto-start; let the UI control scanning
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Device"
        let uuid = peripheral.identifier
        let now = Date()
        
        // Write to CSV if logging
        if let writer = csvWriter {
            let ts = now.timeIntervalSince1970
            let elapsed = sessionStartTime.map { now.timeIntervalSince($0) } ?? 0
            writer.writeRow([
                String(format: "%.6f", ts),
                String(format: "%.6f", elapsed),
                name,
                uuid.uuidString,
                "\(RSSI.intValue)"
            ])
        }
        
        DispatchQueue.main.async {
            let device = DiscoveredDevice(name: name, rssi: RSSI.intValue, identifier: uuid, timestamp: now)
            
            if let index = self.discoveredDevices.firstIndex(where: { $0.identifier == uuid }) {
                self.discoveredDevices[index] = device
            } else {
                self.discoveredDevices.append(device)
            }
            
            self.discoveredDevices.sort { $0.rssi > $1.rssi }
        }
    }
}