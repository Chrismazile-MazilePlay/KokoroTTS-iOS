#include "EspeakWrapper.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

// Include espeak headers using header search path from Package.swift
#include <espeak-ng/speak_lib.h>

static int is_initialized = 0;

int espeak_wrapper_initialize_with_bundle(void) {
    if (is_initialized) {
        return 1; // Already initialized
    }
    
    // Try multiple paths for espeak-ng-data
    const char* paths[] = {
        "Sources/iOS-TTS/Espeak/espeak-ng-data",  // Development path
        "/usr/local/share/espeak-ng-data",         // System installation
        "./espeak-ng-data",                        // Current directory
        NULL                                       // Use system default
    };
    
    int result = -1;
    
    // Try each path until one works
    for (int i = 0; paths[i] != NULL || i == 3; i++) {
        const char* data_path = paths[i];
        
        // Check if path exists (except for NULL)
        if (data_path != NULL) {
            if (access(data_path, F_OK) != 0) {
                continue; // Path doesn't exist, try next
            }
        }
        
        // Try to initialize with this path
        result = espeak_Initialize(AUDIO_OUTPUT_SYNCH_PLAYBACK, 500, data_path, 0);
        
        if (result > 0) {  // Success
            is_initialized = 1;
            return 1;
        }
    }
    
    return 0;  // All paths failed
}

int espeak_wrapper_initialize_with_path(const char* data_path) {
    if (is_initialized) {
        return 1; // Already initialized
    }
    
    // Check if path exists
    if (data_path && access(data_path, F_OK) != 0) {
        return 0; // Path doesn't exist
    }
    
    // Try to initialize with the provided path
    int result = espeak_Initialize(AUDIO_OUTPUT_SYNCH_PLAYBACK, 500, data_path, 0);
    
    if (result > 0) {  // Success
        is_initialized = 1;
        return 1;
    }
    
    return 0;  // Initialization failed
}

EspeakResult espeak_wrapper_text_to_phonemes(const char* text, const char* language) {
    EspeakResult result = {0, NULL};
    
    if (!text || !language) {
        return result;
    }
    
    if (!is_initialized) {
        if (!espeak_wrapper_initialize_with_bundle()) {
            return result;
        }
    }
    
    // Set voice for the specified language
    espeak_SetVoiceByName(language);
    
    // First do a synthesis to ensure proper initialization
    espeak_Synth(text, strlen(text), 0, POS_CHARACTER, 0, espeakCHARS_AUTO, NULL, NULL);
    
    // Convert text to phonemes using real espeak
    // Try different phonemes_mode settings to match Python
    const void* text_ptr = (const void*)text;
    int text_mode = 1;  // UTF8 encoding
    
    // phonemes_mode options:
    // 0 = PhonemeOnly (just phonemes)
    // 1 = PhonemeTies (include ties U+0361) 
    // 2 = PhonemeZWJ (include zero-width joiners)
    // 3 = PhonemeUnderscore (separate with underscores)
    
    // Back to mode 2 (PhonemeZWJ) which gave us proper IPA 
    int phonemes_mode = 2;  // PhonemeZWJ for IPA symbols
    const char* phonemes = espeak_TextToPhonemes(&text_ptr, text_mode, phonemes_mode);
    
    if (phonemes && strlen(phonemes) > 0) {
        // Make a static copy since espeak might reuse its internal buffer
        static char phoneme_buffer[2048];
        strncpy(phoneme_buffer, phonemes, sizeof(phoneme_buffer) - 1);
        phoneme_buffer[sizeof(phoneme_buffer) - 1] = '\0';
        
        // DEBUG: Uncomment to see espeak output
        // printf("DEBUG: espeak returned phonemes for '%s' (lang=%s): '%s'\n", text, language, phoneme_buffer);
        
        result.success = 1;
        result.phonemes = phoneme_buffer;
    }
    
    return result;
}