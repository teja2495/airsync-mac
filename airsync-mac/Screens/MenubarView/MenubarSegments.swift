//
//  MenubarSegments.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-07.
//

import SwiftUI

struct TopSegmentView: View {
    @ObservedObject var appState = AppState.shared
    let toolButtonSize: CGFloat
    let openAndFocusMainWindow: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: toolButtonSize, height: toolButtonSize)

                Menu {
                    #if DEBUG
                    Button("Crash", systemImage: "bolt.trianglebadge.exclamationmark") {
                        fatalError("Sentry Test Crash")
                    }
                    #endif
                    
                    Button("Quit", systemImage: "power") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Text("AirSync")
                        .font(.title2)
                }
                .menuStyle(.borderlessButton)
                .focusable(false)

                Spacer()

                ConnectionStatusPill()
                    .focusable(false)
                
                GlassButtonView(
                    label: "Open App",
                    systemImage: "arrow.up.forward.app",
                    iconOnly: true,
                    circleSize: toolButtonSize
                ) {
                    openAndFocusMainWindow()
                }
            }

            if appState.device != nil {
                HStack(spacing: 4) {
                    GlassButtonView(
                        label: "Send Clipboard",
                        systemImage: "clipboard",
                        iconOnly: true,
                        circleSize: toolButtonSize,
                        action: {
                            sendClipboard()
                        }
                    )
                    
                    GlassButtonView(
                        label: "QuickShare",
                        systemImage: "square.and.arrow.up",
                        iconOnly: true,
                        circleSize: toolButtonSize,
                        action: {
                            openQuickShare()
                        }
                    )

                    GlassButtonView(
                        label: L("menu.browseFiles"),
                        systemImage: "folder",
                        iconOnly: true,
                        circleSize: toolButtonSize,
                        action: {
                            WebDAVManager.shared.openInFinder()
                        }
                    )
                    
                    if appState.adbConnected {
                        GlassButtonView(
                            label: "Mirror",
                            systemImage: "apps.iphone",
                            iconOnly: true,
                            circleSize: toolButtonSize,
                            action: {
                                if appState.useNativeMirroringByDefault {
                                    appState.isNativeMirroring = true
                                } else {
                                    ADBConnector.startScrcpy(
                                        ip: appState.device?.ipAddress ?? "",
                                        port: appState.adbPort,
                                        deviceName: appState.device?.name ?? "My Phone"
                                    )
                                }
                            }
                        )
                        .contextMenu {
                            if appState.useNativeMirroringByDefault {
                                Button("scrcpy Mirror") {
                                    ADBConnector.startScrcpy(
                                        ip: appState.device?.ipAddress ?? "",
                                        port: appState.adbPort,
                                        deviceName: appState.device?.name ?? "My Phone"
                                    )
                                }
                            } else {
                                Button("Android Mirror") {
                                    appState.isNativeMirroring = true
                                }
                            }
                            
                            Button("Desktop Mode") {
                                ADBConnector.startScrcpy(
                                    ip: appState.device?.ipAddress ?? "",
                                    port: appState.adbPort,
                                    deviceName: appState.device?.name ?? "My Phone",
                                    desktop: true
                                )
                            }
                        }
                    }
                    
                    
                    GlassButtonView(
                        label: "DND",
                        systemImage: appState.silenceAllNotifications ? "bell.slash.fill" : "bell.badge",
                        iconOnly: true,
                        circleSize: toolButtonSize
                    ) {
                        appState.silenceAllNotifications.toggle()
                    }
                }
                
                if appState.adbConnected && !appState.recentApps.isEmpty {
                    RecentAppsGridView()
                }
            }
        }
        .padding(12)
        .segmentStyle()
    }
    
    private func sendClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let firstUrl = urls.first {
            DispatchQueue.global(qos: .userInitiated).async {
                WebSocketServer.shared.sendFile(url: firstUrl, isClipboard: true)
            }
        } else if let image = NSImage(pasteboard: pasteboard) {
            let tempDir = FileManager.default.temporaryDirectory
            let tempUrl = tempDir.appendingPathComponent("clipboard_image_\(Int(Date().timeIntervalSince1970)).png")
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                do {
                    try pngData.write(to: tempUrl)
                    DispatchQueue.global(qos: .userInitiated).async {
                        WebSocketServer.shared.sendFile(url: tempUrl, isClipboard: true)
                    }
                } catch {
                    print("[MenubarView] Failed to save clipboard image: \(error)")
                }
            }
        }
    }
    
    private func openQuickShare() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            let targetName = appState.device?.name
            QuickShareManager.shared.startDiscovery(autoTargetName: targetName)
            QuickShareManager.shared.transferURLs = panel.urls
            appState.showingQuickShareTransfer = true
        }
    }
}

