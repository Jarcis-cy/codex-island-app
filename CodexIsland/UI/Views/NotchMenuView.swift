//
//  NotchMenuView.swift
//  CodexIsland
//
//  Minimal menu matching Dynamic Island aesthetic
//

import ApplicationServices
import Combine
import SwiftUI
import ServiceManagement
import Sparkle

// MARK: - NotchMenuView

struct NotchMenuView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var screenSelector = ScreenSelector.shared
    @ObservedObject private var soundSelector = SoundSelector.shared
    @State private var hooksInstalled: Bool = false
    @State private var launchAtLogin: Bool = false
    @State private var remoteDebugLogsEnabled: Bool = false
    @State private var hooksErrorMessage: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                // Back button
                MenuRow(
                    icon: "chevron.left",
                    label: "Back"
                ) {
                    viewModel.toggleMenu()
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                // Appearance settings
                ScreenPickerRow(screenSelector: screenSelector)
                SoundPickerRow(soundSelector: soundSelector)

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                // System settings
                MenuToggleRow(
                    icon: "power",
                    label: "Launch at Login",
                    isOn: launchAtLogin
                ) {
                    do {
                        if launchAtLogin {
                            try SMAppService.mainApp.unregister()
                            launchAtLogin = false
                        } else {
                            try SMAppService.mainApp.register()
                            launchAtLogin = true
                        }
                    } catch {
                        print("Failed to toggle launch at login: \(error)")
                    }
                }

                MenuToggleRow(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Hooks",
                    isOn: hooksInstalled
                ) {
                    do {
                        if hooksInstalled {
                            try HookInstaller.uninstall()
                        } else {
                            try HookInstaller.installIfNeeded()
                        }
                        hooksInstalled = HookInstaller.isInstalled()
                        hooksErrorMessage = nil
                    } catch {
                        hooksInstalled = HookInstaller.isInstalled()
                        hooksErrorMessage = error.localizedDescription
                    }
                }

                if let hooksErrorMessage, !hooksErrorMessage.isEmpty {
                    Text(hooksErrorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(TerminalColors.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                }

                MenuToggleRow(
                    icon: "ladybug",
                    label: "Remote Debug Logs",
                    isOn: remoteDebugLogsEnabled
                ) {
                    remoteDebugLogsEnabled.toggle()
                    AppSettings.remoteDiagnosticsLoggingEnabled = remoteDebugLogsEnabled
                }

                AccessibilityRow(isEnabled: AXIsProcessTrusted())

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                MenuRow(
                    icon: "server.rack",
                    label: "Remote Hosts"
                ) {
                    viewModel.showRemoteHosts()
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                // About
                UpdateRow(updateManager: updateManager)

                MenuRow(
                    icon: "star",
                    label: "Star on GitHub"
                ) {
                    if let url = URL(string: "https://github.com/Jarcis-cy/codex-island-app") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                MenuRow(
                    icon: "xmark.circle",
                    label: "Quit",
                    isDestructive: true
                ) {
                    AppDelegate.shared?.requestQuit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            refreshStates()
        }
        .onChange(of: viewModel.contentType) { _, newValue in
            if newValue == .menu {
                refreshStates()
            }
        }
    }

    private func refreshStates() {
        hooksInstalled = HookInstaller.isInstalled()
        hooksErrorMessage = nil
        launchAtLogin = SMAppService.mainApp.status == .enabled
        remoteDebugLogsEnabled = AppSettings.remoteDiagnosticsLoggingEnabled
        screenSelector.refreshScreens()
    }
}
