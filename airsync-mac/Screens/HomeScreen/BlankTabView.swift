//
//  BlankTabView.swift
//  airsync-mac
//
//  Created by Codex on 2026-05-27.
//

import SwiftUI

struct BlankTabView: View {
    @ObservedObject var appState = AppState.shared
    private let accentColor = Color(red: 0.62, green: 0.94, blue: 0.54)

    var body: some View {
        Group {
            if let device = appState.device {
                VStack {
                    Spacer()

                    VStack(spacing: 28) {
                        VStack(spacing: 0) {
                            VStack(spacing: 18) {
                                ZStack {
                                    Circle()
                                        .fill(.white.opacity(0.04))
                                        .frame(width: 96, height: 96)

                                    Circle()
                                        .stroke(.white.opacity(0.08), lineWidth: 1)
                                        .frame(width: 96, height: 96)

                                    Image(systemName: "iphone")
                                        .font(.system(size: 38, weight: .light))
                                        .foregroundStyle(accentColor)
                                }
                                .padding(.top, 24)

                                VStack(spacing: 14) {
                                    Text(device.name)
                                        .font(.system(size: 26, weight: .bold))
                                        .multilineTextAlignment(.center)

                                    statusPill
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.bottom, 20)

                            Divider()
                                .overlay(.white.opacity(0.08))

                            HStack(spacing: 0) {
                                detailColumn(
                                    icon: connectionIcon,
                                    iconColor: accentColor,
                                    title: "Connection",
                                    value: connectionTypeText
                                )

                                Rectangle()
                                    .fill(.white.opacity(0.08))
                                    .frame(width: 1, height: 60)

                                detailColumn(
                                    icon: batteryIcon,
                                    iconColor: accentColor,
                                    title: "Battery",
                                    value: batteryText
                                )
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 22)
                        }
                        .frame(width: 520)
                        .applyGlassViewIfAvailable(cornerRadius: 34)

                        Button {
                            appState.disconnectDevice()
                        } label: {
                            Label("Disconnect", systemImage: "iphone.slash")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 320)
                                .padding(.vertical, 16)
                                .foregroundStyle(.red.opacity(0.95))
                        }
                        .buttonStyle(.plain)
                        .background(
                            Capsule()
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.02))
                                )
                        )
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectionStatusText: String {
        if appState.device?.ipAddress == "BLE" {
            return "Connected via BLE"
        }
        if appState.isConnectedOverLocalNetwork {
            return "Connected via Wi-Fi"
        }
        return "Connected via Tailscale"
    }

    private var connectionIcon: String {
        if appState.device?.ipAddress == "BLE" {
            return "logo.bluetooth"
        }
        return appState.isConnectedOverLocalNetwork ? "wifi" : "globe"
    }

    private var batteryText: String {
        let level = appState.status?.battery.level ?? 100
        return "\(level)%"
    }

    private var batteryIcon: String {
        let level = appState.status?.battery.level ?? 100
        let isCharging = appState.status?.battery.isCharging ?? false

        if isCharging {
            return "battery.100.bolt"
        }

        switch level {
        case 0...10: return "battery.0"
        case 11...25: return "battery.25"
        case 26...50: return "battery.50"
        case 51...75: return "battery.75"
        default: return "battery.100"
        }
    }

    private var connectionTypeText: String {
        if appState.device?.ipAddress == "BLE" {
            return "Bluetooth LE"
        }
        if appState.isConnectedOverLocalNetwork {
            return "Wi-Fi"
        }
        return "Tailscale"
    }

    private var statusPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accentColor)
                .frame(width: 12, height: 12)

            Text(connectionStatusText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(accentColor.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(accentColor.opacity(0.1), lineWidth: 1)
        )
    }

    private func detailColumn(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .contentShape(Rectangle())
    }
}

#Preview {
    BlankTabView()
}
