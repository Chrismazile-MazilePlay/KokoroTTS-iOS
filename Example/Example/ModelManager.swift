//
//  ModelManager.swift
//  Example
//
//  Created by Marat Zainullin on 10/07/2025.
//

import Foundation
import iOS_TTS
import Combine
import ZIPFoundation
import CoreML

class ModelManager: NSObject, ObservableObject {
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var isModelReady = false
    @Published var errorMessage: String?
    @Published var computeUnits: MLComputeUnits = .all

    private var pipeline: TTSPipeline?
    private let modelURL = "https://firebasestorage.googleapis.com/v0/b/my-project-1494707780868.firebasestorage.app/o/converted.zip?alt=media&token=c27a1359-37c6-4b26-bd7d-8471d409a841"
    private let g2pURL = "https://firebasestorage.googleapis.com/v0/b/my-project-1494707780868.firebasestorage.app/o/v6%2Fg2p.zip?alt=media&token=c42ca3e3-c743-40a0-9f72-9afa5e8007f9"
    private let posModelURL = "https://firebasestorage.googleapis.com/v0/b/my-project-1494707780868.firebasestorage.app/o/quantized-bert-pos-tag.zip?alt=media&token=cd8b9030-8abd-4385-9fb9-9ec27ae5cad7"
    private let espeakDataURL = "https://firebasestorage.googleapis.com/v0/b/my-project-1494707780868.firebasestorage.app/o/v6%2Fespeak-ng-data-complete.zip?alt=media&token=a3f64856-c99f-4104-a04f-a34cde286648"
    
    private var downloadTask: URLSessionDownloadTask?
    private var g2pDownloadTask: URLSessionDownloadTask?
    private var posDownloadTask: URLSessionDownloadTask?
    private var espeakDownloadTask: URLSessionDownloadTask?
    
