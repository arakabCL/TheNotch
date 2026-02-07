//
//  HorizontalTimelineView.swift
//  boringNotch
//
//  Horizontal timeline view for displaying Google Calendar events in the notch
//

import SwiftUI
import Defaults

struct HorizontalTimelineView: View {
    @ObservedObject var calendarService = GoogleCalendarService.shared
    @ObservedObject var authManager = GoogleAuthManager.shared
    @State private var currentTime = Date()
    
    // Timeline configuration
    private let hourWidth: CGFloat = 100
    private let timelineHeight: CGFloat = 100
    private let startHour: Int = 0   // Start at midnight
    private let endHour: Int = 48    // Show 48 hours (today + tomorrow)
    
    @State private var selectedEvent: EventModel?
    @State private var isShowingDetail = false
    
    private var totalHours: Int { endHour - startHour }
    private var timelineWidth: CGFloat { CGFloat(totalHours) * hourWidth }
    
    var body: some View {
        Group {
            if authManager.isSignedIn {
                signedInContent
            } else {
                signInPrompt
            }
        }
        .onAppear {
            startTimeUpdates()
            // Start polling if signed in (will be a no-op if already polling from app launch)
            if authManager.isSignedIn {
                calendarService.startPolling(interval: Defaults[.googleCalendarPollingInterval])
            }
        }
        // Don't stop polling on disappear - keep updating in background
        .popover(isPresented: $isShowingDetail) {
            if let event = selectedEvent {
                EventEditView(event: event)
                    .onAppear {
                        print("📅 Showing Edit Popover for: \(event.title)")
                        SharingStateManager.shared.preventNotchClose = true
                    }
                    .onDisappear {
                        SharingStateManager.shared.preventNotchClose = false
                    }
            }
        }
        .onChange(of: isShowingDetail) { _, newValue in
            if !newValue {
                SharingStateManager.shared.preventNotchClose = false
            }
        }
    }
    
