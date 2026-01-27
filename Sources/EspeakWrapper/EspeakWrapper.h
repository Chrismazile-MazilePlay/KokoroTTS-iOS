#ifndef EspeakWrapper_h
#define EspeakWrapper_h

#include <stdio.h>

// Forward declarations for espeak-ng functions
// Based on speak_lib.h from espeak-ng

#ifdef __cplusplus
extern "C" {
#endif

// Initialize espeak-ng with data path
int espeak_ng_InitializePath(const char* path);

// Set voice by name (e.g., "en-us", "fr", "es", etc.)
int espeak_SetVoiceByName(const char* name);

// Convert text to phonemes
const char* espeak_TextToPhonemes(const void** textptr, int textmode, int phonememode);

// Cleanup
void espeak_ng_Terminate(void);

// Wrapper functions for easier Swift integration
typedef struct {
    int success;
    const char* phonemes;
} EspeakResult;

// High-level wrapper function for text to phonemes conversion
// Thread-safe: uses internal mutex to serialize eSpeak calls
EspeakResult espeak_wrapper_text_to_phonemes(const char* text, const char* language);

// Initialize espeak with bundle resources path
// Thread-safe: can be called from any thread
int espeak_wrapper_initialize_with_bundle(void);

// Initialize espeak with specific data path
// Thread-safe: can be called from any thread
int espeak_wrapper_initialize_with_path(const char* data_path);

// Cleanup espeak resources (optional - resources released on process exit)
// Thread-safe: can be called from any thread
void espeak_wrapper_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif /* EspeakWrapper_h */
