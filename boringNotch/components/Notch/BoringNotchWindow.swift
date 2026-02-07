//
//  BoringNotchWindow.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 06/08/24.
//

import Cocoa

class BoringNotchWindow: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
        
        // Configure the content view's layer for optimal 120Hz rendering
        if let contentView = self.contentView {
            contentView.wantsLayer = true
            if let layer = contentView.layer {
                // Enable asynchronous drawing for smoother animation
                layer.drawsAsynchronously = true
                // Allow continuous updates for smooth 120Hz animation
                layer.allowsEdgeAntialiasing = true
            }
        }
    }
    
    override var canBecomeKey: Bool {
        false
    }
    
    override var canBecomeMain: Bool {
        false
    }
}
