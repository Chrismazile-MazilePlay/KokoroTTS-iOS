//
//  EspeakWrapper.c
//  Imprint-Becoming You
//
//  Thread-safe wrapper for eSpeak-NG phoneme conversion.
//
//  IMPORTANT: eSpeak-NG is NOT thread-safe. It uses internal static buffers
//  that get corrupted when called from multiple threads simultaneously.
//  This wrapper uses a pthread mutex to serialize all eSpeak calls.
//

#include "EspeakWrapper.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <pthread.h>
#include <TargetConditionals.h>

// Only include espeak headers on real device (not simulator)
#if !TARGET_OS_SIMULATOR
#include <espeak-ng/speak_lib.h>
#endif

// =============================================================================
// MARK: - Thread Safety
// =============================================================================

/// Mutex to serialize all eSpeak calls.
/// eSpeak uses internal static buffers and is NOT thread-safe.
static pthread_mutex_t espeak_mutex = PTHREAD_MUTEX_INITIALIZER;

/// Initialization state (protected by espeak_mutex)
static int is_initialized = 0;

/// Static buffer for phoneme output (protected by espeak_mutex)
/// Safe to use static buffer since we hold the lock while copying from it.
static char phoneme_buffer[4096];

// =============================================================================
// MARK: - Simulator Stubs
// =============================================================================

#if TARGET_OS_SIMULATOR

// Stub implementations for iOS Simulator
// The espeak-ng xcframework doesn't include simulator architectures,
// so we provide no-op stubs that gracefully fail.

int espeak_wrapper_initialize_with_bundle(void) {
    // Always return failure on simulator - eSpeak not available
    return 0;
}

int espeak_wrapper_initialize_with_path(const char* data_path) {
    // Always return failure on simulator - eSpeak not available
    (void)data_path;  // Silence unused parameter warning
    return 0;
}

EspeakResult espeak_wrapper_text_to_phonemes(const char* text, const char* language) {
    // Return empty result on simulator - eSpeak not available
    (void)text;      // Silence unused parameter warning
    (void)language;  // Silence unused parameter warning
    
    EspeakResult result = {0, NULL};
    return result;
}

void espeak_wrapper_cleanup(void) {
    // No-op on simulator
}

#else

// =============================================================================
// MARK: - Real Device Implementation
// =============================================================================

/// Internal initialization function (must be called with mutex held)
static int initialize_internal(const char* data_path) {
    if (is_initialized) {
        return 1; // Already initialized
    }
    
    // Check if path exists (if provided)
    if (data_path != NULL) {
        if (access(data_path, F_OK) != 0) {
            return 0; // Path doesn't exist
        }
    }
    
    // Try to initialize with the provided path
    // AUDIO_OUTPUT_SYNCH_PLAYBACK = synchronous mode (no audio output)
    int result = espeak_Initialize(AUDIO_OUTPUT_SYNCH_PLAYBACK, 500, data_path, 0);
    
    if (result > 0) {  // Success (returns sample rate on success)
        is_initialized = 1;
        return 1;
    }
    
    return 0;  // Initialization failed
}

int espeak_wrapper_initialize_with_bundle(void) {
    int result = 0;
    
    pthread_mutex_lock(&espeak_mutex);
    
    if (is_initialized) {
        pthread_mutex_unlock(&espeak_mutex);
        return 1; // Already initialized
    }
    
    // Try multiple paths for espeak-ng-data
    const char* paths[] = {
        "Sources/iOS-TTS/Espeak/espeak-ng-data",  // Development path
        "/usr/local/share/espeak-ng-data",         // System installation
        "./espeak-ng-data",                        // Current directory
        NULL                                       // Sentinel
    };
    
    // Try each path until one works
    for (int i = 0; paths[i] != NULL; i++) {
        if (initialize_internal(paths[i])) {
            result = 1;
            break;
        }
    }
    
    // If all explicit paths failed, try with NULL (system default)
    if (!result && !is_initialized) {
        result = initialize_internal(NULL);
    }
    
    pthread_mutex_unlock(&espeak_mutex);
    return result;
}

int espeak_wrapper_initialize_with_path(const char* data_path) {
    int result = 0;
    
    pthread_mutex_lock(&espeak_mutex);
    result = initialize_internal(data_path);
    pthread_mutex_unlock(&espeak_mutex);
    
    return result;
}

