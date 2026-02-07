//
//  EventNotificationManager.swift
//  boringNotch
//
//  Monitors calendar events and shows notifications when events are starting
//

import Foundation
import Combine
import Defaults
import UserNotifications

@MainActor
class EventNotificationManager: ObservableObject {
    static let shared = EventNotificationManager()
    
    @Published var upcomingEvent: EventModel?
    @Published var showingNotification: Bool = false
    
    private var monitoringTask: Task<Void, Never>?
    private var notifiedEventIds: Set<String> = []
    
    // Computed property to get lead time from settings
    private var notificationLeadTime: TimeInterval {
        Defaults[.calendarNotificationLeadTime]
    }
    
    private init() {
        requestNotificationPermission()
    }
    
    // MARK: - Notification Permission
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error)")
            }
        }
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        stopMonitoring()
        
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkForUpcomingEvents()
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // Check every 30 seconds
            }
        }
    }
    
    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }
    
    private func checkForUpcomingEvents() async {
        guard Defaults[.useGoogleCalendar] else { return }
        guard Defaults[.enableCalendarNotifications] else { return }
        
        let events = GoogleCalendarService.shared.events
        let now = Date()
        
        for event in events {
            // Skip all-day events and already notified events
            guard !event.isAllDay else { continue }
            guard !notifiedEventIds.contains(event.id) else { continue }
            
            let timeUntilStart = event.start.timeIntervalSince(now)
            
            // Notify if event is starting within the lead time
            if timeUntilStart > 0 && timeUntilStart <= notificationLeadTime {
                await showEventNotification(event)
                notifiedEventIds.insert(event.id)
            }
            // Also notify when event is exactly starting (within a 30-second window)
            else if timeUntilStart <= 0 && timeUntilStart > -30 {
                await showEventStartingNow(event)
                notifiedEventIds.insert(event.id)
            }
        }
        
        // Clean up old notification IDs (events that have ended)
        notifiedEventIds = notifiedEventIds.filter { id in
            events.contains { $0.id == id && $0.end > now }
        }
    }
    
    // MARK: - Notifications
    
    private func showEventNotification(_ event: EventModel) async {
        // Show in the notch using sneak peek
        upcomingEvent = event
        showingNotification = true
        
        // Show notch sneak peek
        let timeString = formatTimeUntilStart(event.start)
        BoringViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .calendar,
            duration: 5.0,
            icon: "calendar",
            text: "📅 \(event.title) in \(timeString)"
        )
        
        // Also send system notification
        await sendSystemNotification(
            title: "Event Starting Soon",
            body: "\(event.title) starts in \(timeString)",
            event: event
        )
        
        // Auto-hide notification after 5 seconds
        try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
        showingNotification = false
    }
    
    private func showEventStartingNow(_ event: EventModel) async {
        upcomingEvent = event
        showingNotification = true
        
        // Show notch sneak peek
        BoringViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .calendar,
            duration: 5.0,
            icon: "calendar.badge.clock",
            text: "📅 \(event.title) - Starting Now!"
        )
        
        // Also send system notification
        await sendSystemNotification(
            title: "Event Starting Now",
            body: event.title,
            event: event
        )
        
        // Auto-hide notification after 5 seconds
        try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
        showingNotification = false
    }
    
    private func sendSystemNotification(title: String, body: String, event: EventModel) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Add event URL if available
        if let url = event.url {
            content.userInfo["eventURL"] = url.absoluteString
        }
        
        let request = UNNotificationRequest(
            identifier: "event-\(event.id)",
            content: content,
            trigger: nil // Show immediately
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("❌ Failed to schedule notification: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func formatTimeUntilStart(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        
        if seconds < 60 {
            return "less than a minute"
        } else {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
    }
}
