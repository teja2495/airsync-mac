//
//  HomeView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-27.
//

import SwiftUI
import AppKit

struct HomeView: View {
    @ObservedObject var appState = AppState.shared
    @State private var targetOpacity: Double = 0
    @AppStorage("hasPairedDeviceOnce") private var hasPairedDeviceOnce: Bool = false
    @State var showOnboarding = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var showsQRSidebar: Bool {
        appState.selectedTab == .qr
    }

    private var showsSettingsSidebar: Bool {
        appState.selectedTab == .settings
    }

    private var showsSidebar: Bool {
        showsQRSidebar || showsSettingsSidebar
    }
    
    private var needsOnboarding: Bool {
        // Show onboarding if either:
        // 1. User has never paired a device (first time user)
        // 2. User's lastOnboarding doesn't match current ForceUpdateKey
        return !hasPairedDeviceOnce || UserDefaults.standard.needsOnboarding
    }

    var body: some View {
        Group {
            if showsSidebar {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    if showsQRSidebar {
                        QRScannerSidebarView()
                    } else {
                        SettingsSidebarView()
                    }
                } detail: {
                    AppContentView()
                }
                .navigationSplitViewColumnWidth(min: 270, ideal: 270)
            } else {
                AppContentView()
            }
        }
        .navigationTitle("")
        .background(.background.opacity(appState.windowOpacity))
        .toolbarBackground(
            .clear,
            for: .windowToolbar
        )
        .toolbar(removing: .sidebarToggle)
        // Show onboarding sheet when needed
        .onAppear {
            if needsOnboarding {
                showOnboarding = true
                appState.isOnboardingActive = true
            }
            updateSidebarVisibility()
        }
        .onChange(of: appState.device) { _, _ in
            updateSidebarVisibility()
        }
        .onChange(of: appState.selectedTab) { _, _ in
            updateSidebarVisibility()
        }
        .onChange(of: columnVisibility) { _, newValue in
            if showsSidebar && newValue != .all {
                columnVisibility = .all
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .frame(minWidth: 640, minHeight: 420)
        }
        .onChange(of: showOnboarding) { oldValue, newValue in
            if !newValue {
                appState.isOnboardingActive = false
            }
        }
        .onChange(of: appState.isOnboardingActive) { oldValue, newValue in
            // Force view update to refresh window properties
        }
    }

    private func updateSidebarVisibility() {
        withAnimation(.easeInOut(duration: 0.3)) {
            columnVisibility = showsSidebar ? .all : .detailOnly
        }
    }
}

#Preview {
    HomeView()
}