    // MARK: - Signed In Content
    
    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerView
            timelineScrollView
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                    .foregroundColor(.white)
                Text(Date().formatted(.dateTime.month().day()))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if calendarService.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 20, height: 20)
            } else {
                Text("\(calendarService.events.count) events")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 8)
    }
    
    private var timelineScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Hour markers
                    hourMarkersView
                    
                    // Events
                    eventsView
                    
                    // Current time indicator
                    currentTimeIndicator
                }
                .frame(width: timelineWidth, height: timelineHeight)
            }
            .onAppear {
                scrollToCurrentTime(proxy: proxy)
            }
        }
        .frame(height: timelineHeight)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var hourMarkersView: some View {
        HStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatHour(hour))
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1)
                }
                .frame(width: hourWidth, alignment: .leading)
                .id("hour-\(hour)")
            }
        }
    }
    
    private var eventsView: some View {
        ForEach(calendarService.events) { event in
            if !event.isAllDay {
                EventBlockView(
                    event: event,
                    startHour: startHour,
                    hourWidth: hourWidth,
                    onTap: {
                        print("📅 Event Tapped: \(event.title)")
                        selectedEvent = event
                        isShowingDetail = true
                    },
                    onReschedule: { event, newTime in
                        print("📅 Rescheduling \(event.title) to \(newTime)")
                        do {
                            try await calendarService.rescheduleEvent(event, to: newTime)
                            print("✅ Event rescheduled successfully")
                        } catch {
                            print("❌ Failed to reschedule event: \(error)")
                        }
                    },
                    onResize: { event, newSteps in
                        print("📅 Resizing \(event.title) by \(newSteps) steps")
                        do {
                            // Calculate new end time based on 15 minute steps
                            // each step is 15 minutes = 900 seconds
                            let durationChange = TimeInterval(newSteps * 15 * 60)
                            let newEnd = event.end.addingTimeInterval(durationChange)
                            
                            // Ensure duration is at least 15 minutes
                            guard newEnd.timeIntervalSince(event.start) >= 15 * 60 else { return }
                            
                            try await calendarService.updateEvent(
                                id: event.id,
                                summary: event.title,
                                description: event.notes,
                                location: event.location,
                                start: event.start,
                                end: newEnd,
                                attendees: event.participants.compactMap { $0.email },
                                colorId: event.colorId
                            )
                            print("✅ Event resized successfully")
                        } catch {
                            print("❌ Failed to resize event: \(error)")
                        }
                    }
                )
            }
        }
    }
    
    private var currentTimeIndicator: some View {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: currentTime)
        let minute = calendar.component(.minute, from: currentTime)
        
        let hourOffset = CGFloat(hour - startHour)
        let minuteOffset = CGFloat(minute) / 60.0
        let xPosition = (hourOffset + minuteOffset) * hourWidth
        
        return Group {
            if hour >= startHour && hour < endHour {
                VStack(spacing: 0) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2)
                }
                .offset(x: xPosition - 4)
            }
        }
    }
    
    // MARK: - Sign In Prompt
    
    private var signInPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.largeTitle)
                .foregroundColor(.gray)
            
            Text("Connect Google Calendar")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("See your schedule at a glance")
                .font(.caption)
                .foregroundColor(.gray)
            
            Button(action: {
                Task {
                    await authManager.signIn()
                    if authManager.isSignedIn {
                        calendarService.startPolling()
                    }
                }
            }) {
                HStack {
                    Image(systemName: "person.badge.plus")
                    Text("Sign in with Google")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            
            if authManager.isAuthenticating {
                ProgressView()
                    .scaleEffect(0.8)
            }
            
            if let error = authManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private func formatHour(_ hour: Int) -> String {
        let displayHour = hour % 24
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: displayHour, minute: 0, second: 0, of: Date())!
        let hourString = formatter.string(from: date).lowercased()
        // Add "+" indicator for next day hours
        if hour >= 24 {
            return "+\(hourString)"
        }
        return hourString
    }
    
    private func scrollToCurrentTime(proxy: ScrollViewProxy) {
        let currentHour = Calendar.current.component(.hour, from: Date())
        if currentHour >= startHour && currentHour < endHour {
            proxy.scrollTo("hour-\(max(startHour, currentHour - 1))", anchor: .leading)
        }
    }
    
    private func startTimeUpdates() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            currentTime = Date()
        }
    }
}

// MARK: - Event Block View

struct EventBlockView: View {
    let event: EventModel
    let startHour: Int
    let hourWidth: CGFloat
    let onTap: () -> Void
    var onReschedule: ((EventModel, Date) async -> Void)?
    var onResize: ((EventModel, Int) async -> Void)?
    
    @State private var isHovering = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var previewTime: Date?
    @State private var isRescheduling = false
    
    // Resizing state
    @State private var isResizing = false
    @State private var resizeOffset: CGFloat = 0
    @State private var resizeSteps: Int = 0 // 1 step = 15 mins
    
    // 15-minute increment in pixels (hourWidth / 4)
    private var snapIncrement: CGFloat { hourWidth / 4.0 }
    
    private var eventColor: Color {
        Color(nsColor: event.calendar.color)
    }
    
    @State private var isHoveringResizeHandle = false

