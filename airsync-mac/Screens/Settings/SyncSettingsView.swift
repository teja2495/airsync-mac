//
//  SyncSettingsView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-20.
//

import SwiftUI
import UserNotifications

struct SyncSettingsView: View {
    @ObservedObject var appState = AppState.shared
    @State private var showingPlusPopover = false
    @State private var showRemoteSheet = false

    @AppStorage("syncAndroidPlaybackSeekbar") private var syncAndroidPlaybackSeekbar = false

    // State for notification permissions
    @State private var notificationsGranted = false
    @State private var notificationsChecked = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Wireless / Wired ADB
                headerSection(title: "Connection & ADB", icon: "bolt.horizontal.circle")
                VStack(spacing: 12) {
                    ZStack {
                        HStack {
                            Label("Auto connect ADB", systemImage: "bolt.horizontal.circle")
                            Spacer()

                            if appState.adbConnected {
                                GlassButtonView(
                                    label: "Disconnect ADB",
                                    systemImage: "stop.circle",
                                    action: {
                                        ADBConnector.disconnectADB()
                                        appState.adbConnected = false
                                    }
                                )
                            } else {
                                GlassButtonView(
                                    label: appState.adbConnecting ? "Connecting..." : "Connect ADB",
                                    systemImage: appState.adbConnecting ? "hourglass" : "play.circle",
                                    action: {
                                        if !appState.adbConnecting {
                                            appState.adbConnectionResult = "" // Clear console
                                            appState.manualAdbConnectionPending = true
                                            WebSocketServer.shared.sendRefreshAdbPortsRequest()
                                            appState.adbConnectionResult = "Refreshing latest ADB ports from device..."
                                        }
                                    }
                                )
                                .disabled(
                                    appState.device == nil || appState.adbConnecting || !AppState.shared.isPlus
                                )
                            }

                            ZStack {
                                Toggle(
                                    "",
                                    isOn: $appState.adbEnabled
                                )
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(!AppState.shared.isPlus && AppState.shared.licenseCheck)
                            }
                            .frame(width: 55)
                        }

                        if !AppState.shared.isPlus && AppState.shared.licenseCheck {
                            HStack {
                                Spacer()
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        showingPlusPopover = true
                                    }
                                    .frame(width: 500)
                            }
                        }
                    }
                    .popover(isPresented: $showingPlusPopover, arrowEdge: .bottom) {
                        PlusFeaturePopover(message: "Wireless and Wired ADB features are available in AirSync+")
                            .onTapGesture {
                                showingPlusPopover = false
                            }
                    }

                    if let result = appState.adbConnectionResult {
                        VStack(alignment: .leading, spacing: 6) {
                            ExpandableLicenseSection(title: "ADB Console", content: "[" + (UserDefaults.standard.lastADBCommand ?? "[]") + "] " + result, copyable: true)
                        }
                    }

