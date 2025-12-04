//
//  ContentView.swift
//  Example
//
//  Created by Marat Zainullin on 10/07/2025.
//

import SwiftUI
import iOS_TTS

struct ContentView: View {
    @StateObject private var modelManager = ModelManager()
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var inputText = "Où êtes-vous? C'est incroyable!"
    @State private var isGenerating = false
    @State private var generatedAudio: [Float]? = nil
    @State private var performanceReport: String? = nil
    @State private var showPerformanceReport = false
    @State private var showVoiceSettings = false
    
    // Voice settings
    @State private var selectedLanguage: Language = .french
    @State private var selectedVoice: VoiceStyle = .ffSiwis
    @State private var speechSpeed: Float = 1.0
    
    private var voiceFlag: String {
        switch selectedLanguage {
        case .englishUS:
            return "🇺🇸"
        case .englishGB:
            return "🇬🇧"
        case .french:
            return "🇫🇷"
        case .hindi:
            return "🇮🇳"
        case .japanese:
            return "🇯🇵"
        case .chinese:
            return "🇨🇳"
        case .spanish:
            return "🇪🇸"
        case .italian:
            return "🇮🇹"
        case .portuguese:
            return "🇧🇷"
        }
    }
    
    private func sampleText(for language: Language) -> String {
        switch language {
        case .englishUS:
            return "Hello, this is a test of text to speech technology."
        case .englishGB:
            return "Good day! This is a demonstration of British text to speech."
        case .french:
            return "Où êtes-vous? C'est incroyable!"
        case .hindi:
            return "नमस्ते, यह टेक्स्ट टू स्पीच का परीक्षण है।"
        case .japanese:
            return "こんにちは、これはテキスト読み上げのテストです。"
        case .chinese:
            return "你好，这是文本转语音的测试。"
        case .spanish:
            return "¡Hola! Esta es una prueba de síntesis de voz."
        case .italian:
            return "Ciao, questo è un test di sintesi vocale."
        case .portuguese:
            return "Olá, este é um teste de síntese de fala."
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if !modelManager.isModelReady {
                    // Download section
                    VStack(spacing: 16) {
                        Text("TTS models not found")
                            .font(.headline)
                        
                        if modelManager.isDownloading {
                            VStack {
                                ProgressView(value: modelManager.downloadProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                Text("\(Int(modelManager.downloadProgress * 100))%")
                                    .font(.caption)
                            }
                        } else {
                            Button("Download Models") {
                                modelManager.downloadModels()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        if let error = modelManager.errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                    .padding()
                } else {
                    // TTS section
                    VStack(spacing: 16) {
                        VStack(spacing: 4) {
                            Text("TTS Ready")
                                .font(.headline)
                                .foregroundColor(.green)
                            
                            HStack(spacing: 8) {
                                Text("\(voiceFlag) \(selectedVoice.displayName)")
                                    .font(.caption)
                                
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Text(selectedLanguage.rawValue.uppercased())
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(4)
                                
                                if speechSpeed != 1.0 {
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    Text("\(speechSpeed, specifier: "%.1f")x")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .cornerRadius(4)
                                }
                                
                            }
                            .foregroundColor(.gray)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Text to speak:")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Button("Sample text") {
                                    inputText = sampleText(for: selectedLanguage)
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            
                            TextEditor(text: $inputText)
                                .frame(minHeight: 100)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }
                        
                        HStack {
                            Button("Generate Speech") {
                                Task {
                                    await generateSpeech()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isGenerating || inputText.isEmpty)
                            
                            if isGenerating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            
                            if performanceReport != nil {
                                Button("Performance") {
                                    showPerformanceReport.toggle()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        if let error = modelManager.errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        // Audio player controls
                        if generatedAudio != nil {
                            VStack(spacing: 12) {
                                Divider()
                                
                                HStack {
                                    Button(action: {
                                        if audioPlayer.isPlaying {
                                            audioPlayer.pause()
                                        } else {
                                            audioPlayer.play()
                                        }
                                    }) {
                                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 44))
                                    }
                                    
                                    Button(action: {
                                        audioPlayer.stop()
                                    }) {
                                        Image(systemName: "stop.circle.fill")
                                            .font(.system(size: 44))
                                    }
                                    .disabled(!audioPlayer.isPlaying && audioPlayer.currentTime == 0)
                                }
                                
                                VStack(spacing: 4) {
                                    Slider(value: Binding(
                                        get: { audioPlayer.currentTime },
                                        set: { audioPlayer.seek(to: $0) }
                                    ), in: 0...max(audioPlayer.duration, 0.01))
                                    .disabled(audioPlayer.duration == 0)
                                    
                                    HStack {
                                        Text(formatTime(audioPlayer.currentTime))
                                            .font(.caption)
                                            .monospacedDigit()
                                        
                                        Spacer()
                                        
                                        Text(formatTime(audioPlayer.duration))
                                            .font(.caption)
                                            .monospacedDigit()
                                    }
                                }
                            }
                            .padding(.top, 12)
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("iOS-TTS Example")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showVoiceSettings = true
                    }) {
                        Image(systemName: "speaker.3")
                            .font(.body)
                    }
                    .disabled(!modelManager.isModelReady)
                }
            }
        }
        .sheet(isPresented: $showVoiceSettings) {
            VoiceSettingsView(
                selectedLanguage: $selectedLanguage,
                selectedVoice: $selectedVoice,
                speed: $speechSpeed,
                computeUnits: $modelManager.computeUnits
            )
            .onDisappear {
                // Reinitialize pipeline when compute units change
                if modelManager.isModelReady {
                    do {
                        try modelManager.updateComputeUnits(modelManager.computeUnits)
                    } catch {
                        modelManager.errorMessage = "Failed to update compute units: \(error.localizedDescription)"
                    }
                }
            }
        }
        .sheet(isPresented: $showPerformanceReport) {
            NavigationView {
                ScrollView {
                    if let report = performanceReport {
                        Text(report)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                    }
                }
                .navigationTitle("Performance Report")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showPerformanceReport = false
                        }
                    }
                }
            }
        }
    }
    
    private func generateSpeech() async {
        isGenerating = true
        modelManager.errorMessage = nil
        
        do {
            let options = GenerationOptions(
                style: selectedVoice,
                speed: speechSpeed
            )
            
            let audio = try await modelManager.generateSpeech(text: inputText, options: options)
            print("Generated audio with \(audio.count) samples")
            
            // Get performance report
            performanceReport = modelManager.getPerformanceReport()
            if let report = performanceReport {
                print("\n\(report)")
            }
            
            // Store the audio and play it
            generatedAudio = audio
            audioPlayer.loadAudio(samples: audio, sampleRate: 24000)
            audioPlayer.play()
        } catch {
            modelManager.errorMessage = error.localizedDescription
        }
        
        isGenerating = false
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

