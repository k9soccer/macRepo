//
//  ContentView.swift
//  helloWorld
//
//  Created by Drew Dabe on 2026/5/7.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var sensorManager = SensorManager()
    @StateObject private var bleScanner = BluetoothScanner()
    @State private var selectedSession: URL? = nil
    @State private var showSessionFiles = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Toggle Card
                HStack {
                    VStack(alignment: .leading) {
                        Text("Sensor Logger")
                            .font(.headline)
                        Text(sensorManager.isLogging ? "Recording..." : "Idle")
                            .font(.subheadline)
                            .foregroundColor(sensorManager.isLogging ? .green : .secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { sensorManager.isLogging },
                        set: { newValue in
                            if newValue {
                                sensorManager.startLogging()
                                // Start BLE scanning into the same session directory
                                if let dir = sensorManager.filesInSession(sensorManager.sessionFiles.first ?? URL(fileURLWithPath: "/")).first?.deletingLastPathComponent() {
                                    // BLE will write to the session dir created by SensorManager
                                }
                                // Small delay to let session dir be created, then start BLE
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    let sessions = sensorManager.sessionFiles
                                    if let latest = sessions.first {
                                        bleScanner.startScanning(sessionDir: latest, startTime: Date())
                                    } else {
                                        bleScanner.startScanning()
                                    }
                                }
                            } else {
                                sensorManager.stopLogging()
                                bleScanner.stopScanning()
                            }
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top, 8)

                List {
                    // Sessions Section
                    if !sensorManager.sessionFiles.isEmpty {
                        Section("Saved Sessions") {
                            ForEach(sensorManager.sessionFiles, id: \.self) { sessionURL in
                                Button {
                                    selectedSession = sessionURL
                                    showSessionFiles = true
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(sessionURL.lastPathComponent)
                                                .font(.body)
                                            let files = sensorManager.filesInSession(sessionURL)
                                            Text("\(files.count) sensor files")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        sensorManager.deleteSession(at: sessionURL)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    ShareLink(item: sessionURL) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                    }

                    // BLE Devices Section
                    if !bleScanner.discoveredDevices.isEmpty {
                        Section("Nearby BLE Devices (\(bleScanner.discoveredDevices.count))") {
                            ForEach(bleScanner.discoveredDevices) { device in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .font(.body)
                                        Text(device.identifier.uuidString)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    Text("\(device.rssi) dBm")
                                        .fontWeight(.semibold)
                                        .foregroundColor(device.rssi > -70 ? .green : .orange)
                                }
                            }
                        }
                    }

                    // Live Feed Section
                    if !sensorManager.recentReadings.isEmpty {
                        Section("Live Feed") {
                            ForEach(sensorManager.recentReadings) { reading in
                                HStack {
                                    Text(reading.sensor)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.accentColor)
                                        .frame(width: 55, alignment: .leading)
                                    Text(reading.values.map { "\($0.key): \($0.value)" }.joined(separator: " | "))
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sensor Logger")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSessionFiles) {
                if let session = selectedSession {
                    SessionDetailView(sessionURL: session, sensorManager: sensorManager)
                }
            }
            .onAppear {
                sensorManager.refreshSessionFiles()
            }
        }
    }
}

struct SessionDetailView: View {
    let sessionURL: URL
    @ObservedObject var sensorManager: SensorManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                let files = sensorManager.filesInSession(sessionURL)
                ForEach(files, id: \.self) { file in
                    ShareLink(item: file) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(file.lastPathComponent)
                                    .font(.body)
                                if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                                   let size = attrs[.size] as? Int {
                                    Text(String(format: "%.2f KB", Double(size) / 1024.0))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .navigationTitle(sessionURL.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: sessionURL) {
                        Label("Share All", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
