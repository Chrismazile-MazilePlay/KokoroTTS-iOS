//
//  VoiceSettingsView.swift
//  Example
//

import SwiftUI
import iOS_TTS
import CoreML

struct VoiceSettingsView: View {
    @Binding var selectedLanguage: Language
    @Binding var selectedVoice: VoiceStyle
    @Binding var speed: Float
    @Binding var computeUnits: MLComputeUnits
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedGender: Gender? = nil
    @State private var searchText = ""
    
    private var filteredVoices: [VoiceStyle] {
        var voices = VoiceStyle.allCases
        
        // Filter by language
        voices = voices.filter { $0.language == selectedLanguage }
        
        // Filter by gender if selected
        if let gender = selectedGender {
            voices = voices.filter { $0.gender == gender }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            voices = voices.filter { voice in
                voice.displayName.localizedCaseInsensitiveContains(searchText) ||
                voice.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return voices.sorted { $0.displayName < $1.displayName }
    }
    
    private var languageGroupedVoices: [(Language, [VoiceStyle])] {
        let allVoices = searchText.isEmpty && selectedGender == nil ? 
            VoiceStyle.allCases : 
            VoiceStyle.allCases.filter { voice in
                let matchesGender = selectedGender == nil || voice.gender == selectedGender!
                let matchesSearch = searchText.isEmpty || 
                    voice.displayName.localizedCaseInsensitiveContains(searchText) ||
                    voice.rawValue.localizedCaseInsensitiveContains(searchText)
                return matchesGender && matchesSearch
            }
        
        let grouped = Dictionary(grouping: allVoices) { $0.language }
        return grouped.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { (key, value) in (key, value.sorted { $0.displayName < $1.displayName }) }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Language selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Language")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(Language.allCases, id: \.self) { language in
                                Button(action: {
                                    selectedLanguage = language
                                    // Auto-select first voice of the language if current voice doesn't match
                                    let voicesForLanguage = VoiceStyle.voices(for: language)
                                    if !voicesForLanguage.contains(selectedVoice), let firstVoice = voicesForLanguage.first {
                                        selectedVoice = firstVoice
                                    }
                                }) {
                                    VStack(spacing: 4) {
                                        Text(languageFlag(for: language))
                                            .font(.system(size: 20))
                                        
                                        Text(language.rawValue.uppercased())
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedLanguage == language ? Color.accentColor : Color.gray.opacity(0.2))
                                    )
                                    .foregroundColor(selectedLanguage == language ? .white : .primary)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
                
                Divider()
                
                // Search and filters
                VStack(spacing: 12) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Search voices...", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        if !searchText.isEmpty {
                            Button("Clear") {
                                searchText = ""
                            }
                            .font(.caption)
                        }
                    }
                    
                    // Gender filter
                    HStack {
                        Text("Gender:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Button("All") {
                            selectedGender = nil
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedGender == nil ? Color.accentColor : Color.gray.opacity(0.2))
                        .foregroundColor(selectedGender == nil ? .white : .primary)
                        .cornerRadius(6)
                        
                        ForEach(Gender.allCases, id: \.self) { gender in
                            Button(gender.displayName) {
                                selectedGender = gender
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedGender == gender ? Color.accentColor : Color.gray.opacity(0.2))
                            .foregroundColor(selectedGender == gender ? .white : .primary)
                            .cornerRadius(6)
                        }
                        
                        Spacer()
                    }
                    .font(.caption)
                }
                .padding()
                
                Divider()
                
