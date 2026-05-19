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

    private var allDiscoveredDevices: [DiscoveredDevice] {
        var devices = udpDiscovery.discoveredDevices
        
        // Only include BLE devices if BLE is enabled
        if appState.isBLEEnabled {
            let bleDevices = bleManager.discoveredBLEDevices
            for bleDevice in bleDevices {
                if !devices.contains(where: { $0.name == bleDevice.name }) {
                    devices.append(bleDevice)
                }
            }
        }
        
        return devices
    }

    var body: some View {
        VStack(spacing: 24) {
            // BLE Settings Toggles Section
            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    Image("logo.bluetooth")
                        .foregroundColor(.accentColor)
                    Toggle("BLE", isOn: $appState.isBLEEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.accentColor)
                    Toggle("Auto-connect", isOn: $appState.isBLEAutoConnectEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!appState.isBLEEnabled)
                }
            }
            .padding()
            .glassBoxIfAvailable(radius: 24)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
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
                                    isLastConnected: lastConnected?.name == device.name && (lastConnected != nil && device.ips.contains(lastConnected!.ipAddress)),
                                    isCompact: false, // Expanded mode always!
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
