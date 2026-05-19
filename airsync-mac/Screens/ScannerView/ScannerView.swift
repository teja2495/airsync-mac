//
//  ScannerView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import SwiftUI

struct ScannerView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject private var quickConnectManager = QuickConnectManager.shared
    @ObservedObject private var udpDiscovery = UDPDiscoveryManager.shared
    @ObservedObject private var bleManager = BLECentralManager.shared
    @Namespace private var animation

    static func cleanDeviceName(_ name: String) -> String {
        return name
            .replacingOccurrences(of: "AirSync-AirSync-", with: "")
            .replacingOccurrences(of: "AirSync-", with: "")
            .replacingOccurrences(of: "airsync-", with: "")
            .replacingOccurrences(of: "airsync", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func namesAreSimilar(_ name1: String, _ name2: String) -> Bool {
        let clean1 = cleanDeviceName(name1).lowercased()
        let clean2 = cleanDeviceName(name2).lowercased()
        return clean1.contains(clean2) || clean2.contains(clean1) || clean1 == clean2
    }

    private var allDiscoveredDevices: [DiscoveredDevice] {
        var mergedDevices: [DiscoveredDevice] = []
        
        // Start with UDP (Wi-Fi/Network) discovered devices
        for udpDevice in udpDiscovery.discoveredDevices {
            mergedDevices.append(udpDevice)
        }
        
        // If BLE is enabled, merge or append BLE devices
        if appState.isBLEEnabled {
            let bleDevices = bleManager.discoveredBLEDevices
            for bleDevice in bleDevices {
                if let index = mergedDevices.firstIndex(where: { ScannerView.namesAreSimilar($0.name, bleDevice.name) }) {
                    var matchedDevice = mergedDevices[index]
                    matchedDevice.ips.insert("Bluetooth LE")
                    mergedDevices[index] = matchedDevice
                } else {
                    let cleanedName = ScannerView.cleanDeviceName(bleDevice.name)
                    let cleanedBLEDevice = DiscoveredDevice(
                        deviceId: bleDevice.deviceId,
                        name: cleanedName,
                        ips: bleDevice.ips,
                        port: bleDevice.port,
                        type: bleDevice.type,
                        lastSeen: bleDevice.lastSeen
                    )
                    mergedDevices.append(cleanedBLEDevice)
                }
            }
        }
        
        return mergedDevices
    }

    var body: some View {
        VStack(spacing: 24) {
            // Available Devices Section (UDP and BLE Discovery)
            VStack(spacing: 12) {
                
                if allDiscoveredDevices.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Looking for devices...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack {
                        Spacer()
                        Text("Available Devices")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(allDiscoveredDevices) { device in
                                let lastConnected = quickConnectManager.getLastConnectedDevice()
                                DeviceCard(
                                    device: device,
                                    isLastConnected: lastConnected != nil && ScannerView.namesAreSimilar(lastConnected!.name, device.name),
                                    connectAction: {
                                        if device.type == "ble" {
                                            bleManager.connectManually(toUuid: device.deviceId)
                                        } else {
                                            quickConnectManager.connect(to: device)
                                        }
                                    },
                                    namespace: animation
                                )
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .scrollClipDisabled()
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .frame(minWidth: 320)
        .onAppear {
            // Refresh device info for current network on load
            quickConnectManager.refreshDeviceForCurrentNetwork()
        }
        .onChange(of: appState.selectedNetworkAdapterName) { _, _ in
            quickConnectManager.refreshDeviceForCurrentNetwork()
        }
    }
}

func generateQRText(ip: String?, port: UInt16?, name: String?, key: String) -> String? {
    guard let ip = ip, let port = port else {
        return nil
    }

    let encodedName = name?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "My Mac"
    return "airsync://\(ip):\(port)?name=\(encodedName)?plus=\(AppState.shared.isPlus)?key=\(key)"
}

#Preview {
    ScannerView()
}
