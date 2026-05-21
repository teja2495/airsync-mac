//
//  SharedImagePopupManager.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-21.
//

import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers
import Combine
import ImageIO

// MARK: - High Performance Downscaled Image Helpers

func getImageDimensions(at url: URL) -> CGSize? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else { return nil }
    if let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
       let height = properties[kCGImagePropertyPixelHeight] as? CGFloat {
        return CGSize(width: width, height: height)
    }
    return nil
}

func generateLowQualityThumbnail(at url: URL, maxPixelSize: CGFloat) -> NSImage? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cgImage, size: .zero)
}

// MARK: - Data Model

public struct SharedImageInfo: Identifiable, Equatable {
    public let id: UUID
    public let fileURL: URL
    public let addedAt: Date
    
    public init(id: UUID = UUID(), fileURL: URL, addedAt: Date = Date()) {
        self.id = id
        self.fileURL = fileURL
        self.addedAt = addedAt
    }
}

// MARK: - Custom AppKit Drag & Drop View Wrapper

struct FileDraggableView: NSViewRepresentable {
    let fileURL: URL
    let onDragStarted: () -> Void
    let onDragEnded: (Bool) -> Void
    
    func makeNSView(context: Context) -> DraggableNSView {
        let view = DraggableNSView()
        view.fileURL = fileURL
        view.onDragStarted = onDragStarted
        view.onDragEnded = onDragEnded
        return view
    }
    
    func updateNSView(_ nsView: DraggableNSView, context: Context) {
        nsView.fileURL = fileURL
    }
    
    class DraggableNSView: NSView, NSDraggingSource {
        var fileURL: URL?
        var onDragStarted: (() -> Void)?
        var onDragEnded: ((Bool) -> Void)?
        
        override func mouseDown(with event: NSEvent) {
            guard let fileURL = fileURL else { return }
            
            // Notify drag started on main thread
            DispatchQueue.main.async {
                self.onDragStarted?()
            }
            
            let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
            
            // Generate standard image icon preview for drag
            var dragImage = NSImage(contentsOf: fileURL) ?? NSWorkspace.shared.icon(forFile: fileURL.path)
            let maxDragSize = NSSize(width: 120, height: 120)
            if dragImage.size.width > maxDragSize.width || dragImage.size.height > maxDragSize.height {
                let ratio = dragImage.size.width / dragImage.size.height
                let newSize: NSSize
                if ratio > 1 {
                    newSize = NSSize(width: maxDragSize.width, height: maxDragSize.width / ratio)
                } else {
                    newSize = NSSize(width: maxDragSize.height * ratio, height: maxDragSize.height)
                }
                let resized = NSImage(size: newSize)
                resized.lockFocus()
                dragImage.draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1.0)
                resized.unlockFocus()
                dragImage = resized
            }
            
            draggingItem.setDraggingFrame(
                NSRect(x: event.locationInWindow.x - dragImage.size.width/2,
                       y: event.locationInWindow.y - dragImage.size.height/2,
                       width: dragImage.size.width,
                       height: dragImage.size.height),
                contents: dragImage
            )
            
            self.beginDraggingSession(with: [draggingItem], event: event, source: self)
        }
        
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            return .copy
        }
        
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            DispatchQueue.main.async { [weak self] in
                let success = operation.rawValue != 0
                self?.onDragEnded?(success)
            }
        }
    }
}

// MARK: - Manager

@MainActor
public class SharedImagePopupManager: NSObject, ObservableObject {
    public static let shared = SharedImagePopupManager()
    
    @Published public var activeImages: [SharedImageInfo] = []
    
    private var window: NSPanel?
    private var dismissTimer: Timer?
    
    private override init() {
        super.init()
    }
    
