//
//  Model.swift
//  iOS-TTS
//
//  Created by Marat Zainullin on 10/07/2025.
//

import Foundation
import CoreML
import Accelerate

public class TTSModel {
    private let bert: MLModel
    private let bertEncoder: MLModel
    private let durationEncoder: MLModel
    private let prosodyPredictor: MLModel
    private let f0Predictor: MLModel
    private let textEncoder: MLModel
    private let decoder: MLModel
    private let generator: Generator
    
    private let configuration: MLModelConfiguration
    
    public init(modelPath: URL, configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        self.configuration = configuration
        
        // Load BERT model
        let bertURL = modelPath.appendingPathComponent("Albert.mlmodelc")
        self.bert = try MLModel(contentsOf: bertURL, configuration: configuration)
        
        // Load BERT Encoder
        let bertEncoderURL = modelPath.appendingPathComponent("BertEncoder.mlmodelc")
        self.bertEncoder = try MLModel(contentsOf: bertEncoderURL, configuration: configuration)
        
        // Load Duration Encoder
        let durationEncoderURL = modelPath.appendingPathComponent("DurationEncoder.mlmodelc")
        self.durationEncoder = try MLModel(contentsOf: durationEncoderURL, configuration: configuration)
        
        // Load Prosody Predictor
        let prosodyPredictorURL = modelPath.appendingPathComponent("ProsodyPredictor.mlmodelc")
        self.prosodyPredictor = try MLModel(contentsOf: prosodyPredictorURL, configuration: configuration)
        
        // Load F0 Predictor
        let f0PredictorURL = modelPath.appendingPathComponent("F0Predictor.mlmodelc")
        self.f0Predictor = try MLModel(contentsOf: f0PredictorURL, configuration: configuration)
        
        // Load Text Encoder
        let textEncoderURL = modelPath.appendingPathComponent("TextEncoder.mlmodelc")
        self.textEncoder = try MLModel(contentsOf: textEncoderURL, configuration: configuration)
        
        // Load Decoder
        let decoderURL = modelPath.appendingPathComponent("Decoder.mlmodelc")
        self.decoder = try MLModel(contentsOf: decoderURL, configuration: configuration)
        
        // Load Generator
        self.generator = try Generator(modelPath: modelPath, configuration: configuration)
    }
    
    // MARK: - Main Inference
    
    /// Performs TTS inference with optional pitch modifications.
    ///
    /// - Parameters:
    ///   - inputIds: Phoneme token IDs from G2P conversion
    ///   - refS: Style vector (256 elements: 128 refAudio + 128 style)
    ///   - speed: Speech rate multiplier (0.5-2.0)
    ///   - pitchShiftSemitones: Pitch shift in semitones (-12 to +12)
    ///   - pitchRangeScale: Expressiveness scale (0.5-1.5)
    /// - Returns: Audio samples as Float array
    func infer(
        inputIds: [Int],
        refS: [Float],
        speed: Float,
        pitchShiftSemitones: Float = 0.0,
        pitchRangeScale: Float = 1.0
    ) throws -> [Float] {
        let monitor = PerformanceMonitor.shared
        
        return try monitor.measure(PerformanceMonitor.Module.total) {
            // Batch size is always 1
            let seqLen = inputIds.count
        
            // Create attention mask (all 1s since we have real tokens, no padding)
            let attentionMask = Array(repeating: 1, count: seqLen)
            
            // Create text mask for other models (0s for real tokens, 1s for padding)
            // Since we have no padding, all values are 0
            let textMask = Array(repeating: Float(0), count: seqLen)
            
            // Prepare BERT inputs
            let inputIdsArray = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .float32)
            let attentionMaskArray = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .float32)
            
            // Convert input_ids to Float16
            for i in 0..<seqLen {
                inputIdsArray[[0, i as NSNumber]] = NSNumber(value: Float(inputIds[i]))
                attentionMaskArray[[0, i as NSNumber]] = NSNumber(value: Float(attentionMask[i]))
            }
            
