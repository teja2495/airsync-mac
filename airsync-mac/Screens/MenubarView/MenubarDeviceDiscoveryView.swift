//
//  MenubarDeviceDiscoveryView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-07.
//

import SwiftUI

struct MenubarDeviceDiscoveryView: View {
    @StateObject private var udpDiscovery = UDPDiscoveryManager.shared
    @StateObject private var quickConnectManager = QuickConnectManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !udpDiscovery.discoveredDevices.isEmpty {
                Text("Nearby Devices")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(udpDiscovery.discoveredDevices) { device in
                            let lastConnected = quickConnectManager.getLastConnectedDevice()
                            DeviceCard(
                                device: device,
                                isLastConnected: lastConnected?.name == device.name && (lastConnected != nil && device.ips.contains(lastConnected!.ipAddress)),
                                isCompact: true,
                                connectAction: {
                                    quickConnectManager.connect(to: device)
                                },
                                namespace: nil // No namespace for menubar popover
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
            }
        }
    }
}

#Preview {
    MenubarDeviceDiscoveryView()
        .frame(width: 320)
        .background(Color.black.opacity(0.8))
}
