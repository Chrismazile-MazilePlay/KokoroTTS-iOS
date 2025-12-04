//
//  NPYParser.swift
//  iOS-TTS
//
//  Created by Marat Zainullin on 10/07/2025.
//

import Foundation

public struct NPYParser {
    public static func loadArray(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return try parseNPY(data: data)
    }
    
    private static func parseNPY(data: Data) throws -> [Float] {
        // NPY file format:
        // - Magic string: "\x93NUMPY" (6 bytes)
        // - Major version: 1 byte
        // - Minor version: 1 byte  
        // - Header length: 2 bytes (little endian)
        // - Header: Python dict as string
        // - Data: binary array data
        
        guard data.count >= 10 else {
            throw NPYError.invalidFormat("File too small")
        }
        
        // Check magic string
        let magic = data.subdata(in: 0..<6)
        let expectedMagic = Data([0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]) // "\x93NUMPY"
        guard magic == expectedMagic else {
            throw NPYError.invalidFormat("Invalid magic string")
        }
        
        // Read version
        let majorVersion = data[6]
        let minorVersion = data[7]
        
        guard majorVersion == 1 else {
            throw NPYError.unsupportedVersion("Unsupported major version: \(majorVersion)")
        }
        
        // Read header length (little endian)
        let headerLength = data.withUnsafeBytes { bytes in
            let headerLengthBytes = bytes.bindMemory(to: UInt16.self)
            return UInt16(littleEndian: headerLengthBytes[4]) // bytes 8-9
        }
        
        // Skip header for now and go directly to data
        // We assume it's float32 array with shape that we can determine from data size
        let headerEndIndex = 10 + Int(headerLength)
        
        guard headerEndIndex < data.count else {
            throw NPYError.invalidFormat("Header extends beyond file")
        }
        
        let arrayData = data.subdata(in: headerEndIndex..<data.count)
        
        // Convert bytes to Float32 array (assuming little endian float32)
        let floatCount = arrayData.count / 4
        guard arrayData.count % 4 == 0 else {
            throw NPYError.invalidFormat("Data size not divisible by 4 (not float32)")
        }
        
        var floats: [Float] = []
        floats.reserveCapacity(floatCount)
        
        arrayData.withUnsafeBytes { bytes in
            let floatBytes = bytes.bindMemory(to: Float32.self)
            for i in 0..<floatCount {
                // Read float value (assuming little endian)
                let value = floatBytes[i]
                floats.append(Float(value))
            }
        }
        
        return floats
    }
}

public enum NPYError: Error, LocalizedError {
    case invalidFormat(String)
    case unsupportedVersion(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return "Invalid NPY format: \(message)"
        case .unsupportedVersion(let message):
            return "Unsupported NPY version: \(message)"
        }
    }
}