                    HStack {
                        ZStack {
                            HStack {
                                Label(L("settings.wiredAdb"), systemImage: "cable.connector")
                                Spacer()
                                Toggle("", isOn: $appState.wiredAdbEnabled)
                                    .toggleStyle(.switch)
                                    .disabled(!AppState.shared.isPlus && AppState.shared.licenseCheck)
                            }
                            
                            if !AppState.shared.isPlus && AppState.shared.licenseCheck {
                                HStack {
                                    Spacer()
                                    Rectangle()
                                        .fill(Color.clear)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            showingPlusPopover = true
                                        }
                                        .frame(width: 500)
                                }
                            }
                        }
                    }

                    HStack {
                        Label("Suppress failed messages", systemImage: "bell.slash")
                        Spacer()
                        Toggle("", isOn: $appState.suppressAdbFailureAlerts)
                            .toggleStyle(.switch)
                    }
                }
                .padding()
                .background(.background.opacity(0.3))
                .cornerRadius(12.0)

                // 2. Clipboard Sync
                headerSection(title: "Clipboard Sync", icon: "clipboard")
                VStack {
                    SettingsToggleView(name: "Sync clipboard", icon: "clipboard", isOn: $appState.isClipboardSyncEnabled)

                    HStack {
                        Label("Auto-open shared links", systemImage: "link")
                        Spacer()
                        Toggle("", isOn: $appState.autoOpenLinks)
                            .toggleStyle(.switch)
                            .disabled(!appState.isClipboardSyncEnabled)
                    }
                    .opacity(appState.isClipboardSyncEnabled ? 1.0 : 0.5)
                }
                .padding()
                .background(.background.opacity(0.3))
                .cornerRadius(12.0)

                // 3. Notifications
                headerSection(title: "Notifications Sync", icon: "bell.badge")
                VStack {
                    SettingsToggleView(name: "Sync notification dismissals", icon: "bell.badge", isOn: $appState.dismissNotif)

                    HStack {
                        Label("System Notifications", systemImage: "bell.badge")
                        Spacer()

                        if notificationsGranted {
                            Picker("", selection: $appState.notificationSound) {
                                Text("Default").tag("default")
                                ForEach(SystemSounds.availableSounds, id: \.self) { sound in
                                    Text(sound).tag(sound)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(minWidth: 100)

                            Button(action: {
                                SystemSounds.playSound(appState.notificationSound)
                            }) {
                                Image(systemName: "play.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Test notification sound")
                        } else {
                            GlassButtonView(
                                label: "Grant Permission",
                                systemImage: "bell.badge",
                                primary: true,
                                action: {
                                    openNotificationSettings()
                                }
                            )
                        }
                    }

                    SettingsToggleView(name: "Send now playing status", icon: "play.circle", isOn: $appState.sendNowPlayingStatus)

                    HStack {
                        Label("Sync Android playback seekbar", systemImage: "slider.horizontal.below.rectangle")
                        Button(action: {}) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Publishes Android media info (track, artist, artwork, seekbar position) to macOS Now Playing / boringNotch by playing a silent audio loop in the background.\n\nⓘ Multipoint Bluetooth users: this may cause your headphones to switch audio focus to the Mac, interrupting Android audio. Disable this toggle if that happens.")
                        Spacer()
                        Toggle("", isOn: $syncAndroidPlaybackSeekbar)
                            .toggleStyle(.switch)
                            .onChange(of: syncAndroidPlaybackSeekbar) { _, enabled in
                                if !enabled {
                                    NowPlayingPublisher.shared.clear()
                                }
                            }
                    }
                }
                .padding()
                .background(.background.opacity(0.3))
                .cornerRadius(12.0)
                .onAppear {
                    checkNotificationPermissions()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    checkNotificationPermissions()
                }

                // 4. Call Alerts
                headerSection(title: "Call Alerts", icon: "phone")
                VStack {
                    HStack {
                        Label("Call Alert", systemImage: "phone")
                        Spacer()

                        Picker("", selection: $appState.callNotificationMode) {
                            ForEach(CallNotificationMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(minWidth: 120)
                    }

                    SettingsToggleView(name: "Ring for calls", icon: "speaker.wave.3", isOn: $appState.ringForCalls)
                }
                .padding()
                .background(.background.opacity(0.3))
                .cornerRadius(12.0)

                // 5. Remote Accessibility Control
                headerSection(title: "Remote Accessibility", icon: "accessibility")
                VStack {
                    HStack {
                        Label("Remote Control Permission", systemImage: "accessibility")
                        Spacer()
                        GlassButtonView(label: "Configure", systemImage: "gearshape") {
                            showRemoteSheet = true
                        }
                    }
                }
                .padding()
                .background(.background.opacity(0.3))
                .cornerRadius(12.0)
                .sheet(isPresented: $showRemoteSheet) {
                    RemotePermissionView()
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func headerSection(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Notification Permission Helpers
    func checkNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsGranted = (settings.authorizationStatus == .authorized)
                notificationsChecked = true
            }
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}