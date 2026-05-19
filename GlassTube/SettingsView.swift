//
//  SettingsView.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import SwiftUI
import AppKit

struct SettingsView: View {
        @AppStorage("showLiveCaptionsInfo") private var showLiveCaptionsInfo = true
    @AppStorage("autoplay") private var autoplay = true
    @AppStorage("playbackQuality") private var playbackQuality = "Auto"
    @AppStorage("watchLaterDestination") private var watchLaterDestination = "glasstube"
    
    // Extension toggles
    @AppStorage("sponsorBlockEnabled") private var sponsorBlockEnabled = true
    @AppStorage("returnYoutubeDislikeEnabled") private var returnYoutubeDislikeEnabled = true
    @AppStorage("dearrowEnabled") private var dearrowEnabled = true

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var extensionsManager: ExtensionsManager
    
    @Environment(\.dismiss) private var dismiss
    @State private var updateAvailable = false
    @State private var latestVersion = ""
    @State private var checkingForUpdates = false
    @State private var oauthClientID = ""
    @State private var oauthClientSecret = ""
    @State private var authSavedMessage: String?
    @State private var showingGuidedSetup = false
    @State private var currentSetupStep = 0
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    Toggle("Autoplay", isOn: $autoplay)
                        .help("Automatically play the next video")
                    
                    Picker("Watch Later Destination", selection: $watchLaterDestination) {
                        Text("GlassTube Playlist (readable)").tag("glasstube")
                        Text("YouTube Watch Later (write-only)").tag("youtube")
                    }
                    .help("Choose where to save videos when you click \"Add to Watch Later\"")
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("About Watch Later Options")
                            .font(.caption.weight(.semibold))
                        Text("• GlassTube Playlist: Creates/uses a private playlist you can view in the Library tab")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("• YouTube Watch Later: Adds to YouTube's official WL playlist, but you can't view it in GlassTube due to API restrictions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Playback") {
                    Picker("Default Quality", selection: $playbackQuality) {
                        Text("Auto").tag("Auto")
                        Text("8K").tag("4320p")
                        Text("4K").tag("2160p")
                        Text("1080p").tag("1080p")
                        Text("720p").tag("720p")
                        Text("480p").tag("480p")
                    }
                    .help("Default video quality preference")

                    Toggle("Show Live Captions Info", isOn: $showLiveCaptionsInfo)
                        .help("Show a tip about enabling macOS Live Captions for any video.")
                }