    var modelsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("TTSModels")
    }
    
    var vocabDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("G2PVocab")
    }
    
    var posModelsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("POSModels")
    }
    
    var espeakDataDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("EspeakData")
    }
    
    
    override init() {
        super.init()
        checkIfModelsExist()
    }
    
    func checkIfModelsExist() {
        let requiredModels = ["Albert.mlmodelc", "BertEncoder.mlmodelc", "ProsodyPredictor.mlmodelc", 
                             "F0Predictor.mlmodelc", "TextEncoder.mlmodelc", "am_adam.npy"]
        
        let allModelsExist = requiredModels.allSatisfy { modelName in
            // Files should be in root directory after extraction
            let modelPath = modelsDirectory.appendingPathComponent(modelName)
            return FileManager.default.fileExists(atPath: modelPath.path)
        }
        
        // Check G2P vocab files
        let requiredG2PFiles = ["en_us_gold.json", "en_gb_gold.json"]
        let allG2PFilesExist = requiredG2PFiles.allSatisfy { fileName in
            let filePath = vocabDirectory.appendingPathComponent(fileName)
            return FileManager.default.fileExists(atPath: filePath.path)
        }
        
        // Check POS models (all files should be in root after extraction)
        let requiredPOSFiles = ["Model.mlmodelc", "outTokens.txt", "vocab.txt"]
        let posModelsExist = requiredPOSFiles.allSatisfy { fileName in
            let filePath = posModelsDirectory.appendingPathComponent(fileName)
            return FileManager.default.fileExists(atPath: filePath.path)
        }
        
        // Check espeak-ng data (files are extracted to root EspeakData directory)
        let requiredEspeakFiles = ["phontab", "phondata", "phonindex"]
        let espeakDataExists = requiredEspeakFiles.allSatisfy { fileName in
            let filePath = espeakDataDirectory.appendingPathComponent(fileName)
            return FileManager.default.fileExists(atPath: filePath.path)
        }
        
        if allModelsExist && allG2PFilesExist && posModelsExist && espeakDataExists {
            do {
                try initializePipeline()
            } catch {
                errorMessage = "Failed to initialize pipeline: \(error.localizedDescription)"
                isModelReady = false
            }
        } else {
            isModelReady = false
        }
    }
    
    func downloadModels() {
        guard let modelURL = URL(string: modelURL),
              let g2pURL = URL(string: g2pURL),
              let posModelURL = URL(string: posModelURL),
              let espeakDataURL = URL(string: espeakDataURL) else {
            errorMessage = "Invalid URL"
            return
        }
        
        isDownloading = true
        errorMessage = nil
        downloadProgress = 0
        
        // Start with espeak data first for faster testing, then models, G2P, POS
        downloadEspeakDataArchive()
    }
    
    private func downloadModelsArchive(from url: URL) {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }
    
    private func downloadG2PArchive() {
        guard let url = URL(string: g2pURL) else {
            errorMessage = "Invalid G2P URL"
            return
        }
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        g2pDownloadTask = session.downloadTask(with: url)
        g2pDownloadTask?.resume()
    }
    
    private func downloadPOSArchive() {
        guard let url = URL(string: posModelURL) else {
            errorMessage = "Invalid POS URL"
            return
        }
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        posDownloadTask = session.downloadTask(with: url)
        posDownloadTask?.resume()
    }
    
    private func downloadEspeakDataArchive() {
        guard let url = URL(string: espeakDataURL) else {
            errorMessage = "Invalid Espeak Data URL"
            return
        }
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        espeakDownloadTask = session.downloadTask(with: url)
        espeakDownloadTask?.resume()
    }
    
    
    func initializePipeline() throws {
        // Initialize real pipeline with downloaded models, vocab, POS models, and espeak data
        // Files are extracted to root EspeakData directory
        let espeakPath = espeakDataDirectory.path
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        pipeline = try TTSPipeline(modelPath: modelsDirectory, vocabURL: vocabDirectory, postaggerModelURL: posModelsDirectory, language: .french, espeakDataPath: espeakPath, configuration: configuration)
        pipeline?.performanceMonitoringEnabled = true  // Enable performance monitoring
        isModelReady = true
    }
    
    /// Переинициализация pipeline с новым языком (при смене голоса/языка)
    func reinitializePipeline(for language: Language) throws {
        pipeline = nil  // Очищаем старый pipeline
        // Files are extracted to root EspeakData directory
        let espeakPath = espeakDataDirectory.path
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        pipeline = try TTSPipeline(modelPath: modelsDirectory, vocabURL: vocabDirectory, postaggerModelURL: posModelsDirectory, language: language, espeakDataPath: espeakPath, configuration: configuration)
        pipeline?.performanceMonitoringEnabled = true
        print("🔄 Pipeline reinitialized for language: \(language.rawValue)")
    }

    /// Изменить computeUnits и переинициализировать pipeline
    func updateComputeUnits(_ newComputeUnits: MLComputeUnits) throws {
        guard let currentLanguage = pipeline?.language else {
            // Если pipeline еще не инициализирован, просто сохраняем настройку
            computeUnits = newComputeUnits
            return
        }

        computeUnits = newComputeUnits
        try reinitializePipeline(for: currentLanguage)
        print("🔄 Pipeline reinitialized with computeUnits: \(newComputeUnits)")
    }
    
    private func createDummyModels() throws {
        let modelNames = ["Albert.mlmodelc", "BertEncoder.mlmodelc", "ProsodyPredictor.mlmodelc", 
                         "F0Predictor.mlmodelc", "TextEncoder.mlmodelc"]
        
        for modelName in modelNames {
            let modelPath = modelsDirectory.appendingPathComponent(modelName)
            try FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)
            
            // Create a dummy metadata.json file
            let metadataPath = modelPath.appendingPathComponent("metadata.json")
            let dummyMetadata = Data("{}".utf8)
            try dummyMetadata.write(to: metadataPath)
        }
    }
    
    func generateSpeech(text: String, options: GenerationOptions = GenerationOptions()) async throws -> [Float] {
        // Проверяем и переинициализируем pipeline если язык не совпадает
        let voiceLanguage = options.style.language
        
        // Если pipeline не инициализирован или язык изменился - переинициализируем
        if pipeline == nil || pipeline?.language != voiceLanguage {
            print("🔄 Reinitializing pipeline: current=\(pipeline?.language.rawValue ?? "nil"), requested=\(voiceLanguage.rawValue)")
            try reinitializePipeline(for: voiceLanguage)
        }
        
        guard let pipeline = pipeline else {
            throw NSError(domain: "ModelManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pipeline not initialized"])
        }
        
        return try await pipeline.generate(text: text, options: options)
        
        // For now, return dummy audio data
