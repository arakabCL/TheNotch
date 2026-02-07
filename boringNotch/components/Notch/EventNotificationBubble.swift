//
//  EventNotificationBubble.swift
//  boringNotch
//
//  A floating bubble notification that pops out from the notch area
//  to show upcoming calendar events
//

import SwiftUI
import AppKit

// MARK: - Event Notification Bubble View

struct EventNotificationBubbleView: View {
    let event: EventModel
    let timeUntilStart: String
    let isStartingNow: Bool
    let onDismiss: () -> Void
    
    @State private var isVisible: Bool = false
    @State private var isConfirmed: Bool = false
    @State private var checkScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.3
    
    var body: some View {
        HStack(spacing: 12) {
            // Event color indicator
            Circle()
                .fill(Color(nsColor: event.calendar.color))
                .frame(width: 10, height: 10)
                .shadow(color: Color(nsColor: event.calendar.color).opacity(0.6), radius: 4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Image(systemName: isStartingNow ? "bell.fill" : "clock")
                        .font(.system(size: 10))
                        .foregroundColor(isStartingNow ? .orange : .gray)
                    
                    Text(isStartingNow ? "Starting now!" : "In \(timeUntilStart)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isStartingNow ? .orange : .gray)
                }
            }
            
            Spacer(minLength: 8)
            
            // Time display
            if !isStartingNow {
                Text(formatEventTime(event.start))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Confirm button (satisfying checkbox)
            Button(action: confirmAndDismiss) {
                ZStack {
                    // Pulsing background
                    Circle()
                        .fill(Color(nsColor: event.calendar.color).opacity(pulseOpacity))
                        .frame(width: 36, height: 36)
                        .scaleEffect(isConfirmed ? 1.5 : 1.0)
                        .opacity(isConfirmed ? 0 : 1)
                    
                    // Button circle
                    Circle()
                        .fill(
                            isConfirmed 
                                ? Color.green
                                : Color.white.opacity(0.15)
                        )
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isConfirmed 
                                        ? Color.green 
                                        : Color.white.opacity(0.3),
                                    lineWidth: 2
                                )
                        )
                    
                    // Checkmark
                    Image(systemName: isConfirmed ? "checkmark" : "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isConfirmed ? .white : .white.opacity(0.5))
                        .scaleEffect(checkScale)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(checkScale)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: checkScale)
            .animation(.easeInOut(duration: 0.2), value: isConfirmed)
            .help("Got it!")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 240, maxWidth: 360)
        .background(
            ZStack {
                // Glassmorphism background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                
                // Gradient overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: event.calendar.color).opacity(0.15),
                                Color.black.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Border glow
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(nsColor: event.calendar.color).opacity(0.5),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
        .shadow(color: Color(nsColor: event.calendar.color).opacity(0.2), radius: 10)
        .scaleEffect(isVisible ? 1.0 : 0.5)
        .opacity(isVisible ? 1.0 : 0.0)
        .offset(y: isVisible ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isVisible = true
            }
            // Start subtle pulse animation
            startPulseAnimation()
        }
    }
    
    private func confirmAndDismiss() {
        // Satisfying animation sequence
        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
            checkScale = 1.3
            isConfirmed = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                checkScale = 1.0
            }
        }
        
        // Dismiss after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                isVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onDismiss()
            }
        }
    }
    
    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.6
        }
    }
    
    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Event Notification Window

class EventNotificationWindow: NSPanel {
    private var hostingView: NSHostingView<AnyView>?
    let targetScreen: NSScreen
    
    init(screen: NSScreen) {
        self.targetScreen = screen
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating + 1
        
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        
        // Position below notch area for this screen
        positionBelowNotch()
    }
    
    private func positionBelowNotch() {
        let notchCenterX = targetScreen.frame.midX
        let notchBottomY = targetScreen.frame.maxY - 40
        
        setFrame(
            NSRect(
                x: notchCenterX - 180,
                y: notchBottomY - 85,
                width: 360,
                height: 70
            ),
            display: false
        )
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    func show(event: EventModel, timeUntilStart: String, isStartingNow: Bool, onDismissAll: @escaping () -> Void) {
        let bubbleView = EventNotificationBubbleView(
            event: event,
            timeUntilStart: timeUntilStart,
            isStartingNow: isStartingNow,
            onDismiss: { [weak self] in
                onDismissAll()
            }
        )
        
        let hostingView = NSHostingView(rootView: AnyView(bubbleView))
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        
        contentView?.subviews.forEach { $0.removeFromSuperview() }
        contentView?.addSubview(hostingView)
        self.hostingView = hostingView
        
        // Reposition in case screen layout changed
        positionBelowNotch()
        
        alphaValue = 0
        orderFrontRegardless()
        
        // Animate in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }
    
    func dismiss() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

// MARK: - Event Notification Bubble Manager

@MainActor
class EventNotificationBubbleManager {
    static let shared = EventNotificationBubbleManager()
    
    private var windows: [NSScreen: EventNotificationWindow] = [:]
    private var currentEventId: String?
    
    private init() {}
    
    func showNotification(for event: EventModel, timeUntilStart: String, isStartingNow: Bool) {
        // Dismiss any existing notification first
        dismissAll()
        
        currentEventId = event.id
        
        // Create a window for each connected screen
        for screen in NSScreen.screens {
            let window = EventNotificationWindow(screen: screen)
            windows[screen] = window
            
            window.show(
                event: event,
                timeUntilStart: timeUntilStart,
                isStartingNow: isStartingNow,
                onDismissAll: { [weak self] in
                    self?.dismissAll()
                }
            )
        }
    }
    
    func dismissAll() {
        for (_, window) in windows {
            window.dismiss()
        }
        windows.removeAll()
        currentEventId = nil
    }
    
    func isShowingNotification(for eventId: String) -> Bool {
        return currentEventId == eventId
    }
}