    public func show(fileURL: URL) {
        let dontDismiss = AppState.shared.dontDismissSharedImagePopups
        
        if !dontDismiss {
            // Dismiss existing popups by clearing the array
            self.activeImages.removeAll()
            self.cancelTimer()
        }
        
        // Append the new image card
        let newImage = SharedImageInfo(fileURL: fileURL)
        self.activeImages.append(newImage)
        
        // Setup timer if autoclose is active
        if !dontDismiss {
            self.resetTimer()
        }
        
        // Construct window if not already active
        if self.window == nil {
            let windowWidth: CGFloat = 300
            let windowHeight: CGFloat = 600 // High vertical canvas for stacking multiple cards
            
            let screen = NSScreen.main ?? NSScreen.screens.first
            let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            
            let onLeft = AppState.shared.popupSharedImagesOnLeft
            let targetX = onLeft ? screenFrame.minX : (screenFrame.maxX - windowWidth)
            let targetY = screenFrame.midY - (windowHeight / 2)
            
            let startFrame = NSRect(x: targetX, y: targetY, width: windowWidth, height: windowHeight)
            
            let panel = NSPanel(
                contentRect: startFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.alphaValue = 1.0
            
            let hostingView = NSHostingView(rootView: SharedImageOverlayView())
            hostingView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
            panel.contentView = hostingView
            
            self.window = panel
            panel.orderFrontRegardless()
        }
    }
    
    public func dismiss(imageID: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            self.activeImages.removeAll { $0.id == imageID }
        }
        
        // Tear down the window after removal animations play out if array is empty
        if self.activeImages.isEmpty {
            self.cancelTimer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self else { return }
                if self.activeImages.isEmpty {
                    self.window?.close()
                    self.window = nil
                }
            }
        }
    }
    
    public func dismissAll() {
        self.cancelTimer()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            self.activeImages.removeAll()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self else { return }
            if self.activeImages.isEmpty {
                self.window?.close()
                self.window = nil
            }
        }
    }
    
    public func updateWindowPosition() {
        guard let panel = self.window else { return }
        let windowWidth: CGFloat = 300
        let windowHeight: CGFloat = 600
        
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        
        let onLeft = AppState.shared.popupSharedImagesOnLeft
        let targetX = onLeft ? screenFrame.minX : (screenFrame.maxX - windowWidth)
        let targetY = screenFrame.midY - (windowHeight / 2)
        
        panel.setFrame(NSRect(x: targetX, y: targetY, width: windowWidth, height: windowHeight), display: true, animate: true)
    }
    
    private func resetTimer() {
        self.cancelTimer()
        self.dismissTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismissAll()
            }
        }
    }
    
    private func cancelTimer() {
        self.dismissTimer?.invalidate()
        self.dismissTimer = nil
    }
}

// MARK: - SwiftUI Main Overlay View

struct SharedImageOverlayView: View {
    @ObservedObject var manager = SharedImagePopupManager.shared
    @ObservedObject var appState = AppState.shared
    @State private var isDeckHovered = false
    
    var body: some View {
        ZStack {
            if !manager.activeImages.isEmpty {
                let images = manager.activeImages
                let count = images.count
                let onLeft = appState.popupSharedImagesOnLeft
                
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    SharedImageCardView(
                        image: image,
                        index: index,
                        totalCount: count,
                        isDeckHovered: isDeckHovered,
                        onLeft: onLeft,
                        onDismiss: {
                            manager.dismiss(imageID: image.id)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: onLeft ? .leading : .trailing).combined(with: .opacity),
                        removal: .move(edge: onLeft ? .leading : .trailing).combined(with: .opacity)
                    ))
                }
            }
        }
        .frame(width: 300, height: 600)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                self.isDeckHovered = hovering
            }
        }
    }
}

// MARK: - SwiftUI Individual Card View

struct SharedImageCardView: View {
    let image: SharedImageInfo
    let index: Int
    let totalCount: Int
    let isDeckHovered: Bool
    let onLeft: Bool
    let onDismiss: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var imageSize: CGSize = CGSize(width: 150, height: 150)
    @State private var thumbnailImage: NSImage? = nil
    @State private var failedToLoad = false
    
