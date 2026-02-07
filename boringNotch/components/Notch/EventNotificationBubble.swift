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
    @State private var isAppearing: Bool = true
    
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
            
            Spacer(minLength: 0)
            
            // Time display
            if !isStartingNow {
                Text(formatEventTime(event.start))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 200, maxWidth: 320)
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
    private var dismissTask: Task<Void, Never>?
    private var hostingView: NSHostingView<AnyView>?
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
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
        
        // Position below notch area
        if let screen = NSScreen.main {
            let notchCenterX = screen.frame.midX
            let notchBottomY = screen.frame.maxY - 50 // Below the notch
            
            setFrame(
                NSRect(
                    x: notchCenterX - 160,
                    y: notchBottomY - 70,
                    width: 320,
                    height: 60
                ),
                display: false
            )
        }
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    func show(event: EventModel, timeUntilStart: String, isStartingNow: Bool, duration: TimeInterval = 5.0) {
        dismissTask?.cancel()
        
        let bubbleView = EventNotificationBubbleView(
            event: event,
            timeUntilStart: timeUntilStart,
            isStartingNow: isStartingNow,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        
        let hostingView = NSHostingView(rootView: AnyView(bubbleView))
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        
        contentView?.subviews.forEach { $0.removeFromSuperview() }
        contentView?.addSubview(hostingView)
        self.hostingView = hostingView
        
        // Position centered below notch
        if let screen = NSScreen.main {
            let notchCenterX = screen.frame.midX
            let notchBottomY = screen.frame.maxY - 40
            
            setFrame(
                NSRect(
                    x: notchCenterX - 160,
                    y: notchBottomY - 80,
                    width: 320,
                    height: 70
                ),
                display: true
            )
        }
        
        alphaValue = 0
        orderFrontRegardless()
        
        // Animate in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
        
        // Schedule dismiss
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            self.dismiss()
        }
    }
    
    func dismiss() {
        dismissTask?.cancel()
        
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
    
    private var window: EventNotificationWindow?
    
    private init() {}
    
    func showNotification(for event: EventModel, timeUntilStart: String, isStartingNow: Bool, duration: TimeInterval = 5.0) {
        if window == nil {
            window = EventNotificationWindow()
        }
        
        window?.show(
            event: event,
            timeUntilStart: timeUntilStart,
            isStartingNow: isStartingNow,
            duration: duration
        )
    }
    
    func dismiss() {
        window?.dismiss()
    }
}