//        try await Task.sleep(nanoseconds: 1_000_000_000) // Simulate processing time
//        return Array(repeating: 0.5, count: 1000) // Dummy audio samples
    }
    
    func getPerformanceReport() -> String? {
        return pipeline?.getPerformanceReport()
    }
    
    
    private func unzipFile(at sourceURL: URL, to destinationURL: URL) throws {
        // Create destination directory if needed
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        
        // Use FileManager to unzip with error handling for .DS_Store files
        do {
            try FileManager.default.unzipItem(at: sourceURL, to: destinationURL)
        } catch {
            // If unzip fails, check if it's related to .DS_Store files
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains(".ds_store") || errorString.contains("could not be saved") {
                print("⚠️ Ignoring .DS_Store related error during extraction: \(error.localizedDescription)")
                // Try to continue with partial extraction
            } else {
                throw error // Re-throw if it's a real error
            }
        }
        
        // Clean up .DS_Store files recursively after extraction
        try cleanupDSStoreFiles(in: destinationURL)
    }
    
    private func unzipEspeakFile(at sourceURL: URL, to destinationURL: URL) throws {
        // Create destination directory if needed
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        
        // Use ZIPFoundation for proper directory structure preservation
        let fileManager = FileManager.default
        guard let archive = Archive(url: sourceURL, accessMode: .read) else {
            throw NSError(domain: "UnzipError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot open ZIP archive"])
        }
        
        for entry in archive {
            // Skip the root espeak-ng-data folder - extract its contents to root
            let entryPath = entry.path
            
            // Remove "espeak-ng-data/" prefix if present
            let finalPath: String
            if entryPath.hasPrefix("espeak-ng-data/") {
                finalPath = String(entryPath.dropFirst("espeak-ng-data/".count))
            } else {
                finalPath = entryPath
            }
            
            // Skip empty paths (root directory entry)
            guard !finalPath.isEmpty else { continue }
            
            let destinationEntryURL = destinationURL.appendingPathComponent(finalPath)
            
            // Create intermediate directories if needed
            if entry.type == .directory {
                try fileManager.createDirectory(at: destinationEntryURL, withIntermediateDirectories: true)
            } else {
                // Create parent directory if it doesn't exist
                let parentDirectory = destinationEntryURL.deletingLastPathComponent()
                try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
                
                // Extract file
                _ = try archive.extract(entry, to: destinationEntryURL)
            }
        }
        
        print("✅ Espeak archive extracted with contents moved to EspeakData root")
        
        // Clean up .DS_Store files
        try cleanupDSStoreFiles(in: destinationURL)
    }
    
    
    private func organizeEspeakFiles(in directory: URL) throws {
        // ZIPFoundation preserves directory structure perfectly, just clean up .DS_Store files
        try cleanupDSStoreFiles(in: directory)
        
        print("✅ Espeak files organized successfully (ZIPFoundation preserved structure)")
    }
    
    private func cleanupDSStoreFiles(in directory: URL) throws {
        let fileManager = FileManager.default
        
        // Get all contents recursively, including hidden files to catch .DS_Store
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: []) else {
            return
        }
        
        for case let fileURL as URL in enumerator {
            // Check if it's a .DS_Store file
            if fileURL.lastPathComponent == ".DS_Store" {
                do {
                    if fileManager.fileExists(atPath: fileURL.path) {
                        try fileManager.removeItem(at: fileURL)
                        print("🗑️ Removed .DS_Store file: \(fileURL.relativePath)")
                    }
                } catch {
                    print("⚠️ Failed to remove .DS_Store file: \(error.localizedDescription)")
                }
            }
        }
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if downloadTask == self.downloadTask {
                // Handle models archive download
                // Clean up existing models directory
                if FileManager.default.fileExists(atPath: modelsDirectory.path) {
                    try FileManager.default.removeItem(at: modelsDirectory)
                }
                
                // Create fresh models directory
                try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
                
                // Move zip file to temporary location
                let zipURL = modelsDirectory.appendingPathComponent("models.zip")
                try FileManager.default.moveItem(at: location, to: zipURL)
                
                // Unzip
                try unzipFile(at: zipURL, to: modelsDirectory)
                
                // Clean up zip file
                try FileManager.default.removeItem(at: zipURL)
                
                print("✅ Models downloaded and extracted")
                
                // Start G2P download
                downloadProgress = 0.50 // Half done
                downloadG2PArchive()
                
            } else if downloadTask == self.g2pDownloadTask {
                // Handle G2P vocab archive download
                // Clean up existing vocab directory
                if FileManager.default.fileExists(atPath: vocabDirectory.path) {
                    try FileManager.default.removeItem(at: vocabDirectory)
                }
                
                // Create fresh vocab directory
                try FileManager.default.createDirectory(at: vocabDirectory, withIntermediateDirectories: true)
                
                // Move zip file to temporary location
                let zipURL = vocabDirectory.appendingPathComponent("g2p.zip")
                try FileManager.default.moveItem(at: location, to: zipURL)
                
                // Unzip
                try unzipFile(at: zipURL, to: vocabDirectory)
                
                // Clean up zip file
                try FileManager.default.removeItem(at: zipURL)
                
                print("✅ G2P vocab files downloaded and extracted")
                
                // Start POS download
                downloadProgress = 0.75 // Three quarters done
                downloadPOSArchive()
                
            } else if downloadTask == self.posDownloadTask {
                // Handle POS models archive download
                // Clean up existing POS models directory
                if FileManager.default.fileExists(atPath: posModelsDirectory.path) {
                    try FileManager.default.removeItem(at: posModelsDirectory)
                }
                
                // Create fresh POS models directory
                try FileManager.default.createDirectory(at: posModelsDirectory, withIntermediateDirectories: true)
                
                // Move zip file to temporary location
                let zipURL = posModelsDirectory.appendingPathComponent("pos_models.zip")
                try FileManager.default.moveItem(at: location, to: zipURL)
                
                // Unzip
                try unzipFile(at: zipURL, to: posModelsDirectory)
                
                // Move files from quantized-bert-pos-tag subfolder to root
                let subfolderPath = posModelsDirectory.appendingPathComponent("quantized-bert-pos-tag")
                if FileManager.default.fileExists(atPath: subfolderPath.path) {
                    let contents = try FileManager.default.contentsOfDirectory(at: subfolderPath, includingPropertiesForKeys: nil)
                    for fileURL in contents {
                        let destinationURL = posModelsDirectory.appendingPathComponent(fileURL.lastPathComponent)
                        try FileManager.default.moveItem(at: fileURL, to: destinationURL)
                    }
                    // Remove empty subfolder
                    try FileManager.default.removeItem(at: subfolderPath)
                }
                
                // Clean up zip file
                try FileManager.default.removeItem(at: zipURL)
                
                print("✅ POS Models downloaded and extracted")
                
                // All downloads complete, initialize pipeline
                downloadProgress = 1.0
                try initializePipeline()
                
                isDownloading = false
                
            } else if downloadTask == self.espeakDownloadTask {
                // Handle espeak-ng-data archive download
                // Clean up existing espeak data directory completely
                if FileManager.default.fileExists(atPath: espeakDataDirectory.path) {
                    try FileManager.default.removeItem(at: espeakDataDirectory)
                }
                
                // Create fresh espeak data directory
                try FileManager.default.createDirectory(at: espeakDataDirectory, withIntermediateDirectories: true)
                
                // Move zip file to temporary location
                let zipURL = espeakDataDirectory.appendingPathComponent("espeak_data.zip")
                try FileManager.default.moveItem(at: location, to: zipURL)
                
                // Unzip using ZIPFoundation that preserves directory structure
                try unzipEspeakFile(at: zipURL, to: espeakDataDirectory)
                
                // Clean up zip file
                try FileManager.default.removeItem(at: zipURL)
                
                print("✅ Espeak data downloaded and extracted with proper structure")
                
                // Start models download
                downloadProgress = 0.25 // First quarter done
                guard let modelURL = URL(string: modelURL) else {
                    errorMessage = "Invalid model URL"
                    return
                }
                downloadModelsArchive(from: modelURL)
            }
            
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            isDownloading = false
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        if downloadTask == self.espeakDownloadTask {
            // Espeak download: 0-25%
            downloadProgress = progress * 0.25
        } else if downloadTask == self.downloadTask {
            // Models download: 25-50%
            downloadProgress = 0.25 + (progress * 0.25)
        } else if downloadTask == self.g2pDownloadTask {
            // G2P download: 50-75%
            downloadProgress = 0.50 + (progress * 0.25)
        } else if downloadTask == self.posDownloadTask {
            // POS download: 75-100%
            downloadProgress = 0.75 + (progress * 0.25)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            errorMessage = "Download error: \(error.localizedDescription)"
            isDownloading = false
        }
    }
}