                Section("Downloads") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Download Folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(downloadManager.downloadsDirectoryDisplayPath)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: 10) {
                        Button("Choose Folder") {
                            downloadManager.chooseDownloadsDirectory()
                        }
                        .buttonStyle(.bordered)

                        Button("Use Default Downloads") {
                            downloadManager.resetDownloadsDirectory()
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Section("Extensions") {
                    Toggle("SponsorBlock", isOn: $sponsorBlockEnabled)
                        .onChange(of: sponsorBlockEnabled) { _, _ in
                            applyExtensionSettings()
                        }
                        .help("Skip sponsor segments and self-promotion")
                    
                    Toggle("Return YouTube Dislike", isOn: $returnYoutubeDislikeEnabled)
                        .onChange(of: returnYoutubeDislikeEnabled) { _, _ in
                            applyExtensionSettings()
                        }
                        .help("Show dislike counts on videos")
                    
                    Toggle("DeArrow", isOn: $dearrowEnabled)
                        .onChange(of: dearrowEnabled) { _, _ in
                            applyExtensionSettings()
                        }
                        .help("Replace clickbait titles and thumbnails")
                }

                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        // Header
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.key.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Google Account Sign-In")
                                    .font(.headline)
                                Text("Required for subscriptions, library, saves, and personalized features")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        // Quick Setup Button
                        if !authManager.hasOAuthConfiguration {
                            Button {
                                showingGuidedSetup = true
                            } label: {
                                HStack {
                                    Image(systemName: "wand.and.stars")
                                    Text("Start Guided Setup")
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .controlSize(.large)
                        }

                        // Info callouts
                        infoCallout(icon: "info.circle.fill", color: .blue, text: "Video playback works without signing in. Sign-in is only needed for subscriptions, library, and personalized features.")
                        
                        infoCallout(icon: "speedometer", color: .teal, text: "Google enforces a daily YouTube Data API quota (default 10,000 units/day; resets at midnight Pacific). If you hit quota errors, wait for reset or use a different project.")
                        
                        infoCallout(icon: "text.bubble.fill", color: .mint, text: "Sign-in uses Google's TV/Limited-Input device flow, which grants youtube and youtube.readonly scopes. Some actions (commenting, rating) require youtube.force-ssl, which isn't available in this flow.")

                        Divider()

                        // Setup Instructions (collapsible)
                        DisclosureGroup("Setup Instructions") {
                            VStack(alignment: .leading, spacing: 12) {
                                instructionStep(
                                    number: 1,
                                    text: "Go to console.cloud.google.com and create a new project (or select existing)"
                                )
                                instructionStep(
                                    number: 2,
                                    text: "Search for 'YouTube Data API v3' and click Enable"
                                )
                                instructionStep(
                                    number: 3,
                                    text: "Go to APIs & Services → Credentials → Create Credentials → OAuth client ID"
                                )
                                instructionStep(
                                    number: 4,
                                    text: "Application type: 'TVs and Limited Input devices' (required for device flow)"
                                )
                                instructionStep(
                                    number: 5,
                                    text: "Copy your Client ID and Client Secret (paste them below in Manual Setup)"
                                )
                                
                                Divider()
                                    .padding(.vertical, 4)
                                
                                Text("OAuth Consent Screen Configuration:")
                                    .font(.caption.weight(.semibold))
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("App Information:")
                                        .font(.caption2.weight(.semibold))
                                    Text("• App name: GlassTube (or your choice)")
                                    Text("• User support email: Your email")
                                    Text("• Developer contact: Your email")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Scopes (required):")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.top, 4)
                                    Text("• openid (automatic)")
                                    Text("• email (automatic)")
                                    Text("• profile (automatic)")
                                    Text("• ../auth/youtube.readonly (required)")
                                    Text("• ../auth/youtube (required)")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Do NOT request youtube.force-ssl scope")
                                            .font(.caption2.weight(.semibold))
                                        Text("Google's TV/Limited-Input device flow doesn't grant this scope. Requesting it causes 'invalid_scope' errors and blocks sign-in completely.")
                                            .font(.caption2)
                                    }
                                }
                                .padding(8)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(6)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Publishing Status & Test Users:")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.top, 4)
                                    Text("• Keep Publishing status as 'Testing'")
                                    Text("• Go to OAuth consent screen → Audience tab")
                                    Text("• Click 'Add users' under Test users")
                                    Text("• Add your Google email (exact email you'll sign in with)")
                                    Text("• Wait 1-5 minutes for changes to propagate")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(.blue)
                                        .font(.caption2)
                                    Text("If your email isn't added as a test user, you'll get 'Error 403: access_denied' when trying to sign in.")
                                        .font(.caption2)
                                }
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                                
                                Divider()
                                    .padding(.vertical, 4)
                                
                                Text("What works with these scopes:")
                                    .font(.caption.weight(.semibold))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("✓ Home feed, subscriptions, playlists")
                                    Text("✓ Watch Later, liked videos, your uploads")
                                    Text("✓ View comments, channel info")
                                    Text("✓ Create playlists, add/remove videos")
                                    Text("✓ Subscribe/unsubscribe from channels")
                                }
                                .font(.caption2)
                                .foregroundStyle(.green)
                                
                                Text("What doesn't work (requires youtube.force-ssl):")
                                    .font(.caption.weight(.semibold))
                                    .padding(.top, 4)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("✗ Posting comments")
                                    Text("✗ Liking/disliking videos")
                                    Text("✗ Some playlist operations")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                
                                Divider()
                                    .padding(.vertical, 4)
                                
                                Text("Common Errors:")
                                    .font(.caption.weight(.semibold))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("• 'Error 403: access_denied' → Your email isn't added as a test user yet")
                                    Text("• 'invalid_client' → Wrong client type (must be 'TVs and Limited Input devices')")
                                    Text("• 'invalid_scope' → You requested youtube.force-ssl (don't add it)")
                                    Text("• 'restricted_client' → Client was rejected by Google (use your own client)")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.top, 8)
                        }
                        .font(.subheadline)
                        
                        Divider()

                        // Manual credential entry
                        Text("Manual Setup")
                            .font(.subheadline.weight(.semibold))

                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Client ID", text: $oauthClientID)
                                .textFieldStyle(.roundedBorder)

                            SecureField("Client Secret", text: $oauthClientSecret)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 10) {
                            Button("Save Credentials") {
                                authManager.saveOAuthConfiguration(
                                    clientID: oauthClientID,
                                    clientSecret: oauthClientSecret
                                )
                                authSavedMessage = "Credentials saved. Add your email as a test user in OAuth consent screen, then sign in."
                            }

                            Button("Clear") {
                                oauthClientID = ""
                                oauthClientSecret = ""
                                authManager.clearOAuthConfiguration()
                                authSavedMessage = "Cleared OAuth credentials."
                            }
                        }

                        if let authSavedMessage {
                            Text(authSavedMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Status indicator
                        HStack(spacing: 6) {
                            if authManager.isSignedIn {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Signed in as \(authManager.userName.isEmpty ? authManager.userEmail : authManager.userName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if authManager.hasOAuthConfiguration {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text("Credentials saved. Add your email as a test user, then sign in from the account button.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.orange)
                                Text("Sign-in disabled until credentials are saved.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }

                        // Helpful links
                        HStack(spacing: 16) {
                            Link("Google Cloud Console", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                                .font(.caption)
                            Link("OAuth Consent (Audience)", destination: URL(string: "https://console.cloud.google.com/apis/credentials/consent")!)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Authentication")
                }
                
                Section("Updates") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("GlassTube v1.0.0")
                                    .font(.headline)
                                
                                if checkingForUpdates {
                                    Text("Checking for updates...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if updateAvailable {
                                    Text("New version available: v\(latestVersion)")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                } else {
                                    Text("You're up to date")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Button(checkingForUpdates ? "Checking..." : (updateAvailable ? "Download Update" : "Check for Updates")) {
                                if updateAvailable {
                                    if let url = URL(string: "https://github.com/kpulik/GlassTube/releases/latest") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } else {
                                    checkForUpdates()
                                }
                            }
                            .disabled(checkingForUpdates)
                        }
                        
                        if updateAvailable {
                            Text("Download the latest version from GitHub, then quit and replace this app.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Support") {
                    VStack(spacing: 12) {
                        Text("Enjoying GlassTube?")
                            .font(.headline)
                        
                        Text("Support development with a coffee! ☕️")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button(action: {
                            if let url = URL(string: "https://buymeacoffee.com/kpulik") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "cup.and.saucer.fill")
                                Text("Buy Me a Coffee")
                            }
                            .font(.body)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.yellow)
                            .foregroundStyle(.black)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build", value: "2026.04.11")
                    
                    Button("View on GitHub") {
                        if let url = URL(string: "https://github.com/kpulik/GlassTube") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    
                    Button("Send Feedback") {
                        if let url = URL(string: "https://github.com/kpulik/GlassTube/issues/new") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                let oauth = authManager.oauthConfiguration()
                oauthClientID = oauth.clientID
                oauthClientSecret = oauth.clientSecret

                // Optionally check for updates on appear
                // checkForUpdates()
            }
        }
        .frame(width: 520, height: 780)
        .sheet(isPresented: $showingGuidedSetup) {
            GuidedSetupSheet(currentStep: $currentSetupStep)
        }
    }
    
    // MARK: - Helper Functions

    private func infoCallout(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.body)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor)
                .clipShape(Circle())
            
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Update Checking
    
    private func checkForUpdates() {
        checkingForUpdates = true
        
        Task {
            do {
                // Fetch latest release from GitHub API
                let url = URL(string: "https://api.github.com/repos/kpulik/GlassTube/releases/latest")!
                let (data, _) = try await URLSession.shared.data(from: url)
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tagName = json["tag_name"] as? String {
                    
                    // Remove 'v' prefix if present
                    let version = tagName.replacingOccurrences(of: "v", with: "")
                    
                    await MainActor.run {
                        latestVersion = version
                        // Compare versions (simple string comparison for now)
                        // TODO: Implement semantic versioning comparison
                        updateAvailable = version != "1.0.0"
                        checkingForUpdates = false
                    }
                }
            } catch {
                await MainActor.run {
                    checkingForUpdates = false
                    // Silently fail - could add error state if needed
                }
            }
        }
    }

    private func applyExtensionSettings() {
        extensionsManager.applyUserSettings(
            sponsorBlockEnabled: sponsorBlockEnabled,
            returnYoutubeDislikeEnabled: returnYoutubeDislikeEnabled,
            deArrowEnabled: dearrowEnabled
        )
    }
}

// MARK: - Guided Setup Sheet

struct GuidedSetupSheet: View {
    @Binding var currentStep: Int
    @Environment(\.dismiss) private var dismiss
    @State private var showingPermissionAlert = false
    
    private let setupSteps: [(title: String, description: String, url: String?, action: String)] = [
        (
            "Create Google Cloud Project",
            "We'll open the Google Cloud Console where you can create a new project called 'GlassTube'.",
            "https://console.cloud.google.com/projectcreate",
            "Open Console"
        ),
        (
            "Enable YouTube Data API",
            "Next, we need to enable the YouTube Data API v3 for your project.",
            "https://console.cloud.google.com/apis/library/youtube.googleapis.com",
            "Enable API"
        ),
        (
            "Create OAuth Credentials",
            "Now create OAuth credentials. Select 'TVs and Limited Input devices' as the application type.",
            "https://console.cloud.google.com/apis/credentials/oauthclient",
            "Create Credentials"
        ),
        (
            "Add Test User",
            "Finally, add your Google email as a test user in the OAuth consent screen Audience tab.",
            "https://console.cloud.google.com/apis/credentials/consent",
            "Add Test User"
        ),
        (
            "Copy Credentials",
            "Copy your Client ID and Client Secret from the credentials page and paste them in Settings.",
            nil,
            "Done"
        )
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(0..<setupSteps.count, id: \.self) { index in
                        Circle()
                            .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.top)
                
                // Current step
                VStack(spacing: 16) {
                    Text("Step \(currentStep + 1) of \(setupSteps.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(setupSteps[currentStep].title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(setupSteps[currentStep].description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action button
                VStack(spacing: 12) {
                    if let url = setupSteps[currentStep].url {
                        Button {
                            showingPermissionAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "safari")
                                Text(setupSteps[currentStep].action)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .alert("Open in Browser?", isPresented: $showingPermissionAlert) {
                            Button("Cancel", role: .cancel) {}
                            Button("Open") {
                                if let url = URL(string: url) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        } message: {
                            Text("This will open the Google Cloud Console in your default browser to complete this setup step.")
                        }
                    }
                    
                    HStack(spacing: 12) {
                        if currentStep > 0 {
                            Button("Previous") {
                                withAnimation {
                                    currentStep -= 1
                                }
                            }
                        }
                        
                        Button(currentStep == setupSteps.count - 1 ? "Finish" : "Next") {
                            if currentStep == setupSteps.count - 1 {
                                dismiss()
                            } else {
                                withAnimation {
                                    currentStep += 1
                                }
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding()
            }
            .navigationTitle("Guided Setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 480, height: 400)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
        .environmentObject(DownloadManager())
        .environmentObject(ExtensionsManager())
}
