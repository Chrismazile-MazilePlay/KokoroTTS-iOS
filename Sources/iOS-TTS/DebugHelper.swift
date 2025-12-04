import Foundation
import CoreML

extension MLMultiArray {
    /// Save MLMultiArray in NumPy NPY format
    func saveDebug(name: String) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filePath = documentsPath.appendingPathComponent("\(name)_swift.npy")
        
        do {
            let npyData = createNPYData()
            try npyData.write(to: filePath)
            print("Debug saved to: \(filePath.path)")
            print("  Shape: \(shape)")
            print("  DataType: \(dataType)")
            
            // Also save text version for quick inspection
            let textPath = documentsPath.appendingPathComponent("\(name)_swift.txt")
            try createDebugText().write(to: textPath, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save debug data: \(error)")
        }
    }
    
    /// Create NPY format data
    private func createNPYData() -> Data {
        var data = Data()
        
        // NPY format magic number
        data.append(contentsOf: [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]) // \x93NUMPY
        
        // Version 1.0
        data.append(contentsOf: [0x01, 0x00])
        
        // Create header dictionary
        let shapeStr = "(" + shape.map { "\($0.intValue)" }.joined(separator: ", ") + (shape.count == 1 ? ",)" : ")")
        
        let dtype: String
        switch dataType {
        case .float32:
            dtype = "'<f4'"  // Little-endian float32
        case .float64, .double:
            dtype = "'<f8'"  // Little-endian float64
        case .int32:
            dtype = "'<i4'"  // Little-endian int32
        default:
            dtype = "'<f4'"  // Default to float32
        }
        
        let headerDict = "{'descr': \(dtype), 'fortran_order': False, 'shape': \(shapeStr), }"
        
        // Calculate padding to align on 64-byte boundary
        let headerBytes = headerDict.data(using: .ascii)!
        let totalHeaderSize = 10 + headerBytes.count + 1  // 10 = magic(6) + version(2) + header_len(2), 1 = newline
        let padding = (64 - totalHeaderSize % 64) % 64
        let paddedHeader = headerDict + String(repeating: " ", count: padding) + "\n"
        
        // Write header length (little-endian)
        let headerData = paddedHeader.data(using: .ascii)!
        Swift.withUnsafeBytes(of: UInt16(headerData.count).littleEndian) { data.append(contentsOf: $0) }
        
        // Write header
        data.append(headerData)
        
        // Write array data
        let count = shape.reduce(1) { $0 * $1.intValue }
        
        switch dataType {
        case .float32:
            let pointer = dataPointer.bindMemory(to: Float.self, capacity: count)
            data.append(Data(bytes: pointer, count: count * MemoryLayout<Float>.size))
        case .float64, .double:
            let pointer = dataPointer.bindMemory(to: Double.self, capacity: count)
            data.append(Data(bytes: pointer, count: count * MemoryLayout<Double>.size))
        case .int32:
            let pointer = dataPointer.bindMemory(to: Int32.self, capacity: count)
            data.append(Data(bytes: pointer, count: count * MemoryLayout<Int32>.size))
        default:
            // Default to float32
            let pointer = dataPointer.bindMemory(to: Float.self, capacity: count)
            data.append(Data(bytes: pointer, count: count * MemoryLayout<Float>.size))
        }
        
        return data
    }
    
    /// Create debug text for inspection
    private func createDebugText() -> String {
        var result = "Shape: \(shape)\n"
        result += "DataType: \(dataType)\n"
        result += "Strides: \(strides)\n\n"
        
        let totalElements = shape.reduce(1) { $0 * $1.intValue }
        result += "First 100 elements:\n"
        
        for i in 0..<min(100, totalElements) {
            result += "\(i): \(self[i].floatValue)\n"
        }
        
        if totalElements > 100 {
            result += "\n... (\(totalElements - 100) more elements)\n"
        }
        
        // Add statistics
        if totalElements > 0 {
            var sum: Float = 0
            var min: Float = Float.infinity
            var max: Float = -Float.infinity
            
            for i in 0..<totalElements {
                let value = self[i].floatValue
                sum += value
                min = Swift.min(min, value)
                max = Swift.max(max, value)
            }
            
            let mean = sum / Float(totalElements)
            
            result += "\nStatistics:\n"
            result += "Min: \(min)\n"
            result += "Max: \(max)\n"
            result += "Mean: \(mean)\n"
            result += "Sum: \(sum)\n"
        }
        
        return result
    }
}