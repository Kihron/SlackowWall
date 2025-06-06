//
//  UtilitySettings.swift
//  SlackowWall
//
//  Created by Andrew on 5/26/25.
//

import SwiftUI

struct UtilitySettings: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    @AppSettings(\.utility) private var settings
    @AppSettings(\.keybinds) private var keybinds

    @ObservedObject private var pacemanManager = PacemanManager.shared

    @State private var showTokenAlert = false
    @State var tokenResponse: TokenResponse?

    @State var sensitivityScale: Double = Settings[\.utility].sensitivityScale
    @State var tallSensitivityScale: Double = Settings[\.utility].tallSensitivityScale

    var body: some View {
        SettingsPageView(title: "Utilities", shouldDisableFocus: true) {
            SettingsLabel(
                title: "Eye Projector",
                description: """
                    Settings for an automated eye projector for tall eye.
                    """)

            SettingsCardView {
                VStack {
                    HStack {
                        SettingsLabel(title: "Enabled", font: .body)

                        Button("Open") {
                            openWindow(id: "eye-projector-window")
                        }
                        .disabled(!settings.eyeProjectorEnabled)

                        Toggle("", isOn: $settings.eyeProjectorEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(.accentColor)
                    }

                    Group {
                        Divider()

                        SettingsToggleView(
                            title: "Open/Close With Tall Mode",
                            option: $settings.eyeProjectorOpenWithTallMode
                        )

                        Divider()

                        HStack {
                            SettingsLabel(
                                title: "Height Scale",
                                description: """
                                    Adjusts the "Stretch" on the y axis, \
                                    you probably want the default (0.2)
                                    """,
                                font: .body
                            )

                            TextField(
                                "", value: $settings.eyeProjectorHeightScale,
                                format: .number.grouping(.never)
                            )
                            .textFieldStyle(.roundedBorder)
                            .foregroundStyle(.primary)
                            .frame(width: 80)
                        }
                    }
                    .disabled(!settings.eyeProjectorEnabled)
                }
            }

            SettingsLabel(
                title: "Sensitivity Scaling",
                description: """
                    Allows your sensitivity to change when in tall mode, and to use lower \
                    sensitivities without affecting your unlocked cursor movements.
                    """
            )

            SettingsCardView {
                VStack {
                    SettingsToggleView(title: "Enabled", option: $settings.sensitivityScaleEnabled)

                    Group {
                        Divider()

                        HStack {
                            SettingsLabel(title: "Sensitivity Scale", font: .body)

                            TextField(
                                "", value: $sensitivityScale,
                                format: .number.grouping(.never)
                            )
                            .textFieldStyle(.roundedBorder)
                            .foregroundColor((0.1...50 ~= sensitivityScale) ? .primary : .red)
                            .frame(width: 80)
                            .onChange(of: sensitivityScale) { _, newValue in
                                if 0.1...50 ~= newValue {
                                    Settings[\.utility].sensitivityScale = newValue
                                    MouseSensitivityManager.shared.setSensitivityFactor(
                                        factor: newValue)
                                }
                            }
                        }

                        Divider()

                        HStack {
                            SettingsLabel(title: "Tall Mode Sensitivity Scale", font: .body)

                            TextField(
                                "", value: $tallSensitivityScale,
                                format: .number.grouping(.never)
                            )
                            .textFieldStyle(.roundedBorder)
                            .foregroundColor((0.1...50 ~= tallSensitivityScale) ? .primary : .red)
                            .frame(width: 80)
                            .onChange(of: tallSensitivityScale) { _, newValue in
                                if 0.1...50 ~= newValue {
                                    Settings[\.utility].tallSensitivityScale = newValue
                                }
                            }
                        }
                    }.disabled(!settings.sensitivityScaleEnabled)
                }
            }

            SettingsLabel(
                title: "Paceman",
                description: """
                    Configure Settings for Paceman, a site that tracks your live statistics and/or \
                    reset statistics.
                    View statistics, and generate token here: [paceman.gg](https://paceman.gg)
                    SpeedrunIGT 14.2+ is required.
                    """
            )
            .padding(.bottom, -6)

            SettingsCardView {
                SettingsToggleView(
                    title: "Auto-launch Paceman",
                    description: "Automatically launch Paceman with SlackowWall.",
                    option: $settings.autoLaunchPaceman)
            }

            SettingsLabel(
                title: "Paceman Tracker",
                description:
                    "These settings are directly tied to the Paceman tracker, and require it to be restarted in order to take effect."
            )

            SettingsCardView {
                VStack {
                    HStack {
                        Text("Paceman Token")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Test") {
                            Task {
                                await validateToken()
                            }
                        }

                        SecureField(
                            "", text: $pacemanManager.pacemanConfig.accessKey,
                            onCommit: {
                                pacemanManager.pacemanConfig.accessKey = pacemanManager
                                    .pacemanConfig.accessKey.trimmingCharacters(
                                        in: .whitespacesAndNewlines)
                            }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .disabled(pacemanManager.isRunning)
                    }

                    Divider()

                    SettingsToggleView(
                        title: "Track Reset Statistics",
                        option: $pacemanManager.pacemanConfig.resetStatsEnabled
                    )
                    .disabled(pacemanManager.isRunning)

                    Divider()

                    HStack {
                        SettingsLabel(
                            title: "Start/Stop Paceman",
                            description: "Paceman will close with SlackowWall.", font: .body)

                        Button {
                            if pacemanManager.isRunning {
                                pacemanManager.stopPaceman()
                            } else {
                                pacemanManager.startPaceman()
                            }
                        } label: {
                            HStack {
                                Image(
                                    systemName: pacemanManager.isRunning ? "stop.fill" : "play.fill"
                                )
                                .foregroundStyle(pacemanManager.isRunning ? .red : .green)
                                Text(pacemanManager.isRunning ? "Stop Paceman" : "Start Paceman")
                            }
                        }
                    }
                }
            }
            .alert(
                "Paceman Token",
                isPresented: $showTokenAlert,
                presenting: tokenResponse
            ) { response in
                switch response {
                    case .empty, .invalid:
                        Button("Get Token") {
                            if let url = URL(string: "https://paceman.gg") {
                                openURL(url)
                            }
                        }
                        Button("Close", role: .cancel) {}
                    case .valid, .unable:
                        Button("Ok") {}
                }
            } message: { response in
                switch response {
                    case .empty:
                        Text("No token found, generate here: paceman.gg")
                    case .valid:
                        Text("Token is Valid!")
                    case .invalid:
                        Text("Invalid token, check it was input correctly.")
                    case .unable:
                        Text("Error checking token, please try again later.")
                }
            }
        }
    }

    private func validateToken() async {
        let token = pacemanManager.pacemanConfig.accessKey
        if token.isEmpty {
            tokenResponse = .empty
        } else {
            do {
                if let uuid = try await PacemanManager.validateToken(token: token) {
                    tokenResponse = .valid(uuid)
                } else {
                    tokenResponse = .invalid
                }
            } catch {
                LogManager.shared.appendLog("Error validating token:", error)
                tokenResponse = .unable
            }
        }
        showTokenAlert = true
    }

    private func getAvatarURL(_ uuid: String) -> URL? {
        return URL(string: "https://minotar.net/helm/\(uuid)/32")
    }
}

#Preview {
    ScrollView {
        UtilitySettings()
            .padding()
    }
}
