//
//  CalendarLiveActivity.swift
//  boringNotch
//
//  Created for Google Calendar integration - Closed notch preview
//

import SwiftUI
import Defaults

/// Compact calendar event preview shown when the notch is closed
struct CalendarLiveActivity: View {
    @ObservedObject var calendarService = GoogleCalendarService.shared
    @EnvironmentObject var vm: BoringViewModel
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    var body: some View {
        HStack(spacing: 8) {
            // Calendar icon with event color
            if let event = calendarService.currentEvent ?? calendarService.nextEvent {
                Circle()
                    .fill(Color(nsColor: event.calendar.color))
                    .frame(width: 8, height: 8)
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            
            // Event info
            if let current = calendarService.currentEvent {
                // Currently in an event
                currentEventView(current)
            } else if let next = calendarService.nextEvent {
                // Show next upcoming event
                nextEventView(next)
            } else {
                // No events
                Text("No upcoming events")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
    @ViewBuilder
    private func currentEventView(_ event: EventModel) -> some View {
        HStack(spacing: 4) {
            Text("Now:")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.red)
            
            Text(event.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            
            // Time remaining
            Text(timeRemaining(until: event.end))
                .font(.system(size: 9))
                .foregroundColor(.gray)
        }
    }
    
    @ViewBuilder
    private func nextEventView(_ event: EventModel) -> some View {
        HStack(spacing: 4) {
            Text(dateFormatter.string(from: event.start))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.gray)
            
            Text(event.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
    
    private func timeRemaining(until date: Date) -> String {
        let interval = date.timeIntervalSince(Date())
        if interval <= 0 { return "" }
        
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(minutes)m left"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m left"
        }
    }
}