    var body: some View {
        let position = calculatePosition()
        // width + resize adjustment
        let currentWidth = max(20, position.width + (isResizing ? resizeOffset : 0))
        
        ZStack(alignment: .top) {
            // Main event block
            eventBlock(width: currentWidth)
                .frame(width: currentWidth, height: 50)
                .offset(x: isDragging ? dragOffset : 0)
                .opacity(isDragging ? 0.85 : 1.0)
                .scaleEffect(isDragging ? 1.02 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isDragging)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: resizeOffset)
            
            // Time preview badge (shows during drag)
            if isDragging, let preview = previewTime {
                timePreviewBadge(for: preview)
                    .offset(x: dragOffset, y: -18)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } 
            // Duration preview (shows during resize)
            else if isResizing {
                durationPreviewBadge(currentWidth: currentWidth)
                    .offset(x: currentWidth / 2, y: -18)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            
            // Rescheduling / Resizing indicator
            if isRescheduling {
                ProgressView()
                    .scaleEffect(0.5)
                    .offset(x: position.width / 2, y: 25)
            }
        }
        // Only the view itself handles taps; the background is transparent
        .onTapGesture {
            if !isDragging && !isRescheduling && !isResizing {
                onTap()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    // STRICT CHECK: Cannot move if resizing OR over resize handle
                    guard !isRescheduling && !isResizing && !isHoveringResizeHandle else { return }
                    
                    if !isDragging {
                        isDragging = true
                        SharingStateManager.shared.preventNotchClose = true
                    }
                    
                    // Snap to 15-minute increments
                    let snappedOffset = round(value.translation.width / snapIncrement) * snapIncrement
                    dragOffset = snappedOffset
                    
                    // Calculate preview time
                    previewTime = calculateNewStartTime(from: snappedOffset)
                }
                .onEnded { value in
                    guard isDragging else { return }
                    
                    let snappedOffset = round(value.translation.width / snapIncrement) * snapIncrement
                    
                    // Only save if there's a meaningful change (at least 15 minutes)
                    if abs(snappedOffset) >= snapIncrement, let newTime = calculateNewStartTime(from: snappedOffset) {
                        commitReschedule(to: newTime)
                    } else {
                        cancelDrag()
                    }
                }
        )
        // Separate resize capability
        .overlay(
            resizeHandle
                .offset(x: (currentWidth / 2) - 4 + (isDragging ? dragOffset : 0))
                .opacity((isHovering || isResizing) && !isDragging && !isRescheduling ? 1 : 0),
            alignment: .center // We center it, but calculate manual x offset
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .offset(x: position.x + (isResizing ? resizeOffset / 2 : 0), y: 20)
    }
    
    private func eventBlock(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(eventColor.opacity(isHovering || isDragging || isResizing ? 0.9 : 0.7))
            
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isDragging || isResizing ? Color.white : eventColor, lineWidth: isDragging || isResizing ? 2 : 1)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                // Show preview time during drag, otherwise show original time
                if isDragging, let preview = previewTime {
                    Text(formatTime(preview))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.yellow)
                } else if isResizing {
                    // Show updated duration/end time
                    let durationChange = TimeInterval(resizeSteps * 15 * 60)
                    let newEnd = event.end.addingTimeInterval(durationChange)
                    Text("\(formatTime(event.start)) - \(formatTime(newEnd))")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.yellow)
                } else {
                    Text(formatTime(event.start))
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(width: width, alignment: .leading)
        }
        .help(eventTooltip)
    }
    
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.white.opacity(0.01)) // specific hit area
            .frame(width: 14, height: 40)
            .overlay(
                // Visual handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 4, height: 24)
                    .shadow(radius: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHoveringResizeHandle = hovering
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if !isResizing {
                            isResizing = true
                            SharingStateManager.shared.preventNotchClose = true
                        }
                        
                        // Calculate steps (15 mins) from drag
                        // Since we are dragging the right edge, translation directly maps to width change
                        let rawSteps = round(value.translation.width / snapIncrement)
                        resizeSteps = Int(rawSteps)
                        
                        // Don't allow duration less than 15 mins
                        let currentDurationSteps = Int(event.end.timeIntervalSince(event.start) / (15 * 60))
                        if currentDurationSteps + resizeSteps < 1 {
                            resizeSteps = 1 - currentDurationSteps
                        }
                        
                        resizeOffset = CGFloat(resizeSteps) * snapIncrement
                    }
                    .onEnded { value in
                        guard isResizing else { return }
                        
                        if resizeSteps != 0 {
                            commitResize()
                        } else {
                            cancelResize()
                        }
                    }
            )
            // .cursor(.resizeRight) - Removed as it caused build error
    }
    
    private func timePreviewBadge(for time: Date) -> some View {
        Text(formatTime(time))
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.yellow)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            )
    }
    
    private func durationPreviewBadge(currentWidth: CGFloat) -> some View {
        let durationChange = TimeInterval(resizeSteps * 15 * 60)
        let newEnd = event.end.addingTimeInterval(durationChange)
        let totalDurationMinutes = Int(newEnd.timeIntervalSince(event.start) / 60)
        let hours = totalDurationMinutes / 60
        let minutes = totalDurationMinutes % 60
        
        var durationText = ""
        if hours > 0 { durationText += "\(hours)h " }
        if minutes > 0 { durationText += "\(minutes)m" }
        
        return Text("\(durationText) (\(formatTime(newEnd)))")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.yellow)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            )
    }
    
    private var eventTooltip: String {
        var tooltip = event.title
        tooltip += "\n\(formatTime(event.start)) - \(formatTime(event.end))"
        if let location = event.location, !location.isEmpty {
            tooltip += "\n📍 \(location)"
        }
        if onReschedule != nil {
            tooltip += "\n\nDrag to reschedule\nDrag right edge to resize"
        }
        return tooltip
    }
    
    // MARK: - Position Calculations
    
    private func calculatePosition() -> (x: CGFloat, width: CGFloat) {
        let calendar = Calendar.current
        
        // Get today's start of day for reference
        let today = calendar.startOfDay(for: Date())
        let eventDay = calendar.startOfDay(for: event.start)
        
        // Calculate day offset (0 for today, 1 for tomorrow, etc.)
        let dayOffset = calendar.dateComponents([.day], from: today, to: eventDay).day ?? 0
        
        let startComponents = calendar.dateComponents([.hour, .minute], from: event.start)
        
        // Add 24 hours for each day offset
        let adjustedHour = (startComponents.hour ?? 0) + (dayOffset * 24)
        
        let startHourOffset = CGFloat(adjustedHour - startHour)
        let startMinuteOffset = CGFloat(startComponents.minute ?? 0) / 60.0
        let x = (startHourOffset + startMinuteOffset) * hourWidth
        
        let durationHours = event.end.timeIntervalSince(event.start) / 3600.0
        let width = CGFloat(durationHours) * hourWidth
        
        return (x: max(0, x), width: width)
    }
    
    private func calculateNewStartTime(from offset: CGFloat) -> Date? {
        // Convert pixel offset to time offset
        // hourWidth = 1 hour, so offset / hourWidth = hours
        let hoursOffset = offset / hourWidth
        let secondsOffset = hoursOffset * 3600
        
        let newStart = event.start.addingTimeInterval(secondsOffset)
        
        // Snap to 15-minute intervals
        return snapToFifteenMinutes(newStart)
    }
    
    private func snapToFifteenMinutes(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        
        guard let minute = components.minute else { return date }
        
        // Round to nearest 15 minutes
        let snappedMinute = (minute / 15) * 15
        
        var newComponents = components
        newComponents.minute = snappedMinute
        newComponents.second = 0
        
        return calendar.date(from: newComponents) ?? date
    }
    
    // MARK: - Actions
    
    private func commitReschedule(to newTime: Date) {
        guard let onReschedule = onReschedule else {
            cancelDrag()
            return
        }
        
        isRescheduling = true
        
        Task {
            await onReschedule(event, newTime)
            
            await MainActor.run {
                isRescheduling = false
                isDragging = false
                dragOffset = 0
                previewTime = nil
                SharingStateManager.shared.preventNotchClose = false
            }
        }
    }
    
    private func cancelDrag() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = 0
        }
        isDragging = false
        previewTime = nil
        SharingStateManager.shared.preventNotchClose = false
    }
    
    private func commitResize() {
        guard let onResize = onResize else {
            cancelResize()
            return
        }
        
        isRescheduling = true // Re-use this flag for spinner
        
        Task {
            await onResize(event, resizeSteps)
            
            await MainActor.run {
                isRescheduling = false
                isResizing = false
                resizeOffset = 0
                resizeSteps = 0
                SharingStateManager.shared.preventNotchClose = false
            }
        }
    }
    
    private func cancelResize() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            resizeOffset = 0
        }
        isResizing = false
        resizeSteps = 0
        SharingStateManager.shared.preventNotchClose = false
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Event Edit View

