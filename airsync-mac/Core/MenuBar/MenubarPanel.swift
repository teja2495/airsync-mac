//
//  MenubarPanel.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-07.
//

import AppKit
import SwiftUI

class MenubarPanel: NSPanel {
    init(contentRect: NSRect, rootView: some View) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.contentView?.wantsLayer = true

        let containerView = NSView(frame: contentRect)
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 24
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = NSColor(
            calibratedWhite: 0.14,
            alpha: 0.985
        ).cgColor
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.contentView = containerView
        self.becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool {
        return true
    }
}