EspeakResult espeak_wrapper_text_to_phonemes(const char* text, const char* language) {
    EspeakResult result = {0, NULL};
    
    // Validate inputs before acquiring lock
    if (!text || !language) {
        return result;
    }
    
    // Limit input length to prevent buffer issues
    size_t text_len = strlen(text);
    if (text_len == 0 || text_len > 2048) {
        return result;
    }
    
    pthread_mutex_lock(&espeak_mutex);
    
    // Initialize if needed (with lock held)
    if (!is_initialized) {
        if (!initialize_internal(NULL)) {
            // Try bundle path as fallback
            const char* bundle_paths[] = {
                "Sources/iOS-TTS/Espeak/espeak-ng-data",
                "./espeak-ng-data",
                NULL
            };
            
            int init_ok = 0;
            for (int i = 0; bundle_paths[i] != NULL; i++) {
                if (initialize_internal(bundle_paths[i])) {
                    init_ok = 1;
                    break;
                }
            }
            
            if (!init_ok) {
                pthread_mutex_unlock(&espeak_mutex);
                return result;
            }
        }
    }
    
    // Set voice for the specified language
    // This modifies internal eSpeak state, must be protected
    espeak_ERROR voice_result = espeak_SetVoiceByName(language);
    if (voice_result != EE_OK) {
        // Try fallback to generic English
        voice_result = espeak_SetVoiceByName("en");
        if (voice_result != EE_OK) {
            pthread_mutex_unlock(&espeak_mutex);
            return result;
        }
    }
    
    // Synthesize first to ensure proper initialization of internal state
    // This is required for accurate phoneme conversion
    espeak_ERROR synth_result = espeak_Synth(
        text,
        (unsigned int)(text_len + 1),  // Include null terminator
        0,                              // Position
        POS_CHARACTER,                  // Position type
        0,                              // End position (0 = no end)
        espeakCHARS_AUTO,              // Flags
        NULL,                           // Unique identifier
        NULL                            // User data
    );
    
    if (synth_result != EE_OK) {
        // Synth failed, but we can still try phoneme conversion
        // Some texts may fail synth but still convert to phonemes
    }
    
    // Convert text to phonemes
    // espeak_TextToPhonemes modifies the text pointer as it processes
    const void* text_ptr = (const void*)text;
    int text_mode = espeakCHARS_UTF8;  // UTF-8 encoding
    
    // phonemes_mode options:
    // 0 = espeakPHONEMES_SHOW (IPA phonemes)
    // 1 = espeakPHONEMES_TRACE (with ties)
    // 2 = espeakPHONEMES_MBROLA (MBROLA format)
    // We use mode 2 which gives us proper IPA symbols
    int phonemes_mode = 2;
    
    const char* phonemes = espeak_TextToPhonemes(&text_ptr, text_mode, phonemes_mode);
    
    if (phonemes != NULL && strlen(phonemes) > 0) {
        // Copy to our static buffer while we still hold the lock
        // This is safe because no other thread can modify phoneme_buffer
        size_t phoneme_len = strlen(phonemes);
        if (phoneme_len < sizeof(phoneme_buffer)) {
            strncpy(phoneme_buffer, phonemes, sizeof(phoneme_buffer) - 1);
            phoneme_buffer[sizeof(phoneme_buffer) - 1] = '\0';
            
            result.success = 1;
            result.phonemes = phoneme_buffer;
        }
    }
    
    pthread_mutex_unlock(&espeak_mutex);
    
    // Note: result.phonemes points to phoneme_buffer which is static.
    // The caller must copy the string if they need to keep it beyond
    // the next call to this function. However, since all calls are
    // serialized by the mutex, the buffer is valid until the next call.
    // In practice, Kokoro copies the phonemes immediately after this returns.
    
    return result;
}

void espeak_wrapper_cleanup(void) {
    pthread_mutex_lock(&espeak_mutex);
    
    if (is_initialized) {
        espeak_Terminate();
        is_initialized = 0;
    }
    
    pthread_mutex_unlock(&espeak_mutex);
}

#endif // TARGET_OS_SIMULATOR