struct EventEditView: View {
    let event: EventModel
    @Environment(\.dismiss) var dismiss
    
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var location: String
    @State private var notes: String
    @State private var guests: [String]
    @State private var selectedColorId: String?
    @State private var newGuestEmail: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    
    init(event: EventModel) {
        self.event = event
        _title = State(initialValue: event.title)
        _start = State(initialValue: event.start)
        _end = State(initialValue: event.end)
        _location = State(initialValue: event.location ?? "")
        _notes = State(initialValue: event.notes ?? "")
        // Map participants back to emails for editing
        _guests = State(initialValue: event.participants.compactMap { $0.email })
        _selectedColorId = State(initialValue: event.colorId)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Edit Event")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 20, height: 20)
                }
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Title
                    TextField("Event Title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    
                    // Date and Time
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.gray)
                            DatePicker("Starts", selection: $start)
                                .labelsHidden()
                            Text("→")
                                .foregroundColor(.gray)
                            DatePicker("Ends", selection: $end)
                                .labelsHidden()
                        }
                    }
                    
                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "paintpalette")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            Text("Color")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(GoogleCalendarColor.allColors) { colorOption in
                                Button(action: {
                                    selectedColorId = colorOption.id
                                }) {
                                    Circle()
                                        .fill(Color(nsColor: colorOption.color))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white, lineWidth: selectedColorId == colorOption.id ? 2 : 0)
                                        )
                                        .overlay(
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                                .opacity(selectedColorId == colorOption.id ? 1 : 0)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help(colorOption.name)
                            }
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                    }
                    
                    // Location
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.gray)
                            .frame(width: 20)
                        TextField("Add location", text: $location)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                    
                    // Description
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "text.alignleft")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            Text("Description")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        TextEditor(text: $notes)
                            .frame(height: 80)
                            .padding(4)
                            .scrollContentBackground(.hidden)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(6)
                    }
                    
                    // Guests
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person.2")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            Text("Guests")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        ForEach(guests, id: \.self) { guest in
                            HStack {
                                Text(guest)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                                Button(action: {
                                    guests.removeAll { $0 == guest }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(4)
                        }
                        
                        HStack {
                            TextField("Add guest email", text: $newGuestEmail)
                                .textFieldStyle(.plain)
                            Button("Add") {
                                if !newGuestEmail.isEmpty {
                                    guests.append(newGuestEmail)
                                    newGuestEmail = ""
                                }
                            }
                            .disabled(newGuestEmail.isEmpty)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            // Actions
            HStack(spacing: 12) {
                if let url = event.url {
                    Button(action: {
                        NSWorkspace.shared.open(url)
                    }) {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.gray)
                    }
                    .help("View in Google Calendar")
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.gray)
                
                Button(action: saveChanges) {
                    Text("Save")
                        .fontWeight(.medium)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isSaving)
            }
        }
        .padding(20)
        .frame(width: 380, height: 550)
        .background(Color(white: 0.12))
    }
    
    private func saveChanges() {
        Task {
            isSaving = true
            errorMessage = nil
            do {
                try await GoogleCalendarService.shared.updateEvent(
                    id: event.id,
                    summary: title,
                    description: notes,
                    location: location,
                    start: start,
                    end: end,
                    attendees: guests,
                    colorId: selectedColorId
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

struct DetailItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.gray)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(2)
        }
    }
}

// MARK: - All Day Events Banner

struct AllDayEventsBanner: View {
    let events: [EventModel]
    
    var allDayEvents: [EventModel] {
        events.filter { $0.isAllDay }
    }
    
    var body: some View {
        if !allDayEvents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allDayEvents) { event in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(nsColor: event.calendar.color))
                                .frame(width: 6, height: 6)
                            Text(event.title)
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.3))
                        .clipShape(Capsule())
                    }
                }
            }
            .frame(height: 24)
        }
    }
}

#Preview {
    HorizontalTimelineView()
        .frame(width: 400, height: 120)
        .background(Color.black)
}
