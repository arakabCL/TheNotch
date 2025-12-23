//
//  GoogleCalendarService.swift
//  boringNotch
//
//  Created for Google Calendar integration
//

import Foundation
import AppKit

/// Google Calendar API v3 client
@MainActor
class GoogleCalendarService: ObservableObject {
    static let shared = GoogleCalendarService()
    
    // MARK: - Published Properties
    @Published var events: [EventModel] = []
    @Published var calendars: [GoogleCalendar] = []
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    
    // MARK: - Private Properties
    private let baseURL = "https://www.googleapis.com/calendar/v3"
    private let authManager = GoogleAuthManager.shared
    private var refreshTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = 60 // seconds
    
    // MARK: - Computed Properties
    
    /// The event currently happening (if any)
    var currentEvent: EventModel? {
        let now = Date()
        return events.first { event in
            !event.isAllDay && event.start <= now && event.end > now
        }
    }
    
    /// The next upcoming event (after current time)
    var nextEvent: EventModel? {
        let now = Date()
        return events.first { event in
            !event.isAllDay && event.start > now
        }
    }
    
    // MARK: - Initialization
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start polling for calendar events
    func startPolling(interval: TimeInterval = 60) {
        pollingInterval = interval
        refreshTask?.cancel()
        
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshEvents()
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
        }
    }
    
    /// Stop polling
    func stopPolling() {
        refreshTask?.cancel()
        refreshTask = nil
    }
    
    /// Fetch today's events from Google Calendar
    func refreshEvents() async {
        guard authManager.isSignedIn else {
            events = []
            return
        }
        
        isLoading = true
        lastError = nil
        
        do {
            let accessToken = try await authManager.getValidAccessToken()
            
            // Get start of today and end of tomorrow (48 hours total)
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let endOfRange = calendar.date(byAdding: .day, value: 2, to: startOfDay)!
            
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            
            let timeMin = formatter.string(from: startOfDay)
            let timeMax = formatter.string(from: endOfRange)
            
            // Fetch events from primary calendar
            var components = URLComponents(string: "\(baseURL)/calendars/primary/events")!
            components.queryItems = [
                URLQueryItem(name: "timeMin", value: timeMin),
                URLQueryItem(name: "timeMax", value: timeMax),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "50")
            ]
            
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleCalendarError.invalidResponse
            }
            
            if httpResponse.statusCode == 401 {
                // Token expired, force refresh
                _ = try await authManager.getValidAccessToken()
                await refreshEvents()
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                throw GoogleCalendarError.apiError(statusCode: httpResponse.statusCode)
            }
            
            let eventsResponse = try JSONDecoder().decode(GoogleEventsResponse.self, from: data)
            
            // Convert to EventModel
            self.events = eventsResponse.items.compactMap { googleEvent -> EventModel? in
                return EventModel(from: googleEvent)
            }
            
        } catch {
            lastError = error.localizedDescription
            print("❌ Google Calendar Error: \(error)")
        }
        
        isLoading = false
    }
    
    /// Fetch list of calendars
    func fetchCalendars() async {
        guard authManager.isSignedIn else { return }
        
        do {
            let accessToken = try await authManager.getValidAccessToken()
            
            var request = URLRequest(url: URL(string: "\(baseURL)/users/me/calendarList")!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }
            
            let calendarList = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)
            self.calendars = calendarList.items
            
        } catch {
            print("❌ Failed to fetch calendars: \(error)")
        }
    }
    
    /// Update an existing event
    func updateEvent(id: String, summary: String, description: String?, location: String?, start: Date, end: Date, attendees: [String]) async throws {
        guard authManager.isSignedIn else { throw GoogleCalendarError.notAuthenticated }
        
        let accessToken = try await authManager.getValidAccessToken()
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        let patch = GoogleEventPatch(
            summary: summary,
            description: description,
            location: location,
            start: GoogleEventDateTime(date: nil, dateTime: formatter.string(from: start), timeZone: TimeZone.current.identifier),
            end: GoogleEventDateTime(date: nil, dateTime: formatter.string(from: end), timeZone: TimeZone.current.identifier),
            attendees: attendees.map { GoogleAttendee(email: $0, displayName: nil, responseStatus: nil, organizer: nil, self: nil) }
        )
        
        let url = URL(string: "\(baseURL)/calendars/primary/events/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(patch)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GoogleCalendarError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        // Refresh events after update
        await refreshEvents()
    }
    
    /// Reschedule an event to a new start time (preserving duration)
    func rescheduleEvent(_ event: EventModel, to newStart: Date) async throws {
        // Calculate the event duration and apply it to the new start time
        let duration = event.end.timeIntervalSince(event.start)
        let newEnd = newStart.addingTimeInterval(duration)
        
        // Keep all other event properties the same
        try await updateEvent(
            id: event.id,
            summary: event.title,
            description: event.notes,
            location: event.location,
            start: newStart,
            end: newEnd,
            attendees: event.participants.compactMap { $0.email }
        )
    }
}

// MARK: - Google Calendar API Models