struct MediaSegmentView: View {
    @ObservedObject var appState = AppState.shared
    
    var body: some View {
        if let status = appState.status {
            DeviceStatusView(showMediaToggle: true)
                .background {
                    let artwork = status.music?.albumArt ?? ""
                    if !appState.isMusicCardHidden,
                       !artwork.isEmpty,
                       let data = Data(base64Encoded: artwork),
                       let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .transition(.scale.combined(with: .opacity))
                .animation(.interpolatingSpring(stiffness: 200, damping: 30), value: appState.isMusicCardHidden)
        }
    }
}



struct DiscoverySegmentView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject private var udpDiscovery = UDPDiscoveryManager.shared
    @ObservedObject private var bleManager = BLECentralManager.shared

    var body: some View {
        let hasUdp = !udpDiscovery.discoveredDevices.isEmpty
        let hasBle = appState.isBLEEnabled && !bleManager.discoveredBLEDevices.isEmpty
        
        if appState.device == nil && (hasUdp || hasBle) {
            MenubarDeviceDiscoveryView()
                .padding(10)
                .segmentStyle()
        }
    }
}

struct NotificationsSegmentView: View {
    @ObservedObject var appState = AppState.shared
    
    var body: some View {
        if appState.device != nil && !appState.notifications.isEmpty {
            VStack(spacing: 6) {
                HStack {
                    Text("Notifications")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)

                MenuBarNotificationsListView()
            }
        }
    }
}

struct CallControlSegmentView: View {
    @ObservedObject var appState = AppState.shared
    
    var body: some View {
        if let callEvent = appState.activeCall {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    if let photoString = callEvent.contactPhoto,
                       !photoString.isEmpty,
                       let photoData = Data(base64Encoded: photoString, options: .ignoreUnknownCharacters),
                       let image = NSImage(data: photoData) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(callEvent.contactName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        
                        Text(callDirectionText(callEvent) + " • " + callStateText(callEvent))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                
                if appState.isPlus && appState.licenseCheck {
                    
                    HStack(spacing: 16) {
                        if callEvent.direction == .incoming {
                            if isCallAccepted(callEvent) {
                                GlassButtonView(
                                    label: L("menubar.call.end"),
                                    systemImage: "phone.down.fill",
                                    size: .large,
                                    action: {
                                        appState.sendCallAction(callEvent.eventId, action: "end")
                                    }
                                )
                                .foregroundStyle(.red)
                            } else {
                                GlassButtonView(
                                    label: L("menubar.call.accept"),
                                    systemImage: "phone.fill",
                                    size: .large,
                                    action: {
                                        appState.sendCallAction(callEvent.eventId, action: "accept")
                                    }
                                )
                                .foregroundStyle(.green)
                                
                                GlassButtonView(
                                    label: L("menubar.call.decline"),
                                    systemImage: "phone.down.fill",
                                    size: .large,
                                    action: {
                                        appState.sendCallAction(callEvent.eventId, action: "decline")
                                    }
                                )
                                .foregroundStyle(.red)
                            }
                        } else if callEvent.direction == .outgoing {
                            GlassButtonView(
                                label: L("menubar.call.end"),
                                systemImage: "phone.down.fill",
                                size: .large,
                                action: {
                                    appState.sendCallAction(callEvent.eventId, action: "end")
                                }
                            )
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .segmentStyle()
        }
    }
    
    private func callDirectionText(_ callEvent: CallEvent) -> String {
        switch callEvent.direction {
        case .incoming:
            return L("menubar.call.incomingCall")
        case .outgoing:
            return L("menubar.call.outgoingCall")
        }
    }
    
    private func callStateText(_ callEvent: CallEvent) -> String {
        switch callEvent.state {
        case .ringing:
            return L("menubar.call.ringing")
        case .offhook:
            return callEvent.direction == .incoming ? L("menubar.call.accepted") : L("menubar.call.ringing")
        case .accepted:
            return L("menubar.call.accepted")
        case .rejected:
            return "Rejected"
        case .ended:
            return "Ended"
        case .missed:
            return "Missed"
        case .idle:
            return "Idle"
        }
    }
    
    private func isCallAccepted(_ callEvent: CallEvent) -> Bool {
        callEvent.state == .offhook && callEvent.direction == .incoming
    }
}

