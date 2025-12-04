import Foundation
import CoreML
import RosaKit
import Accelerate

/// Optimized STFT implementation using RosaKit library with precomputed values
class RosaKitSTFT {
    private let filterLength: Int
    private let hopLength: Int
    private let winLength: Int
    public let window: [Float]
    
    // Precomputed values
    private let windowDouble: [Double]
    private let twoPi: Double = 2.0 * Double.pi
    
    init(filterLength: Int = 800, hopLength: Int = 200, winLength: Int = 800) {
        self.filterLength = filterLength
        self.hopLength = hopLength
        self.winLength = winLength
        
        // Generate and cache Hann window
        self.window = RosaKitSTFT.generateHannWindow(length: winLength)
        self.windowDouble = self.window.map { Double($0) }
    }
    
    /// Generate Hann window (periodic=True)
    private static func generateHannWindow(length: Int) -> [Float] {
        var window = [Float](repeating: 0, count: length)
        for i in 0..<length {
            let angle = 2.0 * Float.pi * Float(i) / Float(length)
            window[i] = 0.5 * (1.0 - cos(angle))
        }
        return window
    }
    
    /// Transform audio to magnitude and phase spectrograms using RosaKit
    func transform(_ inputData: MLMultiArray) throws -> (magnitude: MLMultiArray, phase: MLMultiArray) {
        let shape = inputData.shape
        let batchSize = shape[0].intValue
        
        // Extract audio data with optimized memory access
        let audioLength: Int
        var audio1D: [Double]
        
        if shape.count == 3 {
            audioLength = shape[2].intValue
            audio1D = [Double](repeating: 0, count: audioLength)
            let dataPointer = inputData.dataPointer.bindMemory(to: Float32.self, capacity: inputData.count)
            
            // Convert Float32 to Double using vDSP
            var floatArray = [Float](repeating: 0, count: audioLength)
            for i in 0..<audioLength {
                floatArray[i] = dataPointer[i]
            }
            vDSP_vspdp(floatArray, 1, &audio1D, 1, vDSP_Length(audioLength))
        } else if shape.count == 2 {
            audioLength = shape[1].intValue
            audio1D = [Double](repeating: 0, count: audioLength)
            let dataPointer = inputData.dataPointer.bindMemory(to: Float32.self, capacity: inputData.count)
            
            // Convert Float32 to Double using vDSP
            var floatArray = [Float](repeating: 0, count: audioLength)
            for i in 0..<audioLength {
                floatArray[i] = dataPointer[i]
            }
            vDSP_vspdp(floatArray, 1, &audio1D, 1, vDSP_Length(audioLength))
        } else {
            throw TTSError.invalidInput("Unsupported input shape: \(shape)")
        }
        
        // Use RosaKit STFT
        let complexSpectogram = audio1D.stft(nFFT: filterLength, hopLength: hopLength)
        
        // Convert complex spectrogram to magnitude and phase
        let freqBins = complexSpectogram.count
        let numFrames = complexSpectogram.first?.count ?? 0
        
        let magnitude = try MLMultiArray(shape: [NSNumber(value: batchSize), NSNumber(value: freqBins), NSNumber(value: numFrames)], dataType: .float32)
        let phase = try MLMultiArray(shape: [NSNumber(value: batchSize), NSNumber(value: freqBins), NSNumber(value: numFrames)], dataType: .float32)
        
        let magPointer = magnitude.dataPointer.bindMemory(to: Float32.self, capacity: magnitude.count)
        let phasePointer = phase.dataPointer.bindMemory(to: Float32.self, capacity: phase.count)
        
        // Optimized conversion using direct pointer access
        var idx = 0
        for freqIdx in 0..<freqBins {
            for frameIdx in 0..<numFrames {
                let complex = complexSpectogram[freqIdx][frameIdx]
                let real = complex.real
                let imag = complex.imagine
                
                // Compute magnitude and phase
                let mag = sqrt(real * real + imag * imag)
                let ph = atan2(imag, real)
                
                magPointer[idx] = Float(mag)
                phasePointer[idx] = Float(ph)
                idx += 1
            }
        }
        
        return (magnitude, phase)
    }
    
    /// Inverse transform using RosaKit ISTFT - optimized version
    func inverse(_ magnitude: MLMultiArray, _ phase: MLMultiArray) throws -> MLMultiArray {
        let freqBins = magnitude.shape[1].intValue
        let numFrames = magnitude.shape[2].intValue
        
        let magPointer = magnitude.dataPointer.bindMemory(to: Float32.self, capacity: magnitude.count)
        let phasePointer = phase.dataPointer.bindMemory(to: Float32.self, capacity: phase.count)
        
        // Convert magnitude and phase back to complex format for RosaKit
        var complexSpectrogram = [[(real: Double, imagine: Double)]]()
        complexSpectrogram.reserveCapacity(freqBins)
        
        // Pre-allocate arrays for better performance
        var idx = 0
        for freqIdx in 0..<freqBins {
            var frameArray = [(real: Double, imagine: Double)]()
            frameArray.reserveCapacity(numFrames)
            
            for frameIdx in 0..<numFrames {
                let mag = Double(magPointer[idx])
                let ph = Double(phasePointer[idx])
                
                // Use sincos for better performance
                var sinVal: Double = 0
                var cosVal: Double = 0
                __sincos(ph, &sinVal, &cosVal)
                
                let real = mag * cosVal
                let imag = mag * sinVal
                
                frameArray.append((real: real, imagine: imag))
                idx += 1
            }
            complexSpectrogram.append(frameArray)
        }
        
        // Use RosaKit ISTFT
        let audioDouble = complexSpectrogram.istft(hopLength: hopLength)
        
        // Convert to Float and create MLMultiArray
        let audioLength = audioDouble.count
        let result = try MLMultiArray(shape: [1, 1, NSNumber(value: audioLength)], dataType: .float32)
        let resultPointer = result.dataPointer.bindMemory(to: Float32.self, capacity: result.count)
        
        // Convert Double to Float using vDSP
        var audioFloat = [Float](repeating: 0, count: audioLength)
        vDSP_vdpsp(audioDouble, 1, &audioFloat, 1, vDSP_Length(audioLength))
        
        // Copy to result
        for i in 0..<audioLength {
            resultPointer[i] = audioFloat[i]
        }
        
        return result
    }
}