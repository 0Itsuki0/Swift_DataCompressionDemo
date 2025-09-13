

import SwiftUI
import Compression

extension Algorithm {
    var algorithmC: compression_algorithm {
        switch self {
        case .lzfse:
            COMPRESSION_LZFSE
        case .zlib:
            COMPRESSION_ZLIB
        case .lz4:
            COMPRESSION_LZ4
        case .lzma:
            COMPRESSION_LZMA
        case .lzbitmap:
            COMPRESSION_LZBITMAP
        case .brotli:
            COMPRESSION_BROTLI
        @unknown default:
            COMPRESSION_ZLIB
        }
    }
    
    var fileExtension: String {
        switch self {
            
        case .lzfse:
            ".lzfse"
        case .zlib:
            ".zlib"
        case .lz4:
            ".lz4"
        case .lzma:
            ".lzma"
        case .lzbitmap:
            ".lzbitmap"
        case .brotli:
            ".brotli"
        @unknown default:
            ".zlib"
        }
    }
}

class CompressService {
    enum CompressError: Error {
        case failedToCompress
        case failedToGetFilename
    }
    

    private static let destinationDirectory = FileManager.default.temporaryDirectory
    
    
    // 8 MB
    private static let defaultDecompressCapacity = 8_000_000
    
    // InputFilter and OutputFilter instances compress and decompress in pages (chunks)
    //
    // Specify the number of bytes in each page to read from or write to a stream.
    // Smaller values allow your app to report progress or perform other tasks at higher frequencies than larger values.
    // However, larger values allow your app to compress or decompress using fewer steps, possibly in less time.
    private static let streamPageSize = 32_768

    
    // compress with buffer, ie: everything in one step
    static func compressWithBuffer(data: Data, algorithm: Algorithm) throws -> Data {

        // Step 1: create an array of UInt8 from the data
        var sourceBuffer = Array(data)
        let sourceSize = data.count
        
        // Step 2: Create the destination buffer to receive the compressed data
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: sourceSize)
        defer {
            destinationBuffer.deallocate()
        }
        
        // Step 3: Compress the data with a given algorithm
        let compressedSize = compression_encode_buffer(
            destinationBuffer, // Pointer to the buffer that receives the compressed data
            sourceSize, // Size of the destination buffer in bytes
            &sourceBuffer, // Pointer to a buffer containing all of the source data
            sourceSize, // Size of the data in the source buffer in bytes.
            nil,
            algorithm.algorithmC
        )
        
        // If the function can’t compress the entire input to fit into the provided destination buffer, or an error occurs, 0 is returned.
        if compressedSize == 0 {
            print("Compressiong failed.")
            throw CompressError.failedToCompress
        }
        
