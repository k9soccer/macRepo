//
//  ContentView.swift
//  helloWorld
//
//  Created by Drew Dabe on 2026/5/7.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = BluetoothScanner()

    var body: some View {
        VStack {
            Text("BLE Scanner")
                .font(.largeTitle)
                .bold()
                .padding(.top)

            Button(action: {
                if scanner.isScanning {
                    scanner.stopScanning()
                } else {
                    scanner.startScanning()
                }
            }) {
                Text(scanner.isScanning ? "Stop Scanning" : "Start Scanning")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(scanner.isScanning ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding(.horizontal)
            }

            List(scanner.discoveredDevices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(.headline)
                        Text(device.identifier.uuidString)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    // Display RSSI (Signal strength in dBm)
                    Text("\(device.rssi) dBm")
                        .fontWeight(.bold)
                        .foregroundColor(device.rssi > -70 ? .green : .orange)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

#Preview {
    ContentView()
}