struct GoogleEventsResponse: Codable {
    let kind: String
    let summary: String?
    let items: [GoogleEvent]
}

struct GoogleEventPatch: Codable {
    let summary: String?
    let description: String?
    let location: String?
    let start: GoogleEventDateTime?
    let end: GoogleEventDateTime?
    let attendees: [GoogleAttendee]?
}

struct GoogleEvent: Codable {
    let id: String
    let status: String?
    let htmlLink: String?
    let summary: String?
    let description: String?
    let location: String?
    let start: GoogleEventDateTime
    let end: GoogleEventDateTime
    let attendees: [GoogleAttendee]?
    let colorId: String?
    let recurringEventId: String?
    
    var isAllDay: Bool {
        start.date != nil && start.dateTime == nil
    }
}

struct GoogleEventDateTime: Codable {
    let date: String?       // For all-day events: "2024-12-22"
    let dateTime: String?   // For timed events: ISO 8601 format
    let timeZone: String?
    
    var asDate: Date? {
        if let dateTime = dateTime {
            return ISO8601DateFormatter().date(from: dateTime)
        } else if let date = date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: date)
        }
        return nil
    }
}

struct GoogleAttendee: Codable {
    let email: String
    let displayName: String?
    let responseStatus: String?
    let organizer: Bool?
    let `self`: Bool?
}

struct GoogleCalendarListResponse: Codable {
    let items: [GoogleCalendar]
}

struct GoogleCalendar: Codable, Identifiable {
    let id: String
    let summary: String
    let backgroundColor: String?
    let foregroundColor: String?
    let primary: Bool?
    let selected: Bool?
}

enum GoogleCalendarError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int)
    case notAuthenticated
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Google Calendar"
        case .apiError(let code): return "Google Calendar API error (code: \(code))"
        case .notAuthenticated: return "Not authenticated with Google"
        }
    }
}

// MARK: - EventModel Extension for Google Events

// Standalone function to avoid MainActor isolation issues
private func googleCalendarColorForId(_ colorId: String?) -> NSColor {
    // Google Calendar color IDs (1-11 for events)
    let colors: [String: NSColor] = [
        "1": NSColor(red: 0.47, green: 0.53, blue: 0.98, alpha: 1), // Lavender
        "2": NSColor(red: 0.20, green: 0.66, blue: 0.33, alpha: 1), // Sage
        "3": NSColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1), // Grape
        "4": NSColor(red: 0.91, green: 0.47, blue: 0.51, alpha: 1), // Flamingo
        "5": NSColor(red: 0.95, green: 0.72, blue: 0.00, alpha: 1), // Banana
        "6": NSColor(red: 0.95, green: 0.52, blue: 0.11, alpha: 1), // Tangerine
        "7": NSColor(red: 0.02, green: 0.66, blue: 0.84, alpha: 1), // Peacock
        "8": NSColor(red: 0.38, green: 0.38, blue: 0.38, alpha: 1), // Graphite
        "9": NSColor(red: 0.33, green: 0.47, blue: 0.98, alpha: 1), // Blueberry
        "10": NSColor(red: 0.03, green: 0.56, blue: 0.24, alpha: 1), // Basil
        "11": NSColor(red: 0.85, green: 0.25, blue: 0.20, alpha: 1)  // Tomato
    ]
    
    guard let id = colorId else {
        return NSColor.systemBlue
    }
    return colors[id] ?? NSColor.systemBlue
}

extension EventModel {
    init?(from googleEvent: GoogleEvent) {
        guard let startDate = googleEvent.start.asDate,
              let endDate = googleEvent.end.asDate else {
            return nil
        }
        
        // Parse color from colorId or use default
        let color = googleCalendarColorForId(googleEvent.colorId)
        
        // Map attendees
        let participants = googleEvent.attendees?.map { attendee -> Participant in
            Participant(
                name: attendee.displayName ?? attendee.email,
                email: attendee.email,
                status: AttendanceStatus(from: attendee.responseStatus),
                isOrganizer: attendee.organizer ?? false,
                isCurrentUser: attendee.`self` ?? false
            )
        } ?? []
        
        self.init(
            id: googleEvent.id,
            start: startDate,
            end: endDate,
            title: googleEvent.summary ?? "(No title)",
            location: googleEvent.location,
            notes: googleEvent.description,
            url: googleEvent.htmlLink.flatMap { URL(string: $0) },
            isAllDay: googleEvent.isAllDay,
            type: .event(.unknown),
            calendar: CalendarModel(
                id: "google-primary",
                account: "Google",
                title: "Google Calendar",
                color: color,
                isSubscribed: false,
                isReminder: false
            ),
            participants: participants,
            timeZone: googleEvent.start.timeZone.flatMap { TimeZone(identifier: $0) },
            hasRecurrenceRules: googleEvent.recurringEventId != nil,
            priority: nil
        )
    }
}

extension AttendanceStatus {
    init(from responseStatus: String?) {
        switch responseStatus {
        case "accepted": self = .accepted
        case "declined": self = .declined
        case "tentative": self = .maybe
        case "needsAction": self = .pending
        default: self = .unknown
        }
    }
}

