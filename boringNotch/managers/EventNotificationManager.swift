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

// Notification timing stages
private enum NotificationStage: String, CaseIterable {
    case earlyWarning = "25min"    // 25 minutes before
    case fiveMinutes = "5min"      // 5 minutes before
    case starting = "now"          // At event start
    
    var timeThreshold: TimeInterval {
        switch self {
        case .earlyWarning: return 25 * 60  // 25 minutes
        case .fiveMinutes: return 5 * 60    // 5 minutes
        case .starting: return 30           // 30 seconds (to account for timing)
        }
    }
    
    var isStartingNow: Bool {
        return self == .starting
    }
}

@MainActor
class EventNotificationManager: ObservableObject {
    static let shared = EventNotificationManager()
    
    @Published var upcomingEvent: EventModel?
    @Published var showingNotification: Bool = false
    
    private var monitoringTask: Task<Void, Never>?
    
    // Track which events have been notified at each stage
    // Key format: "eventId-stage"
    private var notifiedStages: Set<String> = []
    
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
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000) // Check every 15 seconds
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
            // Skip all-day events
            guard !event.isAllDay else { continue }
            
            let timeUntilStart = event.start.timeIntervalSince(now)
            
            // Check each notification stage
            for stage in NotificationStage.allCases {
                let stageKey = "\(event.id)-\(stage.rawValue)"
                
                // Skip if already notified for this stage
                guard !notifiedStages.contains(stageKey) else { continue }
                
                let shouldNotify: Bool
                switch stage {
                case .earlyWarning:
                    // Notify when within 25 minutes but more than 5 minutes away
                    shouldNotify = timeUntilStart > 0 
                        && timeUntilStart <= stage.timeThreshold 
                        && timeUntilStart > NotificationStage.fiveMinutes.timeThreshold
                case .fiveMinutes:
                    // Notify when within 5 minutes but more than 30 seconds away
                    shouldNotify = timeUntilStart > 0 
                        && timeUntilStart <= stage.timeThreshold 
                        && timeUntilStart > NotificationStage.starting.timeThreshold
                case .starting:
                    // Notify when event is starting (within 30 seconds of start, or just started)
                    shouldNotify = timeUntilStart <= stage.timeThreshold && timeUntilStart > -60
                }
                
                if shouldNotify {
                    await showEventNotification(event, stage: stage)
                    notifiedStages.insert(stageKey)
                    break // Only show one notification at a time per event
                }
            }
        }
        
        // Clean up old notification stage records (events that have ended)
        notifiedStages = notifiedStages.filter { stageKey in
            let eventId = stageKey.components(separatedBy: "-").first ?? ""
            return events.contains { $0.id == eventId && $0.end > now }
        }
    }
    
    // MARK: - Notifications
    
    private func showEventNotification(_ event: EventModel, stage: NotificationStage) async {
        upcomingEvent = event
        showingNotification = true
        
        let timeString = formatTimeUntilStart(event.start)
        
        // Show the floating bubble notification on all screens
        EventNotificationBubbleManager.shared.showNotification(
            for: event,
            timeUntilStart: timeString,
            isStartingNow: stage.isStartingNow
        )
        
        // Also send system notification
        let title = stage.isStartingNow ? "Event Starting Now" : "Upcoming Event"
        let body = stage.isStartingNow ? event.title : "\(event.title) in \(timeString)"
        
        await sendSystemNotification(
            title: title,
            body: body,
            event: event,
            stage: stage
        )
    }
    
    private func sendSystemNotification(title: String, body: String, event: EventModel, stage: NotificationStage) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Add event URL if available
        if let url = event.url {
            content.userInfo["eventURL"] = url.absoluteString
        }
        
        let request = UNNotificationRequest(
            identifier: "event-\(event.id)-\(stage.rawValue)",
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
    
    // Mark a notification as dismissed by user
    func markNotificationDismissed(eventId: String) {
        showingNotification = false
        upcomingEvent = nil
    }
}