                // Speed control
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Speed: \(speed, specifier: "%.1f")x")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Button("Reset") {
                            speed = 1.0
                        }
                        .font(.caption)
                        .disabled(speed == 1.0)
                    }
                    
                    HStack {
                        Text("0.5x")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Slider(value: $speed, in: 0.5...2.0, step: 0.1)
                        
                        Text("2.0x")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding()

                Divider()

                // Compute Units selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Compute Units")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Choose which processor to use for inference")
                        .font(.caption)
                        .foregroundColor(.gray)

                    VStack(spacing: 8) {
                        ComputeUnitsButton(
                            title: "All (Automatic)",
                            description: "Let the system choose the best option",
                            icon: "sparkles",
                            isSelected: computeUnits == .all,
                            action: { computeUnits = .all }
                        )

                        ComputeUnitsButton(
                            title: "CPU & Neural Engine",
                            description: "Use CPU and Neural Engine only",
                            icon: "cpu",
                            isSelected: computeUnits == .cpuAndNeuralEngine,
                            action: { computeUnits = .cpuAndNeuralEngine }
                        )

                        ComputeUnitsButton(
                            title: "CPU & GPU",
                            description: "Use CPU and GPU only",
                            icon: "memorychip",
                            isSelected: computeUnits == .cpuAndGPU,
                            action: { computeUnits = .cpuAndGPU }
                        )

                        ComputeUnitsButton(
                            title: "CPU Only",
                            description: "Use CPU for all processing",
                            icon: "cpu.fill",
                            isSelected: computeUnits == .cpuOnly,
                            action: { computeUnits = .cpuOnly }
                        )
                    }
                }
                .padding()

                Divider()

                // Voice list
                List {
                    if searchText.isEmpty && selectedGender == nil {
                        // Show all languages with voices when no filters applied
                        ForEach(languageGroupedVoices, id: \.0) { language, voices in
                            Section(header: languageHeader(for: language)) {
                                ForEach(voices, id: \.self) { voice in
                                    VoiceRow(
                                        voice: voice,
                                        isSelected: voice == selectedVoice,
                                        onSelect: { selectedVoice = voice }
                                    )
                                }
                            }
                        }
                    } else {
                        // Show only selected language when language is selected
                        ForEach(filteredVoices, id: \.self) { voice in
                            VoiceRow(
                                voice: voice,
                                isSelected: voice == selectedVoice,
                                onSelect: { selectedVoice = voice }
                            )
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Voice Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func languageFlag(for language: Language) -> String {
        switch language {
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
    
    @ViewBuilder
    private func languageHeader(for language: Language) -> some View {
        HStack {
            Text(languageFlag(for: language))
            
            Text(languageDisplayName(for: language))
                .textCase(.none)
                .fontWeight(.semibold)
            
            Spacer()
            
            let voicesForLanguage = VoiceStyle.voices(for: language)
            Text("(\(voicesForLanguage.count) voices)")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    private func languageDisplayName(for language: Language) -> String {
        switch language {
        case .englishUS:
            return "American English"
        case .englishGB:
            return "British English"
        case .french:
            return "French"
        case .hindi:
            return "Hindi"
        case .japanese:
            return "Japanese"
        case .chinese:
            return "Chinese (Mandarin)"
        case .spanish:
            return "Spanish"
        case .italian:
            return "Italian"
        case .portuguese:
            return "Portuguese (Brazilian)"
        }
    }
}

struct VoiceRow: View {
    let voice: VoiceStyle
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(voice.displayName)
                            .font(.body)
                            .fontWeight(isSelected ? .semibold : .regular)
                        
                        Spacer()
                        
                        // Gender icon
                        Image(systemName: voice.gender == .female ? "person.fill" : "person.fill")
                            .foregroundColor(voice.gender == .female ? .pink : .blue)
                            .font(.caption)
                    }
                    
                    HStack {
                        Text(voice.rawValue)
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        // Language tag
                        Text(voice.language.rawValue.uppercased())
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                        
                    }
                }
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .fontWeight(.semibold)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }
}

struct ComputeUnitsButton: View {
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : .accentColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? .white : .primary)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .gray)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 20))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VoiceSettingsView(
        selectedLanguage: .constant(.englishUS),
        selectedVoice: .constant(.amAdam),
        speed: .constant(1.0),
        computeUnits: .constant(.all)
    )
}