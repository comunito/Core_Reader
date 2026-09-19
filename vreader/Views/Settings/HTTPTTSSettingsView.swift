// Purpose: Settings UI for configuring HTTP-based TTS providers.
// Allows users to set API endpoint, key, voice, and provider type.
//
// Key decisions:
// - Stores config via @AppStorage for persistence.
// - API key stored in Keychain via KeychainService for security.
// - Test connection button validates config before saving.
// - Provider picker: Google Cloud, Azure, or Custom endpoint.
//
// @coordinates-with: HTTPTTSConfig.swift, HTTPTTSProvider.swift

import SwiftUI

/// Settings view for HTTP TTS provider configuration.
struct HTTPTTSSettingsView: View {

    @State private var endpoint: String = "https://texttospeech.googleapis.com/v1/text:synthesize"
    @State private var apiKey: String = ""
    @State private var voice: String = "es-US-Wavenet-B"
    @State private var providerType: ProviderSelection = .googleCloud
    @State private var languageCode: String = "es-US"
    @State private var speakingRate: Double = 1.0
    @State private var azureRegion: String = "eastus"
    @State private var customHeaders: String = ""
    @State private var customBodyTemplate: String = ""
    @State private var validationMessage: String?
    @State private var isValid: Bool?

    private let keychain = KeychainService()
    private static let keychainAccount = "com.vreader.httpTTS.apiKey"
    private static let configKey = "httpTTSConfig"

    enum ProviderSelection: String, CaseIterable {
        case googleCloud = "Google Cloud"
        case azure = "Azure"
        case custom = "Custom"
    }

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Type", selection: $providerType) {
                    ForEach(ProviderSelection.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                TextField("API Endpoint", text: $endpoint)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .accessibilityIdentifier("httpTTSEndpoint")

                SecureField("API Key", text: $apiKey)
                    .textContentType(.password)
                    .accessibilityIdentifier("httpTTSApiKey")

                TextField("Voice ID", text: $voice)
                    .autocapitalization(.none)
                    .accessibilityIdentifier("httpTTSVoice")

                HStack {
                    Text("Speed")
                    Slider(value: $speakingRate, in: 0.25...4.0, step: 0.05)
                    Text(String(format: "%.2gx", speakingRate))
                        .monospacedDigit()
                }
            }

            if providerType == .googleCloud {
                Section("Google Cloud") {
                    TextField("Language code", text: $languageCode)
                        .autocapitalization(.none)
                        .accessibilityIdentifier("googleTTSLanguageCode")
                    Text("The API key is stored only in Keychain.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if providerType == .azure {
                Section("Azure Settings") {
                    TextField("Region", text: $azureRegion)
                        .autocapitalization(.none)
                        .accessibilityIdentifier("httpTTSAzureRegion")
                }
            }

            if providerType == .custom {
                Section("Custom API Settings") {
                    TextField("Custom Headers (JSON)", text: $customHeaders)
                        .autocapitalization(.none)
                        .accessibilityIdentifier("httpTTSCustomHeaders")

                    TextField("Body Template", text: $customBodyTemplate)
                        .autocapitalization(.none)
                        .accessibilityIdentifier("httpTTSCustomBody")

                    Text("Use {{TEXT}} and {{VOICE}} as placeholders.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button("Validate & Save") {
                    validateAndSave()
                }
                .accessibilityIdentifier("httpTTSSaveButton")

                if let message = validationMessage {
                    Label(
                        message,
                        systemImage: isValid == true ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundColor(isValid == true ? .green : .red)
                    .font(.caption)
                }
            }
        }
        .navigationTitle("HTTP TTS Settings")
        .onAppear { loadConfig() }
    }

    // MARK: - Config Management

    private func buildConfig() -> HTTPTTSConfig {
        let provider: TTSProviderType
        switch providerType {
        case .googleCloud:
            provider = .googleCloud(languageCode: languageCode)
        case .azure:
            provider = .azure(region: azureRegion)
        case .custom:
            let headers = parseHeaders(customHeaders)
            provider = .custom(headers: headers, bodyTemplate: customBodyTemplate)
        }

        return HTTPTTSConfig(
            endpoint: endpoint,
            apiKey: apiKey,
            voice: voice,
            provider: provider,
            speakingRate: speakingRate
        )
    }

    private func validateAndSave() {
        let config = buildConfig()
        let result = config.validate()

        switch result {
        case .valid:
            saveConfig(config)
            validationMessage = "Configuration saved successfully."
            isValid = true
        case .invalid(let error):
            validationMessage = validationErrorMessage(error)
            isValid = false
        }
    }

    private func saveConfig(_ config: HTTPTTSConfig) {
        // Save API key to Keychain
        try? keychain.saveString(config.apiKey, forAccount: Self.keychainAccount)

        // Save config (without API key) to UserDefaults
        var configForStorage = config
        configForStorage.apiKey = "" // Don't store API key in UserDefaults
        if let data = try? JSONEncoder().encode(configForStorage) {
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
    }

    private func loadConfig() {
        // Load config from UserDefaults
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let config = try? JSONDecoder().decode(HTTPTTSConfig.self, from: data) {
            endpoint = config.endpoint
            voice = config.voice
            speakingRate = config.speakingRate

            switch config.provider {
            case .googleCloud(let code):
                providerType = .googleCloud
                languageCode = code
            case .azure(let region):
                providerType = .azure
                azureRegion = region
            case .custom(let headers, let bodyTemplate):
                providerType = .custom
                customHeaders = headersToString(headers)
                customBodyTemplate = bodyTemplate
            }
        }

        // Load API key from Keychain
        apiKey = (try? keychain.readString(forAccount: Self.keychainAccount)) ?? ""
    }

    private func parseHeaders(_ string: String) -> [String: String] {
        guard let data = string.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private func headersToString(_ headers: [String: String]) -> String {
        guard !headers.isEmpty,
              let data = try? JSONEncoder().encode(headers),
              let string = String(data: data, encoding: .utf8)
        else { return "" }
        return string
    }

    private func validationErrorMessage(_ error: ConfigValidationError) -> String {
        switch error {
        case .emptyEndpoint:
            return "API endpoint URL is required."
        case .emptyAPIKey:
            return "API key is required."
        case .emptyVoice:
            return "Voice ID is required."
        case .invalidEndpointURL:
            return "API endpoint is not a valid URL."
        case .invalidSpeakingRate:
            return "Speed must be between 0.25x and 4x."
        }
    }
}
