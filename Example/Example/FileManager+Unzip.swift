//
//  FileManager+Unzip.swift
//  Example
//
//  Created by Marat Zainullin on 10/07/2025.
//

import Foundation
import ZIPFoundation

extension FileManager {
    func unzipItem(at sourceURL: URL, to destinationURL: URL) throws {
        print("DEBUG: Starting ZIP extraction with ZIPFoundation")
        
        // Create destination directory
        try createDirectory(at: destinationURL, withIntermediateDirectories: true)
        
        // Open ZIP archive
        guard let archive = Archive(url: sourceURL, accessMode: .read) else {
            throw NSError(domain: "ZipError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open ZIP archive"])
        }
        
        var extractedCount = 0
        
        // Extract each file
        for entry in archive {
            let fileName = entry.path
            print("DEBUG: Processing entry: \(fileName)")
            
            // Skip directories, __MACOSX files, and ._ files
            if entry.type == .directory || fileName.contains("__MACOSX") || fileName.contains("._") {
                print("DEBUG: Skipping unwanted entry: \(fileName)")
                continue
            }
            
            // Handle .mlmodelc files - preserve directory structure
            let outputURL: URL
            if fileName.contains(".mlmodelc/") {
                // Extract .mlmodelc files with preserved structure
                // Remove "converted/" prefix but keep the rest
                let relativePath = fileName.replacingOccurrences(of: "converted/", with: "")
                outputURL = destinationURL.appendingPathComponent(relativePath)
                
                // Create intermediate directories
                let directory = outputURL.deletingLastPathComponent()
                try createDirectory(at: directory, withIntermediateDirectories: true)
                
                print("DEBUG: Extracting \(fileName) as \(relativePath)")
            } else {
                // Extract other files (like .npy) to root directory
                let justFileName = URL(fileURLWithPath: fileName).lastPathComponent
                outputURL = destinationURL.appendingPathComponent(justFileName)
                print("DEBUG: Extracting \(fileName) as \(justFileName)")
            }
            
            // Extract the file
            _ = try archive.extract(entry, to: outputURL)
            extractedCount += 1
            
            print("DEBUG: Successfully extracted to: \(outputURL.lastPathComponent)")
        }
        
        print("DEBUG: ZIP extraction completed. Extracted \(extractedCount) files")
    }
}