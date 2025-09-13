# Swift_DataCompressionDemo

A demo of performing Data Compression with [Compression](https://developer.apple.com/documentation/compression) framework. 

- Buffer compression
- Stream compression with InputFilter and OutputFilter
  - Directly From Data
  - From File using file handler

## Basic Usage
### Buffer
```
let sourceString = """
    Hello From Itsuki!
    Hello From Itsuki!
    Hello From Itsuki!
    Hello From Itsuki!
    Hello From Itsuki!
    Hello From Itsuki!
    Hello From Itsuki!
    Hello From Itsuki!
    Hello From Itsuki!
    Hello From Itsuki!
    """
let sourceData = Data(sourceString.utf8)

let compressedData = try CompressService.compressWithBuffer(data: sourceData, algorithm: .zlib)
print("compressedData count: ", compressedData.count  as Any)
assert(compressedData == (try? (sourceData as NSData).compressed(using: .zlib)) as? Data)

let decompressedData = CompressService.decompressWithBuffer(data: compressedData, uncompressedSize: sourceString.utf8.count, algorithm: .zlib)
print("decompressedData count: ", decompressedData.count  as Any)
assert(decompressedData == (try? (compressedData as NSData).decompressed(using: .zlib)) as? Data)
assert(String(data: decompressedData, encoding: .utf8) == sourceString)
```

### Stream

#### With Data
```
let compressedData = try CompressService.compressDecompressWithStreamUsingOutputFilter(data: sourceData, isCompressing: true, algorithm: .zlib)
print("compressedData count: ", compressedData.count)

assert(compressedData == (try? (sourceData as NSData).compressed(using: .zlib)) as? Data)

let decompressedData = try CompressService.compressDecompressWithStreamUsingOutputFilter(data: compressedData, isCompressing: false, algorithm: .zlib)
print("decompressedData count: ", decompressedData.count)
assert(decompressedData == (try? (compressedData as NSData).decompressed(using: .zlib)) as? Data)
print(String(data: decompressedData, encoding: .utf8) as Any)
assert(String(data: decompressedData, encoding: .utf8) == sourceString)
```

#### With File
```
let sourceURL = (try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)).appending(path: "text.txt")
try sourceData.write(to: sourceURL)
let compressedURL = try CompressService.compressDecompressWithStreamUsingInputFilter(url: sourceURL, isCompressing: true, algorithm: .zlib)
print("compressed url: ", compressedURL)

let decompressedURL = try CompressService.compressDecompressWithStreamUsingInputFilter(url: compressedURL, isCompressing: false, algorithm: .zlib)
print("decompressedURL: ", decompressedURL)
assert(try! Data(contentsOf: sourceURL) == Data(contentsOf: decompressedURL))

```





