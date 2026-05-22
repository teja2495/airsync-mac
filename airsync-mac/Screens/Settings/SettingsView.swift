import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState = AppState.shared
    @AppStorage("SUEnableAutomaticChecks") private var automaticallyChecksForUpdates = true
    @AppStorage("SUAutomaticallyUpdate") private var automaticallyDownloadsUpdates = false

    @State private var deviceName: String = ""
    @State private var port: String = "6996"
    @State private var availableAdapters: [(name: String, address: String)] = []
    @State private var currentIPAddress: String = "N/A"
    @State private var showRemoteSheet = false
    @State private var showingPlusPopover = false

    var body: some View {
        Group {
            switch appState.selectedSettingsTab {
            case .myMac:
                myMacSettingsView
            case .sync:
                SyncSettingsView()
            case .mirroring:
                MirroringSettingsView()
            case .quickShare:
                quickShareSettingsView
            case .menubar:
                menubarSettingsView
            case .appearance:
                appearanceSettingsView
            case .airsyncPlus:
                airsyncPlusSettingsView
            }
        }
        .frame(minWidth: 300)
        .onAppear {
            if let device = appState.myDevice {
                deviceName = device.name
                port = String(device.port)
            } else {
                deviceName = UserDefaults.standard.string(forKey: "deviceName")
                ?? (Host.current().localizedName ?? "My Mac")
                port = UserDefaults.standard.string(forKey: "devicePort")
                ?? String(Defaults.serverPort)
            }
        }
    }

    // MARK: - Subviews

    private var myMacSettingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Device Info
                headerSection(title: "Device Name", icon: "iphone")
                VStack {
                    DeviceNameView(deviceName: $deviceName)
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                // 2. Server settings
                headerSection(title: "Server Configuration", icon: "server.rack")
                VStack(spacing: 12) {
                    HStack {
                        Label("Network Adapter", systemImage: "rectangle.connected.to.line.below")
                        Spacer()

                        Picker("", selection: Binding(
                            get: { appState.selectedNetworkAdapterName },
                            set: { appState.selectedNetworkAdapterName = $0 }
                        )) {
                            Text("Auto").tag(nil as String?)
                            ForEach(availableAdapters, id: \.name) { adapter in
                                Text("\(adapter.name) (\(adapter.address))").tag(Optional(adapter.name))
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    .onAppear {
                        availableAdapters = WebSocketServer.shared.getAvailableNetworkAdapters()
                        currentIPAddress = WebSocketServer.shared.getLocalIPAddress(adapterName: appState.selectedNetworkAdapterName) ?? "N/A"
                    }
                    .onChange(of: appState.selectedNetworkAdapterName) { _, _ in
                        currentIPAddress = WebSocketServer.shared.getLocalIPAddress(adapterName: appState.selectedNetworkAdapterName) ?? "N/A"
                        WebSocketServer.shared.stop()
                        if let port = UInt16(port) {
                            WebSocketServer.shared.start(port: port)
                        } else {
                            WebSocketServer.shared.start()
                        }
                        appState.shouldRefreshQR = true
                    }

                    ConnectionInfoText(
                        label: "IP Address",
                        icon: "wifi",
                        text: currentIPAddress,
                        activeIp: appState.activeMacIp
                    )

                    HStack {
                        Label("Server Port", systemImage: "rectangle.connected.to.line.below")
                            .padding(.trailing, 20)
                        Spacer()
                        TextField("Server Port", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: port) { oldValue, newValue in
                                port = newValue.filter { "0123456789".contains($0) }
                            }
                            .frame(maxWidth: 100)
                    }
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                HStack {
                    Spacer()
                    SaveAndRestartButton(
                        title: "Save and Restart the Server",
                        systemImage: "square.and.arrow.down.badge.checkmark",
                        deviceName: deviceName,
                        port: port,
                        version: appState.device?.version ?? "",
                        onSave: nil,
                        onRestart: nil
                    )
                }
            }
            .padding()
        }
    }

    private var quickShareSettingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(title: "Quick Share", icon: "laptopcomputer.and.arrow.down")
                VStack {
                    HStack {
                        Label(Localizer.shared.text("quickshare.title"), systemImage: "bolt.horizontal.circle")
                        Spacer()
                        Toggle("", isOn: $appState.quickShareEnabled)
                            .toggleStyle(.switch)
                    }

                    if appState.quickShareEnabled {
                        Text(String(format: Localizer.shared.text("quickshare.settings.discoverable"), QuickShareManager.shared.deviceName))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            Label(Localizer.shared.text("quickshare.settings.autoAccept"), systemImage: "checkmark.shield")
                            Spacer()
                            Toggle("", isOn: $appState.autoAcceptQuickShare)
                                .toggleStyle(.switch)
                        }

                        HStack {
                            Label(Localizer.shared.text("quickshare.settings.popupSharedImages"), systemImage: "doc.on.doc")
                            Spacer()
                            Toggle("", isOn: $appState.popupSharedImages)
                                .toggleStyle(.switch)
                        }

                        if appState.popupSharedImages {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label(Localizer.shared.text("quickshare.settings.maxPopups"), systemImage: "square.3.stack.3d")
                                        .padding(.leading, 12)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        Text("\(appState.sharedImagePopupsLimit)")
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                            .frame(width: 24, alignment: .trailing)
                                        Slider(
                                            value: Binding(
                                                get: { Double(appState.sharedImagePopupsLimit) },
                                                set: { appState.sharedImagePopupsLimit = Int(round($0)) }
                                            ),
                                            in: 1...10,
                                            step: 1
                                        )
                                        .frame(width: 120)
                                    }
                                }
                            }
                            .padding(.bottom, 4)

                            HStack {
                                Label(Localizer.shared.text("quickshare.settings.popupSide"), systemImage: "macwindow.and.ipad.arrow.left")
                                    .padding(.leading, 12)
                                Spacer()
                                Picker("", selection: $appState.popupSharedImagesOnLeft) {
                                    Text(Localizer.shared.text("quickshare.settings.side.left")).tag(true)
                                    Text(Localizer.shared.text("quickshare.settings.side.right")).tag(false)
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                headerSection(title: Localizer.shared.text("settings.fileAccess.title"), icon: "folder.badge.gearshape")
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ZStack {
                            HStack {
                                Label(Localizer.shared.text("settings.fileAccess.enabled"), systemImage: "externaldrive")
                                Spacer()
                                Toggle("", isOn: $appState.isFileAccessEnabled)
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
                    .popover(isPresented: $showingPlusPopover, arrowEdge: .bottom) {
                        PlusFeaturePopover(message: "File Access feature is available in AirSync+")
                            .onTapGesture {
                                showingPlusPopover = false
                            }
                    }

                    Text(Localizer.shared.text("settings.fileAccess.description"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)
            }
            .padding()
        }
    }

    private var menubarSettingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(title: L("settings.menubar"), icon: "menubar.arrow.up.rectangle")
                VStack(spacing: 12) {
                    HStack {
                        Label(L("settings.menubar.fontSize"), systemImage: "textformat.size")
                        Spacer()
                        Slider(
                            value: $appState.menubarFontSize,
                            in: 10...16,
                            step: 1
                        )
                        .frame(width: 150)
                        .controlSize(.small)
                        
                        Text("\(Int(appState.menubarFontSize))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)
                    }

                    Divider()

                    HStack {
                        Label(L("settings.menubar.showIcon"), systemImage: "iphone.gen3")
                        Spacer()
                        Toggle("", isOn: $appState.showMenubarIcon)
                            .toggleStyle(.switch)
                    }

                    HStack {
                        Label(L("settings.menubar.showText"), systemImage: "text.alignleft")
                        Spacer()
                        Toggle("", isOn: $appState.showMenubarText)
                            .toggleStyle(.switch)
                    }

                    if appState.showMenubarText {
                        VStack(spacing: 12) {
                            HStack {
                                Label(L("settings.menubar.maxLength"), systemImage: "arrow.left.and.right")
                                Spacer()
                                Slider(
                                    value: Binding(
                                        get: { Double(appState.menubarTextMaxLength) },
                                        set: { appState.menubarTextMaxLength = Int($0) }
                                    ),
                                    in: 10...80,
                                    step: 5
                                )
                                .frame(width: 150)
                                .controlSize(.small)
                            }

                            HStack {
                                Label(L("settings.menubar.showDeviceName"), systemImage: "iphone.gen3")
                                Spacer()
                                Toggle("", isOn: $appState.showMenubarDeviceName)
                                    .toggleStyle(.switch)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Divider()

                    HStack {
                        Label(L("settings.menubar.batteryStyle"), systemImage: "battery.100")
                        Spacer()
                        Picker("", selection: $appState.menubarBatteryStyle) {
                            Text(L("settings.menubar.batteryStyle.both")).tag("both")
                            Text(L("settings.menubar.batteryStyle.icon")).tag("icon")
                            Text(L("settings.menubar.batteryStyle.percentage")).tag("percentage")
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    HStack {
                        Label(L("settings.menubar.showMusic"), systemImage: "music.note")
                        Spacer()
                        Toggle("", isOn: $appState.showMenubarMusicIcon)
                            .toggleStyle(.switch)
                    }

                    if appState.showMenubarMusicIcon {
                        HStack {
                            Label(L("settings.menubar.showAlbumArt"), systemImage: "photo")
                            Spacer()
                            Toggle("", isOn: $appState.showMenubarAlbumArt)
                                .toggleStyle(.switch)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    HStack {
                        Label(L("settings.menubar.showPillStroke"), systemImage: "capsule")
                        Spacer()
                        Toggle("", isOn: $appState.showMenubarPillStroke)
                            .toggleStyle(.switch)
                    }


                    Divider()
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    HStack {
                        Label(L("settings.menubar.notifications"), systemImage: "bell")
                        Spacer()
                        Picker("", selection: $appState.menubarNotificationStyle) {
                            Text(L("settings.menubar.notifications.both")).tag("both")
                            Text(L("settings.menubar.notifications.count")).tag("count")
                            Text(L("settings.menubar.notifications.icons")).tag("icons")
                            Text(L("settings.menubar.notifications.none")).tag("none")
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    if appState.menubarNotificationStyle == "count" || appState.menubarNotificationStyle == "both" {

                        HStack {
                            Label(L("settings.menubar.badgeStyle"), systemImage: "bell.badge")
                            Spacer()
                            Picker("", selection: $appState.menubarUnreadBadgeStyle) {
                                Text(L("settings.menubar.badgeStyle.badge")).tag("badge")
                                Text(L("settings.menubar.badgeStyle.text")).tag("text")
                                Text(L("settings.menubar.badgeStyle.none")).tag("none")
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))

                        if appState.menubarUnreadBadgeStyle == "badge" {
                            HStack {
                                Label(L("settings.menubar.badgeColor"), systemImage: "paintpalette")
                                Spacer()
                                Picker("", selection: $appState.menubarUnreadBadgeColor) {
                                    Text(L("settings.menubar.color.accent")).tag("accent")
                                    Text(L("settings.menubar.color.red")).tag("red")
                                    Text(L("settings.menubar.color.orange")).tag("orange")
                                    Text(L("settings.menubar.color.blue")).tag("blue")
                                    Text(L("settings.menubar.color.green")).tag("green")
                                    Text(L("settings.menubar.color.purple")).tag("purple")
                                    Text(L("settings.menubar.color.gray")).tag("gray")
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)
            }
            .padding()
            .animation(.spring(), value: appState.showMenubarText)
            .animation(.spring(), value: appState.showMenubarIcon)
            .animation(.spring(), value: appState.menubarBatteryStyle)
            .animation(.spring(), value: appState.showMenubarMusicIcon)
            .animation(.spring(), value: appState.showMenubarAlbumArt)
            .animation(.spring(), value: appState.showMenubarPillStroke)
            .animation(.spring(), value: appState.menubarNotificationStyle)
            .animation(.spring(), value: appState.menubarUnreadBadgeStyle)
        }
    }

    private var appearanceSettingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Appearance
                headerSection(title: "Appearance", icon: "paintbrush")
                VStack(spacing: 12) {
                    HStack {
                        Label("Liquid Opacity", systemImage: "app.background.dotted")
                        Spacer()
                        Slider(
                            value: $appState.windowOpacity,
                            in: 0...1.0
                        )
                        .frame(width: 150)
                    }

                    HStack {
                        Label("Hide Dock Icon", systemImage: "dock.rectangle")
                        Spacer()
                        Toggle("", isOn: $appState.hideDockIcon)
                            .toggleStyle(.switch)
                    }

                    HStack {
                        Label("Always Open Window", systemImage: "macwindow")
                        Spacer()
                        Toggle("", isOn: $appState.alwaysOpenWindow)
                            .toggleStyle(.switch)
                    }
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                // 2. Application & Updates
                headerSection(title: "Application & Updates", icon: "arrow.clockwise")
                VStack(spacing: 12) {
                    SettingsToggleView(name: "Check for updates automatically", icon: "sparkles", isOn: $automaticallyChecksForUpdates)
                    SettingsToggleView(name: "Download updates automatically", icon: "arrow.down.circle", isOn: $automaticallyDownloadsUpdates)
                    SettingsToggleView(name: "Crash reporting", icon: "ant", isOn: $appState.isCrashReportingEnabled)
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)
            }
            .padding()
        }
    }

    private var airsyncPlusSettingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(title: "AirSync+", icon: "plus.diamond.fill")
                SettingsPlusView()
                    .padding()
                    .glassBoxIfAvailable(radius: 18)
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
}
