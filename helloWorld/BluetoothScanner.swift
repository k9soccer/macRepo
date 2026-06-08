import Foundation
import CoreBluetooth
import Combine

struct DiscoveredDevice: Identifiable {
    let id = UUID()
    let name: String
    let rssi: Int
    let identifier: UUID
}

class BluetoothScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager!
    @Published var isScanning = false
    @Published var discoveredDevices: [DiscoveredDevice] = []

    override init() {
        super.init()
        // Initialize the CoreBluetooth central manager. The delegate will receive updates on Bluetooth state.
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        if centralManager.state == .poweredOn {
            isScanning = true
            discoveredDevices.removeAll()
            // Scanning for all devices. nil means any UUID.
            centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
    }

    // Called when the Bluetooth hardware state changes (e.g. user turns Bluetooth on/off)
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            // Automatically start scanning if powered on
            startScanning()
        } else {
            stopScanning()
        }
    }

    // Called every time the scanner pings a discovery packet from a BLE device
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Device"
        let uuid = peripheral.identifier
        
        DispatchQueue.main.async {
            let device = DiscoveredDevice(name: name, rssi: RSSI.intValue, identifier: uuid)
            
            // Check if we already found this device, update its signal strength (RSSI)
            if let index = self.discoveredDevices.firstIndex(where: { $0.identifier == uuid }) {
                self.discoveredDevices[index] = device
            } else {
                self.discoveredDevices.append(device)
            }
            
            // Sort by strongest signal (closest to 0)
            self.discoveredDevices.sort { $0.rssi > $1.rssi }
        }
    }
}