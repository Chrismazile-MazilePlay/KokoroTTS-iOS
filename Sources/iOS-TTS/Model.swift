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
    
    func infer(inputIds: [Int], refS: [Float], speed: Float) throws -> [Float] {
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
        
        print("🔍 BERT input_ids shape: \(inputIdsArray.shape), total elements: \(inputIdsArray.count)")
        print("🔍 BERT attention_mask shape: \(attentionMaskArray.shape)")
        
        let bertOutput = try monitor.measure(PerformanceMonitor.Module.bert) {
            do {
                print("▶️ Calling BERT model...")
                let output = try bert.prediction(from: bertInput)
                print("✅ BERT model completed successfully")
                return output
            } catch {
                print("❌ BERT model failed: \(error)")
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
        
        print("🔍 BERT Encoder bert_dur shape: \(lastHiddenState.shape), total elements: \(lastHiddenState.count)")
        
        let bertEncoderOutput = try monitor.measure(PerformanceMonitor.Module.bertEncoder) {
            do {
                print("▶️ Calling BERT Encoder model...")
                let output = try bertEncoder.prediction(from: bertEncoderInput)
                print("✅ BERT Encoder model completed successfully")
                return output
            } catch {
                print("❌ BERT Encoder model failed: \(error)")
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
        
        print("🔍 Duration Encoder text shape: \(dEn.shape), total elements: \(dEn.count)")
        print("🔍 Duration Encoder style shape: \(styleArray.shape)")
        print("🔍 Duration Encoder mask shape: \(textMaskArray.shape)")
        
        let durationOutput = try monitor.measure(PerformanceMonitor.Module.durationEncoder) {
            do {
                print("▶️ Calling Duration Encoder model...")
                let output = try durationEncoder.prediction(from: durationInput)
                print("✅ Duration Encoder model completed successfully")
                return output
            } catch {
                print("❌ Duration Encoder model failed: \(error)")
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
        
        print("🔍 Prosody Predictor d shape: \(d.shape), total elements: \(d.count)")
        print("🔍 Prosody Predictor speed shape: \(speedArray.shape), value: \(speed)")
        
        let prosodyOutput = try monitor.measure(PerformanceMonitor.Module.prosodyPredictor) {
            do {
                print("▶️ Calling Prosody Predictor model...")
                let output = try prosodyPredictor.prediction(from: prosodyInput)
                print("✅ Prosody Predictor model completed successfully")
                return output
            } catch {
                print("❌ Prosody Predictor model failed: \(error)")
                throw error
            }
        }
        
        guard let predDur = prosodyOutput.featureValue(for: "pred_dur")?.multiArrayValue else {
            throw NSError(domain: "TTSModel", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to get prosody predictor output"])
        }
        
        
        
        // Create alignment indices
        let (_, alignmentMatrix, en) = try monitor.measure(PerformanceMonitor.Module.alignment) {
            print("🔍 Creating alignment with predDur shape: \(predDur.shape), seqLen: \(seqLen)")
            let indices = try createAlignmentIndices(predDur: predDur, seqLen: seqLen)
            print("🔍 Alignment indices count: \(indices.count)")
            let alignmentMatrix = try createAlignmentMatrix(indices: indices, seqLen: seqLen)
            print("🔍 Alignment matrix shape: \(alignmentMatrix.shape), total elements: \(alignmentMatrix.count)")
            let en = try applyAlignment(d: d, alignmentMatrix: alignmentMatrix)
            print("🔍 Final alignment result shape: \(en.shape), total elements: \(en.count)")
            return (indices, alignmentMatrix, en)
        }
        
        // Call F0 Predictor
        let f0Input = try MLDictionaryFeatureProvider(dictionary: [
            "x": MLFeatureValue(multiArray: en),
            "s": MLFeatureValue(multiArray: styleArray),
        ])
        
        print("🔍 F0 Predictor x shape: \(en.shape), total elements: \(en.count)")
        print("🔍 F0 Predictor s shape: \(styleArray.shape)")
        
        let f0Output = try monitor.measure(PerformanceMonitor.Module.f0Predictor) {
            do {
                print("▶️ Calling F0 Predictor model...")
                let output = try f0Predictor.prediction(from: f0Input)
                print("✅ F0 Predictor model completed successfully")
                return output
            } catch {
                print("❌ F0 Predictor model failed: \(error)")
                throw error
            }
        }
        guard let f0Pred = f0Output.featureValue(for: "F0_pred")?.multiArrayValue,
              let nPred = f0Output.featureValue(for: "N_pred")?.multiArrayValue else {
            throw NSError(domain: "TTSModel", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to get F0 predictor output"])
        }
        
        
        // Call Text Encoder
        let textEncoderInput = try MLDictionaryFeatureProvider(dictionary: [
            "x": MLFeatureValue(multiArray: inputIdsArray),
            "m": MLFeatureValue(multiArray: textMaskArray),
        ])
        
        print("🔍 Text Encoder x shape: \(inputIdsArray.shape), total elements: \(inputIdsArray.count)")
        print("🔍 Text Encoder m shape: \(textMaskArray.shape)")
        
        let textEncoderOutput = try monitor.measure(PerformanceMonitor.Module.textEncoder) {
            do {
                print("▶️ Calling Text Encoder model...")
                let output = try textEncoder.prediction(from: textEncoderInput)
                print("✅ Text Encoder model completed successfully")
                return output
            } catch {
                print("❌ Text Encoder model failed: \(error)")
                throw error
            }
        }
        guard let tEn = textEncoderOutput.featureValue(for: "t_en")?.multiArrayValue else {
            throw NSError(domain: "TTSModel", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to get text encoder output"])
        }
        
        // Apply alignment to text encoder output
        // In Python: asr = t_en @ pred_aln_trg (no transpose needed)
        print("🔍 Applying direct alignment to text encoder output")
        print("🔍 Text encoder output shape: \(tEn.shape), total elements: \(tEn.count)")
        let asr = try applyAlignmentDirect(input: tEn, alignmentMatrix: alignmentMatrix)
        print("🔍 ASR result shape: \(asr.shape), total elements: \(asr.count)")
        
        // Prepare reference audio array
        let refAudioArray = try MLMultiArray(shape: [1, 128], dataType: .float32)
        for i in 0..<128 {
            refAudioArray[[0, i as NSNumber]] = NSNumber(value: refAudio[i])
        }
        
        // Call Decoder
        let decoderInput = try MLDictionaryFeatureProvider(dictionary: [
            "asr": MLFeatureValue(multiArray: asr),
            "F0_curve": MLFeatureValue(multiArray: f0Pred),
            "N": MLFeatureValue(multiArray: nPred),
            "s": MLFeatureValue(multiArray: refAudioArray)
        ])
        
        print("🔍 Decoder asr shape: \(asr.shape), total elements: \(asr.count)")
        print("🔍 Decoder F0_curve shape: \(f0Pred.shape), total elements: \(f0Pred.count)")
        print("🔍 Decoder N shape: \(nPred.shape), total elements: \(nPred.count)")
        print("🔍 Decoder s shape: \(refAudioArray.shape)")
        
        let decoderOutput = try monitor.measure(PerformanceMonitor.Module.decoder) {
            do {
                print("▶️ Calling Decoder model...")
                let output = try decoder.prediction(from: decoderInput)
                print("✅ Decoder model completed successfully")
                return output
            } catch {
                print("❌ Decoder model failed: \(error)")
                throw error
            }
        }
        guard let x = decoderOutput.featureValue(for: "x")?.multiArrayValue,
              let _ = decoderOutput.featureValue(for: "s")?.multiArrayValue,
              let _ = decoderOutput.featureValue(for: "F0_curve")?.multiArrayValue else {
            throw NSError(domain: "TTSModel", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to get decoder output"])
        }
        
        
        let s = refAudioArray
        let F0_curve = f0Pred

        // Generate audio using the generator
        print("🔍 Generator x shape: \(x.shape), total elements: \(x.count)")
        print("🔍 Generator s shape: \(s.shape)")
        print("🔍 Generator F0_curve shape: \(F0_curve.shape), total elements: \(F0_curve.count)")
        
        let audio = try monitor.measure(PerformanceMonitor.Module.generator) {
            do {
                print("▶️ Calling Generator...")
                let output = try generator.generate(x: x, s: s, f0Curve: F0_curve)
                print("✅ Generator completed successfully")
                return output
            } catch {
                print("❌ Generator failed: \(error)")
                throw error
            }
        }
        
        return audio
        }
    }
    
    private func splitStyleVector(_ refS: [Float]) -> (refAudio: [Float], style: [Float]) {
        // ref_s[:, :128] - first 128 elements for reference audio
        // ref_s[:, 128:] - last 128 elements for style
        let refAudio = Array(refS.prefix(128))
        let style = Array(refS.suffix(128))
        return (refAudio, style)
    }
    
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