            // Call BERT model
            let bertInput = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: inputIdsArray),
                "attention_mask": MLFeatureValue(multiArray: attentionMaskArray)
            ])
            
            #if DEBUG
            print("BERT input_ids shape: \(inputIdsArray.shape), total elements: \(inputIdsArray.count)")
            print("BERT attention_mask shape: \(attentionMaskArray.shape)")
            #endif
            
            let bertOutput = try monitor.measure(PerformanceMonitor.Module.bert) {
                do {
                    #if DEBUG
                    print("Calling BERT model...")
                    #endif
                    let output = try bert.prediction(from: bertInput)
                    #if DEBUG
                    print("BERT model completed successfully")
                    #endif
                    return output
                } catch {
                    print("BERT model failed: \(error)")
                    throw error
                }
            }
            guard let lastHiddenState = bertOutput.featureValue(for: "last_hidden_state")?.multiArrayValue else {
                throw NSError(domain: "TTSModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get BERT output"])
            }
            
            // Call BERT encoder
            let bertEncoderInput = try MLDictionaryFeatureProvider(dictionary: [
                "bert_dur": MLFeatureValue(multiArray: lastHiddenState)
            ])
            
            #if DEBUG
            print("BERT Encoder bert_dur shape: \(lastHiddenState.shape), total elements: \(lastHiddenState.count)")
            #endif
            
            let bertEncoderOutput = try monitor.measure(PerformanceMonitor.Module.bertEncoder) {
                do {
                    #if DEBUG
                    print("Calling BERT Encoder model...")
                    #endif
                    let output = try bertEncoder.prediction(from: bertEncoderInput)
                    #if DEBUG
                    print("BERT Encoder model completed successfully")
                    #endif
                    return output
                } catch {
                    print("BERT Encoder model failed: \(error)")
                    throw error
                }
            }
            guard let dEnRaw = bertEncoderOutput.featureValue(for: "d_en")?.multiArrayValue else {
                throw NSError(domain: "TTSModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get BERT encoder output"])
            }
            
            // In Python: d_en = self.bert_encoder(bert_dur).transpose(-1, -2)
            // Transpose last two dimensions
            let dEn = try transposeLastTwoDimensions(dEnRaw)
            
            // Split style vector
            let (refAudio, style) = splitStyleVector(refS)
            
            // Prepare text mask for prosody predictor
            let textMaskArray = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .float32)
            for i in 0..<seqLen {
                textMaskArray[[0, i as NSNumber]] = NSNumber(value: textMask[i])
            }
            
            // Prepare style array
            let styleArray = try MLMultiArray(shape: [1, 128], dataType: .float32)
            for i in 0..<128 {
                styleArray[[0, i as NSNumber]] = NSNumber(value: style[i])
            }
            
            // Call Duration Encoder (without speed)
            let durationInput = try MLDictionaryFeatureProvider(dictionary: [
                "text": MLFeatureValue(multiArray: dEn),
                "style": MLFeatureValue(multiArray: styleArray),
                "mask": MLFeatureValue(multiArray: textMaskArray),
            ])
            
            #if DEBUG
            print("Duration Encoder text shape: \(dEn.shape), total elements: \(dEn.count)")
            print("Duration Encoder style shape: \(styleArray.shape)")
            print("Duration Encoder mask shape: \(textMaskArray.shape)")
            #endif
            
            let durationOutput = try monitor.measure(PerformanceMonitor.Module.durationEncoder) {
                do {
                    #if DEBUG
                    print("Calling Duration Encoder model...")
                    #endif
                    let output = try durationEncoder.prediction(from: durationInput)
                    #if DEBUG
                    print("Duration Encoder model completed successfully")
                    #endif
                    return output
                } catch {
                    print("Duration Encoder model failed: \(error)")
                    throw error
                }
            }
            guard let d = durationOutput.featureValue(for: "d")?.multiArrayValue else {
                throw NSError(domain: "TTSModel", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to get duration predictor output"])
            }
            
            // Prepare speed array (tensor of size (1,))
            let speedArray = try MLMultiArray(shape: [1], dataType: .float32)
            speedArray[[0]] = NSNumber(value: speed)
            
            let prosodyInput = try MLDictionaryFeatureProvider(dictionary: [
                "d": MLFeatureValue(multiArray: d),
                "speed": MLFeatureValue(multiArray: speedArray)
            ])
            
            #if DEBUG
            print("Prosody Predictor d shape: \(d.shape), total elements: \(d.count)")
            print("Prosody Predictor speed shape: \(speedArray.shape), value: \(speed)")
            #endif
            
            let prosodyOutput = try monitor.measure(PerformanceMonitor.Module.prosodyPredictor) {
                do {
                    #if DEBUG
                    print("Calling Prosody Predictor model...")
                    #endif
                    let output = try prosodyPredictor.prediction(from: prosodyInput)
                    #if DEBUG
                    print("Prosody Predictor model completed successfully")
                    #endif
                    return output
                } catch {
                    print("Prosody Predictor model failed: \(error)")
                    throw error
                }
            }
            
            guard let predDur = prosodyOutput.featureValue(for: "pred_dur")?.multiArrayValue else {
                throw NSError(domain: "TTSModel", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to get prosody predictor output"])
            }
            
            // Create alignment indices
            let (_, alignmentMatrix, en) = try monitor.measure(PerformanceMonitor.Module.alignment) {
                #if DEBUG
                print("Creating alignment with predDur shape: \(predDur.shape), seqLen: \(seqLen)")
                #endif
                let indices = try createAlignmentIndices(predDur: predDur, seqLen: seqLen)
                #if DEBUG
                print("Alignment indices count: \(indices.count)")
                #endif
                let alignmentMatrix = try createAlignmentMatrix(indices: indices, seqLen: seqLen)
                #if DEBUG
                print("Alignment matrix shape: \(alignmentMatrix.shape), total elements: \(alignmentMatrix.count)")
                #endif
                let en = try applyAlignment(d: d, alignmentMatrix: alignmentMatrix)
                #if DEBUG
                print("Final alignment result shape: \(en.shape), total elements: \(en.count)")
                #endif
                return (indices, alignmentMatrix, en)
            }
            
            // Call F0 Predictor
            let f0Input = try MLDictionaryFeatureProvider(dictionary: [
                "x": MLFeatureValue(multiArray: en),
                "s": MLFeatureValue(multiArray: styleArray),
            ])
            
            #if DEBUG
            print("F0 Predictor x shape: \(en.shape), total elements: \(en.count)")
            print("F0 Predictor s shape: \(styleArray.shape)")
            #endif
            
            let f0Output = try monitor.measure(PerformanceMonitor.Module.f0Predictor) {
                do {
                    #if DEBUG
                    print("Calling F0 Predictor model...")
                    #endif
                    let output = try f0Predictor.prediction(from: f0Input)
                    #if DEBUG
                    print("F0 Predictor model completed successfully")
                    #endif
                    return output
                } catch {
                    print("F0 Predictor model failed: \(error)")
                    throw error
                }
            }
            guard let f0Pred = f0Output.featureValue(for: "F0_pred")?.multiArrayValue,
                  let nPred = f0Output.featureValue(for: "N_pred")?.multiArrayValue else {
                throw NSError(domain: "TTSModel", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to get F0 predictor output"])
            }
            
            // ================================================================
            // Apply pitch modifications to F0 curve
            // ================================================================
            let modifiedF0: MLMultiArray
            if pitchShiftSemitones != 0.0 || pitchRangeScale != 1.0 {
                modifiedF0 = try applyPitchModifications(
                    f0: f0Pred,
                    pitchShiftSemitones: pitchShiftSemitones,
                    pitchRangeScale: pitchRangeScale
                )
                #if DEBUG
                print("Applied pitch modifications: shift=\(pitchShiftSemitones), range=\(pitchRangeScale)")
                #endif
            } else {
                modifiedF0 = f0Pred
            }
            
            // Call Text Encoder
            let textEncoderInput = try MLDictionaryFeatureProvider(dictionary: [
                "x": MLFeatureValue(multiArray: inputIdsArray),
                "m": MLFeatureValue(multiArray: textMaskArray),
            ])
            
            #if DEBUG
            print("Text Encoder x shape: \(inputIdsArray.shape), total elements: \(inputIdsArray.count)")
            print("Text Encoder m shape: \(textMaskArray.shape)")
            #endif
            
            let textEncoderOutput = try monitor.measure(PerformanceMonitor.Module.textEncoder) {
                do {
                    #if DEBUG
                    print("Calling Text Encoder model...")
                    #endif
                    let output = try textEncoder.prediction(from: textEncoderInput)
                    #if DEBUG
                    print("Text Encoder model completed successfully")
                    #endif
                    return output
                } catch {
                    print("Text Encoder model failed: \(error)")
                    throw error
                }
            }
            guard let tEn = textEncoderOutput.featureValue(for: "t_en")?.multiArrayValue else {
                throw NSError(domain: "TTSModel", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to get text encoder output"])
            }
            
            // Apply alignment to text encoder output
            // In Python: asr = t_en @ pred_aln_trg (no transpose needed)
            #if DEBUG
            print("Applying direct alignment to text encoder output")
            print("Text encoder output shape: \(tEn.shape), total elements: \(tEn.count)")
            #endif
            let asr = try applyAlignmentDirect(input: tEn, alignmentMatrix: alignmentMatrix)
            #if DEBUG
            print("ASR result shape: \(asr.shape), total elements: \(asr.count)")
            #endif
            
            // Prepare reference audio array
            let refAudioArray = try MLMultiArray(shape: [1, 128], dataType: .float32)
            for i in 0..<128 {
                refAudioArray[[0, i as NSNumber]] = NSNumber(value: refAudio[i])
            }
            
            // Call Decoder with modified F0
            let decoderInput = try MLDictionaryFeatureProvider(dictionary: [
                "asr": MLFeatureValue(multiArray: asr),
                "F0_curve": MLFeatureValue(multiArray: modifiedF0),
                "N": MLFeatureValue(multiArray: nPred),
                "s": MLFeatureValue(multiArray: refAudioArray)
            ])
            
            #if DEBUG
            print("Decoder asr shape: \(asr.shape), total elements: \(asr.count)")
            print("Decoder F0_curve shape: \(modifiedF0.shape), total elements: \(modifiedF0.count)")
            print("Decoder N shape: \(nPred.shape), total elements: \(nPred.count)")
            print("Decoder s shape: \(refAudioArray.shape)")
            #endif
            
            let decoderOutput = try monitor.measure(PerformanceMonitor.Module.decoder) {
                do {
                    #if DEBUG
                    print("Calling Decoder model...")
                    #endif
                    let output = try decoder.prediction(from: decoderInput)
                    #if DEBUG
                    print("Decoder model completed successfully")
                    #endif
                    return output
                } catch {
                    print("Decoder model failed: \(error)")
                    throw error
                }
            }
            guard let x = decoderOutput.featureValue(for: "x")?.multiArrayValue,
                  let _ = decoderOutput.featureValue(for: "s")?.multiArrayValue,
                  let _ = decoderOutput.featureValue(for: "F0_curve")?.multiArrayValue else {
                throw NSError(domain: "TTSModel", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to get decoder output"])
            }
            
            let s = refAudioArray
            let F0_curve = modifiedF0

            // Generate audio using the generator
            #if DEBUG
            print("Generator x shape: \(x.shape), total elements: \(x.count)")
            print("Generator s shape: \(s.shape)")
            print("Generator F0_curve shape: \(F0_curve.shape), total elements: \(F0_curve.count)")
            #endif
            
            let audio = try monitor.measure(PerformanceMonitor.Module.generator) {
                do {
                    #if DEBUG
                    print("Calling Generator...")
                    #endif
                    let output = try generator.generate(x: x, s: s, f0Curve: F0_curve)
                    #if DEBUG
                    print("Generator completed successfully")
                    #endif
                    return output
                } catch {
                    print("Generator failed: \(error)")
                    throw error
                }
            }
            
            return audio
        }
    }
    
    // MARK: - Pitch Modification
    
    /// Applies pitch shift and range scaling to F0 curve.
    ///
    /// Algorithm:
    /// 1. Calculate mean F0 from voiced frames (f0 > 0)
    /// 2. For each voiced frame:
    ///    - deviation = f0 - mean
    ///    - scaled = mean + (deviation * rangeScale)
    ///    - shifted = scaled * 2^(semitones/12)
    /// 3. Clamp to 50-500 Hz range
    /// 4. Unvoiced frames (f0 == 0) remain zero
    ///
    /// - Parameters:
    ///   - f0: Original F0 curve from F0 Predictor
    ///   - pitchShiftSemitones: Semitones to shift (-12 to +12)
    ///   - pitchRangeScale: Expressiveness multiplier (0.5 to 1.5)
    /// - Returns: Modified F0 curve as MLMultiArray
    private func applyPitchModifications(
        f0: MLMultiArray,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float
    ) throws -> MLMultiArray {
        let count = f0.count
        
        // Create output array with same shape
        let modified = try MLMultiArray(shape: f0.shape, dataType: f0.dataType)
        
        // Get data pointers
        let srcPointer = f0.dataPointer.bindMemory(to: Float32.self, capacity: count)
        let dstPointer = modified.dataPointer.bindMemory(to: Float32.self, capacity: count)
        
        // Step 1: Calculate mean F0 from voiced frames
        var sum: Float = 0.0
        var voicedCount: Int = 0
        
        for i in 0..<count {
            let value = srcPointer[i]
            if value > 0 {
                sum += value
                voicedCount += 1
            }
        }
        
        // Edge case: no voiced frames
        guard voicedCount > 0 else {
            // Copy unchanged
            memcpy(dstPointer, srcPointer, count * MemoryLayout<Float32>.size)
            return modified
        }
        
        let meanF0 = sum / Float(voicedCount)
        
        // Step 2: Calculate pitch multiplier from semitones
        // frequency_ratio = 2^(semitones/12)
        let pitchMultiplier = powf(2.0, pitchShiftSemitones / 12.0)
        
        // Step 3: Apply modifications to each frame
        for i in 0..<count {
            let original = srcPointer[i]
            
            if original > 0 {
                // Voiced frame: apply range scaling and pitch shift
                let deviation = original - meanF0
                let scaledDeviation = deviation * pitchRangeScale
                let rangeScaled = meanF0 + scaledDeviation
                let shifted = rangeScaled * pitchMultiplier
                
                // Clamp to reasonable range (50-500 Hz)
                let clamped = max(50.0, min(500.0, shifted))
                dstPointer[i] = clamped
            } else {
                // Unvoiced frame: keep as zero
                dstPointer[i] = 0.0
            }
        }
        
        return modified
    }
    
    // MARK: - Style Vector Processing
    
    private func splitStyleVector(_ refS: [Float]) -> (refAudio: [Float], style: [Float]) {
        // ref_s[:, :128] - first 128 elements for reference audio
        // ref_s[:, 128:] - last 128 elements for style
        let refAudio = Array(refS.prefix(128))
        let style = Array(refS.suffix(128))
        return (refAudio, style)
    }
    
    // MARK: - Alignment
    
    private func createAlignmentIndices(predDur: MLMultiArray, seqLen: Int) throws -> [Int] {
        // Convert pred_dur to integer durations
        var durations: [Int] = []
        for i in 0..<seqLen {
            let durValue = predDur[[i as NSNumber]].floatValue
            durations.append(Int(durValue))
        }
        
        // Create indices array by repeating each index by its duration
        // Equivalent to torch.repeat_interleave(torch.arange(seqLen), pred_dur)
        var indices: [Int] = []
        for (index, duration) in durations.enumerated() {
            for _ in 0..<duration {
                indices.append(index)
            }
        }
        
        return indices
    }
    
    private func createAlignmentMatrix(indices: [Int], seqLen: Int) throws -> MLMultiArray {
        // Create alignment matrix of shape [1, seqLen, totalDuration]
        let totalDuration = indices.count
        let alignmentMatrix = try MLMultiArray(shape: [1, NSNumber(value: seqLen), NSNumber(value: totalDuration)], dataType: .float32)
        
        // Initialize with zeros
        let dataPointer = alignmentMatrix.dataPointer.bindMemory(to: Float32.self, capacity: alignmentMatrix.count)
        for i in 0..<alignmentMatrix.count {
            dataPointer[i] = 0.0
        }
        
        // Set 1s at alignment positions
        // pred_aln_trg[indices[i], i] = 1
        for (i, index) in indices.enumerated() {
            alignmentMatrix[[0, index as NSNumber, i as NSNumber]] = NSNumber(value: 1.0)
        }
        
        return alignmentMatrix
    }
    
    private func applyAlignment(d: MLMultiArray, alignmentMatrix: MLMultiArray) throws -> MLMultiArray {
        // In Python: en = d.transpose(-1, -2) @ pred_aln_trg
        // d shape: [1, seqLen, hiddenDim] needs to be transposed to [1, hiddenDim, seqLen]
        // alignmentMatrix shape: [1, seqLen, totalDuration]
        // Result should be: [1, hiddenDim, totalDuration]
        
        let seqLen = d.shape[1].intValue
        let hiddenDim = d.shape[2].intValue
        let totalDuration = alignmentMatrix.shape[2].intValue
        
        // First transpose d from [1, seqLen, hiddenDim] to [1, hiddenDim, seqLen]
        let dTransposed = try transposeLastTwoDimensions(d)
        
        // Create result array
        let result = try MLMultiArray(shape: [1, NSNumber(value: hiddenDim), NSNumber(value: totalDuration)], dataType: .float32)
        
        // Get data pointers
        let dPointer = dTransposed.dataPointer.bindMemory(to: Float32.self, capacity: dTransposed.count)
        let alignPointer = alignmentMatrix.dataPointer.bindMemory(to: Float32.self, capacity: alignmentMatrix.count)
        let resultPointer = result.dataPointer.bindMemory(to: Float32.self, capacity: result.count)
        
        // Perform matrix multiplication: dTransposed[hiddenDim x seqLen] @ alignmentMatrix[seqLen x totalDuration]
        // Using BLAS gemm: C = alpha * A * B + beta * C
        cblas_sgemm(
            CblasRowMajor,           // Row major storage
            CblasNoTrans,            // Don't transpose A (dTransposed)
            CblasNoTrans,            // Don't transpose B (alignmentMatrix)
            Int32(hiddenDim),        // M: rows of A and C
            Int32(totalDuration),    // N: columns of B and C
            Int32(seqLen),           // K: columns of A, rows of B
            1.0,                     // alpha
            dPointer,                // A: dTransposed matrix
            Int32(seqLen),           // Leading dimension of A
            alignPointer,            // B: alignment matrix (skip batch dimension)
            Int32(totalDuration),    // Leading dimension of B
            0.0,                     // beta
            resultPointer,           // C: result matrix
            Int32(totalDuration)     // Leading dimension of C
        )
        
        return result
    }
    
    private func applyAlignmentDirect(input: MLMultiArray, alignmentMatrix: MLMultiArray) throws -> MLMultiArray {
        // Direct matrix multiplication without transpose
        // input shape: [1, hiddenDim, seqLen]
        // alignmentMatrix shape: [1, seqLen, totalDuration]
        // Result should be: [1, hiddenDim, totalDuration]
        
        let hiddenDim = input.shape[1].intValue
        let seqLen = input.shape[2].intValue
        let totalDuration = alignmentMatrix.shape[2].intValue
        
        // Create result array
        let result = try MLMultiArray(shape: [1, NSNumber(value: hiddenDim), NSNumber(value: totalDuration)], dataType: .float32)
        
        // Get data pointers
        let inputPointer = input.dataPointer.bindMemory(to: Float32.self, capacity: input.count)
        let alignPointer = alignmentMatrix.dataPointer.bindMemory(to: Float32.self, capacity: alignmentMatrix.count)
        let resultPointer = result.dataPointer.bindMemory(to: Float32.self, capacity: result.count)
        
        // Perform matrix multiplication: input[hiddenDim x seqLen] @ alignmentMatrix[seqLen x totalDuration]
        cblas_sgemm(
            CblasRowMajor,           // Row major storage
            CblasNoTrans,            // Don't transpose A (input)
            CblasNoTrans,            // Don't transpose B (alignmentMatrix)
            Int32(hiddenDim),        // M: rows of A and C
            Int32(totalDuration),    // N: columns of B and C
            Int32(seqLen),           // K: columns of A, rows of B
            1.0,                     // alpha
            inputPointer,            // A: input matrix
            Int32(seqLen),           // Leading dimension of A
            alignPointer,            // B: alignment matrix
            Int32(totalDuration),    // Leading dimension of B
            0.0,                     // beta
            resultPointer,           // C: result matrix
            Int32(totalDuration)     // Leading dimension of C
        )
        
        return result
    }
    
    // MARK: - Tensor Operations
    
    /// Optimized transpose using vDSP
    private func transposeLastTwoDimensions(_ array: MLMultiArray) throws -> MLMultiArray {
        let batch = array.shape[0].intValue
        let dim1 = array.shape[1].intValue
        let dim2 = array.shape[2].intValue
        
        let transposed = try MLMultiArray(shape: [NSNumber(value: batch), NSNumber(value: dim2), NSNumber(value: dim1)],
                                         dataType: array.dataType)
        
        let sourcePointer = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)
        let destPointer = transposed.dataPointer.bindMemory(to: Float32.self, capacity: transposed.count)
        
        // Use vDSP_mtrans for matrix transpose
        vDSP_mtrans(sourcePointer, 1, destPointer, 1, vDSP_Length(dim2), vDSP_Length(dim1))
        
        return transposed
    }
}