        // Step 4: Convert bytes to Data
        // NOTE: Data(bytesNoCopy:...) will not work
        return Data(bytes: destinationBuffer, count: compressedSize)

    }
    
    // decompress with buffer
    // uncompressedSize: Size of the uncompressed data in bytes.
    static func decompressWithBuffer(data: Data, uncompressedSize: Int?, algorithm: Algorithm) -> Data {
        let decompressCapacity = uncompressedSize ?? self.defaultDecompressCapacity
        
        // Step 1: Create the destination buffer to receive the decompressed data
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: decompressCapacity)
        defer {
            destinationBuffer.deallocate()
        }
        
        // Step 2: Access the raw bytes in the data’s buffer.
        let decodedBytesCount = data.withUnsafeBytes { encodedSourceBuffer in
            let typedPointer = encodedSourceBuffer.bindMemory(to: UInt8.self)
            
            // Step 3: decompress the data with same algorithm used for compressing
            let decodedBytesCount = compression_decode_buffer(
                destinationBuffer,
                decompressCapacity,
                typedPointer.baseAddress!,
                data.count,
                nil,
                algorithm.algorithmC
            )
            return decodedBytesCount
        }
            
        // Step 4: Convert bytes to Data
        return Data(bytes: destinationBuffer, count: decodedBytesCount)
    }
    
    // stream compress/decompress from data using input filter
    static func compressDecompressWithStreamUsingInputFilter(data: Data, isCompressing: Bool, algorithm: Algorithm) throws -> Data {
    
        let operation: FilterOperation = isCompressing ? .compress : .decompress
        
        // if operation is compress, then the final compressed Data
        // if the operation is decompress, then the final decompressed data
        var processedData = Data()


        var index = 0
        let sourceDataSize = data.count
        
        let inputFilter = try InputFilter(operation, using: algorithm, bufferCapacity: self.streamPageSize, readingFrom: { (length: Int) -> Data? in
            let rangeLength = min(length, sourceDataSize - index)
            let subdata = data.subdata(in: index ..< index + rangeLength)
            index += rangeLength
            return subdata
        })
        
        
        while let page = try inputFilter.readData(ofLength: self.streamPageSize) {
            processedData.append(page)
        }
        

        return processedData
    }
    
    // stream compress/decompress from data using output filter
    static func compressDecompressWithStreamUsingOutputFilter(data: Data, isCompressing: Bool, algorithm: Algorithm) throws -> Data {

        // creating file handle so that we can read data of a specific length
        var compressedData = Data()
    
        let operation: FilterOperation = isCompressing ? .compress : .decompress

        let outputFilter = try OutputFilter(operation, using: algorithm,  bufferCapacity: self.streamPageSize) {
            (data: Data?) -> Void in
            if let data = data {
                compressedData.append(data)
            }
        }
        
        var index = 0
        let sourceDataSize = data.count
        
        while true {

            let rangeLength = min(self.streamPageSize, sourceDataSize - index)
            
            if (rangeLength == 0) {
                // Finalize the stream, i.e. flush all data remaining in the stream
                // Once the stream is finalized, writing non empty/nil data to the stream will throw an exception.
                // needed. Otherwise, might result in invalid data
                //
                // An alternative will be move this if check after try outputFilter.write(subdata).
                // In that case, calling finalize is not required.
                try outputFilter.finalize()
                break
            }

            let subdata = data.subdata(in: index ..< index + rangeLength)
            index = rangeLength + index
            
            try outputFilter.write(subdata)
            


        }
        
        return compressedData
    }
    
    // stream compress/decompress from URL using input filter + FileHandler
    static func compressDecompressWithStreamUsingInputFilter(url: URL, isCompressing: Bool, algorithm: Algorithm) throws -> URL {
        
        // creating file handle so that we can read data of a specific length
        let sourceFileHandle = try FileHandle(forReadingFrom: url)
        guard let fileName = isCompressing ? url.pathComponents.last : url.deletingPathExtension().pathComponents.last else {
            throw CompressError.failedToGetFilename

        }

        let lastPath = isCompressing ? "\(fileName)\(algorithm.fileExtension)" : fileName
        let destinationURL = destinationDirectory.appending(path: lastPath)
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
        let destinationFileHandle = try FileHandle(forWritingTo: destinationURL)
        
        let operation: FilterOperation = isCompressing ? .compress : .decompress
                
        let inputFilter = try InputFilter(operation, using: algorithm, bufferCapacity: self.streamPageSize, readingFrom: { (length: Int) -> Data? in
            let subdata = sourceFileHandle.readData(ofLength: self.streamPageSize)
            return subdata
        })
        
        
        while let page = try inputFilter.readData(ofLength: self.streamPageSize) {
            try destinationFileHandle.write(contentsOf: page)
        }

        return destinationURL
    }
    
    // stream compress/decompress from URL using output filter + FileHandler
    // we can also try to read in all data at once and use the functions above.
    static func compressDecompressWithStreamUsingOutputFilter(url: URL, isCompressing: Bool, algorithm: Algorithm) throws -> URL {
        
        // creating file handle so that we can read data of a specific length
        let sourceFileHandle = try FileHandle(forReadingFrom: url)
        guard let fileName = isCompressing ? url.pathComponents.last : url.deletingPathExtension().pathComponents.last else {
            throw NSError(domain: "Failed to get file name", code: 500)

        }

        let lastPath = isCompressing ? "\(fileName)\(algorithm.fileExtension)" : fileName
        let destinationURL = destinationDirectory.appending(path: lastPath)
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
        let destinationFileHandle = try FileHandle(forWritingTo: destinationURL)

        let operation: FilterOperation = isCompressing ? .compress : .decompress

        let outputFilter = try OutputFilter(operation, using: algorithm, writingTo: {
            (data: Data?) -> Void in
            
            if let data = data {
                // following will crash with error: Inappropriate ioctl for device
                // destinationFileHandle.write(data)
                try destinationFileHandle.write(contentsOf: data)
            }
        })
        
        
        while true {
            
            let subdata = sourceFileHandle.readData(ofLength: self.streamPageSize)
            try outputFilter.write(subdata)
            if subdata.count < self.streamPageSize {
                // Finalize the stream, i.e. flush all data remaining in the stream
                // Once the stream is finalized, writing non empty/nil data to the stream will throw an exception.
                // needed. Otherwise, might result in invalid data
                try outputFilter.finalize()
                break
            }

        }
        
        sourceFileHandle.closeFile()
        destinationFileHandle.closeFile()

        return destinationURL
    }
    
}
