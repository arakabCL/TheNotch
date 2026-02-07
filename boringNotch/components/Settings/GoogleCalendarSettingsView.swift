//
//  GoogleCalendarSettingsView.swift
//  boringNotch
//
//  Google Calendar settings and sign-in UI
//

import SwiftUI
import Defaults

struct GoogleCalendarSettingsView: View {
    @ObservedObject var authManager = GoogleAuthManager.shared
    @ObservedObject var calendarService = GoogleCalendarService.shared
    @Default(.useGoogleCalendar) var useGoogleCalendar
    @Default(.googleCalendarPollingInterval) var pollingInterval
    
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .useGoogleCalendar) {
                    Text("Use Google Calendar")
                }
            } header: {
                Text("Calendar Source")
            } footer: {
                Text("Enable to show your Google Calendar events in the notch instead of music controls.")
            }
            
            if useGoogleCalendar {
                signInSection
                
                if authManager.isSignedIn {
                    calendarOptionsSection
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private var signInSection: some View {
        Section {
            if authManager.isSignedIn {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Signed in", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        if let email = authManager.userEmail {
                            Text(email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button("Sign Out") {
                        authManager.signOut()
                        calendarService.stopPolling()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect your Google account to see calendar events.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        Task {
                            await authManager.signIn()
                            if authManager.isSignedIn {
                                await calendarService.refreshEvents()
                                calendarService.startPolling(interval: pollingInterval)
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("Sign in with Google")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authManager.isAuthenticating)
                    
                    if authManager.isAuthenticating {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Waiting for authorization...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let error = authManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        } header: {
            Text("Google Account")
        }
    }
    
    private var calendarOptionsSection: some View {
        Section {
            HStack {
                Text("Refresh interval")
                Spacer()
                Picker("", selection: $pollingInterval) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            
            Button("Refresh Now") {
                Task {
                    await calendarService.refreshEvents()
                }
            }
            .disabled(calendarService.isLoading)
            
            if calendarService.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Updating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let error = calendarService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        } header: {
            Text("Options")
        } footer: {
            Text("Events will automatically refresh at the selected interval.")
        }
    }
}

#Preview {
    GoogleCalendarSettingsView()
        .frame(width: 400)
}