    var body: some View {
        HStack {
            if onLeft {
                cardContent
                Spacer()
            } else {
                Spacer()
                cardContent
            }
        }
        .frame(width: 300, height: 600)
        .zIndex(Double(index)) // Keep natural deck layering order
        .onAppear {
            // Fetch size and thumbnail off-main-thread to ensure UI stays buttery smooth (60+ FPS)
            DispatchQueue.global(qos: .userInteractive).async {
                let size = getImageDimensions(at: image.fileURL) ?? CGSize(width: 150, height: 150)
                let thumb = generateLowQualityThumbnail(at: image.fileURL, maxPixelSize: 300)
                
                DispatchQueue.main.async {
                    self.imageSize = size
                    if let thumb = thumb {
                        self.thumbnailImage = thumb
                    } else {
                        self.failedToLoad = true
                    }
                }
            }
        }
    }
    
    private var cardContent: some View {
        ZStack(alignment: .topTrailing) {
            // Card Render
            Group {
                if let thumbnail = thumbnailImage {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if failedToLoad {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 130, height: 130)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 130, height: 130)
                        .overlay(
                            ProgressView()
                                .controlSize(.small)
                        )
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
            )
            
            // Overlay custom file drag responder layer
            FileDraggableView(
                fileURL: image.fileURL,
                onDragStarted: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        self.isPressed = true
                    }
                },
                onDragEnded: { success in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                        self.isPressed = false
                    }
                    if success {
                        onDismiss()
                    }
                }
            )
            .frame(width: cardWidth, height: cardHeight)

            // Close button inside topmost corner, overlays on top of the drag view
            if isHovered {
                Button(action: {
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(8)
                .transition(.scale.combined(with: .opacity))
                .zIndex(10)
            }
        }
        .shadow(color: Color.black.opacity(isHovered ? 0.4 : 0.25), radius: isHovered ? 12 : 8, x: onLeft ? 4 : -4, y: 4)
        .rotationEffect(.degrees(rotation), anchor: onLeft ? .bottomLeading : .bottomTrailing)
        .offset(x: offsetX, y: offsetY)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onHover { hovering in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                self.isHovered = hovering
            }
        }
    }
    
    private var cardWidth: CGFloat {
        130
    }
    
    private var cardHeight: CGFloat {
        let ratio = imageSize.width / imageSize.height
        let clampedRatio = max(0.65, min(1.5, ratio))
        return 130 / clampedRatio
    }
    
    // Dynamic vertical "card hand" offsets
    private var baseY: CGFloat {
        let shiftIndex = totalCount - 1 - index
        return -CGFloat(shiftIndex) * 35.0
    }
    
    private var baseRotation: Double {
        let shiftIndex = totalCount - 1 - index
        let base = 8.0 + Double(shiftIndex) * 3.0
        return onLeft ? base : -base
    }
    
    private var rotation: Double {
        if isPressed {
            return 0.0 // Level when drag is holding
        } else if isHovered {
            return onLeft ? 14.0 : -14.0 // Hover tilts slightly more out
        } else {
            return baseRotation
        }
    }
    
    private var offsetX: CGFloat {
        let base: CGFloat
        if isPressed {
            base = 15 // Full center alignment on-screen
        } else if isHovered {
            base = 15 // Slides fully into viewport
        } else if isDeckHovered {
            // Slides partially out to show hand when deck is hovered
            let shiftIndex = totalCount - 1 - index
            base = 40 + CGFloat(shiftIndex) * 10
        } else {
            // Default peeking state
            let shiftIndex = totalCount - 1 - index
            base = 75 + CGFloat(shiftIndex) * 10
        }
        return onLeft ? -base : base
    }
    
    private var offsetY: CGFloat {
        if isPressed {
            return baseY
        } else if isHovered {
            return baseY - 20 // Pops upward relative to card stack!
        } else {
            return baseY
        }
    }
}
