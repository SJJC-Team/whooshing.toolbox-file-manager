import NIOFileSystem
import NIOConcurrencyHelpers
import NIOCore
import NIOAdvanced
import ErrorHandle
import AsyncAlgorithms
import Cryptos
import FluentKit
import Foundation
import SQLKit
import Logging
import LoggingAdvanced

/// 指定读取文件内容的范围。
///
/// - `all`：读取整个文件内容。
/// - `range`：读取指定的开区间范围 `[lowerBound, upperBound)` 的字节。
/// - `closedRange`：读取指定的闭区间范围 `[lowerBound...upperBound]` 的字节。
public enum ReadPart: Sendable, CustomStringConvertible, Loggerable {
    /// 读取整个文件内容。
    case all
    /// 读取指定的开区间范围 `[lowerBound, upperBound)` 的字节。
    case range(Range<Int64>)
    /// 读取指定的闭区间范围 `[lowerBound...upperBound]` 的字节。
    case closedRange(ClosedRange<Int64>)
    
    public var description: String {
        switch self {
        case .all: return "all"
        case .range(let range): return "range(\(range))"
        case .closedRange(let range): return "closedRange(\(range))"
        }
    }
}

/// 文件读取操作的协议，继承自 `FileContentHandler`，定义了不同方式读取文件内容的方法。
public protocol FileReader: FileContentHandler {
    /// 异步读取指定范围的文件内容，返回一个异步字节缓冲区通道。
    ///
    /// - Parameter part: 指定读取的文件范围。
    /// - Returns: 异步抛出错误的字节缓冲区通道。
    ///
    /// 该写入操作带有 BackPressure 功能，会自动阻塞文件系统的数据流，防止内存堆砌
    func read(part: ReadPart) -> AsyncThrowingChannel<Data, Error>
    
    /// 读取指定范围的文件内容，返回完整的字节缓冲区。
    ///
    /// - Parameter part: 指定读取的文件范围。
    /// - Returns: 异步事件循环结果，成功时返回读取的数据，失败时返回错误。
    ///
    /// - Warning: 使用这个方法会将文件中要读取的数据全部堆砌至内存中，直到读取完毕后
    /// 才会作为返回值返回，这对于小数据读取是极佳的。但应当避免大文件数据读取，否则容易
    /// 造成内存堆砌
    func readData(part: ReadPart) async throws(File.Errcase.ErrType) -> Data
    
    /// 读取指定范围的文件内容，分块回调处理每个字节缓冲区。
    ///
    /// - Parameters:
    ///   - part: 指定读取的文件范围。
    ///   - callback: 异步回调，每次读取到的数据块。
    ///   
    /// - Returns: 异步事件循环结果，成功或失败。
    func readChunks(part: ReadPart, _ callback: @escaping @Sendable (Data) -> EventLoopResult<Void, Error>) async throws(File.Errcase.ErrType)
    
    /// 读取指定范围的文件内容，分块回调处理每个字节缓冲区。
    ///
    /// - Parameters:
    ///   - part: 指定读取的文件范围。
    ///   - callback: 异步回调，每次读取到的数据块。
    ///
    /// - Returns: 异步事件循环结果，成功或失败。
    func readChunks(part: ReadPart, _ callback: @escaping @Sendable (Data) async throws -> ()) async throws(File.Errcase.ErrType)
    
    func readData(part: ReadPart) -> EventLoopRes<Data, File.Errcase>
    func readChunks(part: ReadPart, _ callback: @escaping @Sendable (Data) -> EventLoopResult<Void, Error>) -> EventLoopRes<Void, File.Errcase>
    func readChunks(part: ReadPart, _ callback: @escaping @Sendable (Data) async throws -> ()) -> EventLoopRes<Void, File.Errcase>
}

protocol __FileReader: FileReader, __FileContentHandler {
    associatedtype ReadableFileHandle: ReadableFileHandleProtocol
    var fileReadHandler: ReadableFileHandle { get }
}

extension __FileReader {
    @inlinable
    var fileReadHandler: ReadableFileHandle {
        guard let handler = self.fileHandler as? ReadableFileHandle else {
            fatalError("FileHandler 配置不正确")
        }
        return handler
    }
    
    @inlinable
    func read(part: ReadPart) -> AsyncThrowingChannel<Data, Error> {
        let logger = getHandleLogger()
        logger.info("执行 流式读取文件数据 操作", metadata: ["part": .data(part)])
        
        // 创建读取任务准备进行异步读取
        let reader = AsyncThrowingChannel<Data, Error>()
        Task {
            do {
                try await self.backPressureRead(part: part, reader: reader, logger: logger)
                logger.info("流式读取文件数据操作完成")
                reader.finish()
            } catch {
                reader.fail(logger.error(error))
            }
        }
        return reader
    }
    
    @inlinable
    func readData(part: ReadPart) async throws(File.Errcase.ErrType) -> Data {
        logger.info("执行 单次读取文件数据 操作", metadata: ["part": .data(part)])
        
        let channel = read(part: part)
        
        return try await logger.required(throws: File.Errcase.readFileFailed){
            var res = Data()
            for try await chunk in channel.chunkedChannel(fileCrypto.chunkSize) {
                res += chunk
            }
            logger.info("单次读取文件数据操作完成", metadata: ["data_length": .stringConvertible(res.count)])
            return res
        }
    }
    
    @inlinable
    func readChunks(
        part: ReadPart,
        _ callback: @escaping @Sendable (Data) -> EventLoopResult<Void, Error>
    ) async throws(File.Errcase.ErrType) {
        logger.info("执行 流式读取文件数据 操作", metadata: ["part": .data(part)])
        
        let channel = read(part: part)
        
        try await logger.required(throws: File.Errcase.readFileFailed) {
            for try await chunk in channel.chunkedChannel(fileCrypto.chunkSize) {
                try await callback(chunk).get()
            }
        }
        
        logger.info("流式读取文件数据操作完成")
    }
    
    @inlinable
    func readChunks(
        part: ReadPart,
        _ callback: @escaping @Sendable (Data) async throws -> ()
    ) async throws(File.Errcase.ErrType) {
        logger.info("执行 流式读取文件数据 操作", metadata: ["part": .data(part)])
        
        let channel = read(part: part)
        
        try await logger.required(throws: File.Errcase.readFileFailed) {
            for try await chunk in channel {
                try await callback(chunk)
            }
        }
        
        logger.info("流式读取文件数据操作完成")
    }
}

enum PartIntersectionResult: Loggerable, CustomStringConvertible {
    case all
    case intersection(ChunkHelpers.IntersectionResult)
    
    var description: String {
        switch self {
        case .all: "all"
        case .intersection(let intersectionResult): intersectionResult.description
        }
    }
}

extension __FileReader {
    // 带有 back pressure 机制地从加密文件中按指定的块读取数据并解密
    @usableFromInline
    func backPressureRead(
        part readPart: ReadPart,
        reader: AsyncThrowingChannel<Data, Error>,
        logger: Logger
    ) async throws(BscError<File.Errcase>) {
        // 准备读取的范围
        let readRange: Range<Int64>
        
        switch readPart {
        case .all:
            readRange = 0..<fileIndex.size!
        case .closedRange(let r):
            readRange = .init(r)
        case .range(let r):
            readRange = r
        }
        
        let fileId = try required(throws: File.Errcase.readFileFailed, "获取文件 ID 失败，\(filePath)") {
            try fileIndex.requireID()
        }
        
        logger.debug("成功取得文件 ID", metadata: ["id": .stringConvertible(fileId)])
        
        let fileParts = try await required(throws: File.Errcase.readFileFailed, "数据库查询文件数据块时失败，\(filePath)") {
            try await FilePart.query(on: storage.db)
                .filter(\.$fileIndex.$id == fileId)
                .filter(\.$byteStart < readRange.upperBound)
                .filter(\.$byteEnd >= readRange.lowerBound)
                .sort(\.$byteStart, .ascending)
                .sort(\.$byteEnd, .ascending)
                .all()
                .get()
        }
        
        logger.debug("成功取得文件数据块索引", metadata: ["chunks": .data(fileParts)])
        
        for (i, part) in fileParts.enumerated() {
            let partLength = part.byteEnd - part.byteStart
            let partEncryptedLength = part.encryptedEnd - part.encryptedStart
            
            let headIntersectionResult: PartIntersectionResult
            let tailIntersectionResult: PartIntersectionResult
            
            if i == 0 {
                logger.debug("处理首个数据块")
                let res = try required(throws: File.Errcase.readFileFailed, "头指针落点分析失败，\(filePath)") {
                    try ChunkHelpers.index(
                        readRange.lowerBound - part.byteStart + part.byteHeadIgnore,
                        in: .init(.chunk(fileCrypto.chunkSize, total: partLength + part.byteHeadIgnore + part.byteTailIgnore)),
                        offset: Crypto.Symm.Stream.cipherExtraLength
                    )
                }
                headIntersectionResult = res.chunkBegin == 0 ? .all : .intersection(res)
                
                logger.debug("头指针落点分析成功", metadata: ["result": .data(headIntersectionResult)])
            } else {
                headIntersectionResult = .all
            }
            
            if i == fileParts.count - 1 {
                logger.debug("处理末尾数据块")
                let res = try required(throws: File.Errcase.readFileFailed, "尾指针落点分析失败，\(filePath)") {
                    try ChunkHelpers.index(
                        readRange.upperBound - part.byteStart + part.byteHeadIgnore,
                        in: .init(.chunk(fileCrypto.chunkSize, total: partLength + part.byteHeadIgnore + part.byteTailIgnore)),
                        offset: Crypto.Symm.Stream.cipherExtraLength
                    )
                }
                tailIntersectionResult = res.chunks.count == 0 ? .all : .intersection(res)
                
                logger.debug("尾指针落点分析成功", metadata: ["result": .data(tailIntersectionResult)])
            } else {
                tailIntersectionResult = .all
            }
            
            let chunkReadStartOffset: Int64
            let chunkReadEnd: Int64
            let tagStart: Int
            
            switch headIntersectionResult {
            case .all:
                chunkReadStartOffset = 0
                tagStart = part.tagStart
            case .intersection(let intersect):
                chunkReadStartOffset = intersect.chunkBegin
                tagStart = part.tagStart + intersect.chunkIndex
            }
            
            switch tailIntersectionResult {
            case .all:
                chunkReadEnd = part.encryptedEnd
            case .intersection(let intersect):
                chunkReadEnd = part.encryptedStart + intersect.chunkBegin + (intersect.rangeInIntersection ? 0 : intersect.chunks.first!)
            }
            
            logger.debug("计算索引数据", metadata: [
                "chunk_read_start_offset": .stringConvertible(chunkReadStartOffset),
                "chunk_read_end": .stringConvertible(chunkReadEnd),
                "tag_start": .stringConvertible(tagStart)
            ])
            
            logger.debug("准备读取文件块", metadata: [
                "in": .stringConvertible(part.encryptedStart + chunkReadStartOffset..<chunkReadEnd),
                "chunk_length_bytes": .stringConvertible(fileCrypto.chunkSize + Crypto.Symm.Stream.cipherExtraLength)
            ])
            
            let chunks = fileReadHandler.readChunks(
                in: part.encryptedStart + chunkReadStartOffset..<chunkReadEnd,
                chunkLength: .bytes(fileCrypto.chunkSize + Crypto.Symm.Stream.cipherExtraLength)
            )

            let curReadingPartEncryptedLength = chunkReadEnd - part.encryptedStart - chunkReadStartOffset
            
            logger.debug("加密内容数据总长度", metadata: [
                "cur_reading_part_encrypted_length": .stringConvertible(curReadingPartEncryptedLength)
            ])
            
            try await required(throws: File.Errcase.readFileFailed, "未知错误，\(filePath)") {
                var curPartSize = 0
                var curEncryptedSize = chunkReadStartOffset
                var curChunkIndex = 0
                for try await chunk in chunks {
                    
                    let first = curPartSize == 0
                    curPartSize += chunk.readableBytes
                    let last = curPartSize == curReadingPartEncryptedLength
                    
                    logger.debug("解密文件块 \(curChunkIndex)", metadata: [
                        "size": .stringConvertible(chunk.data.count)
                    ])
                    
                    var data: ByteBuffer = try Crypto.Symm.Stream.decrypt(chunk.data, key: key, chunkTag: tagStart + curChunkIndex).get()
                    
                    logger.debug("解密文件块 \(curChunkIndex) 完成", metadata: [
                        "plain_size": .stringConvertible(data.readableBytes)
                    ])
                    
                    if curEncryptedSize == 0 {
                        data.moveReaderIndex(forwardBy: Int(part.byteHeadIgnore))
                    }
                    
                    curEncryptedSize += Int64(chunk.readableBytes)
                    
                    if curEncryptedSize == partEncryptedLength {
                        data.moveWriterIndex(to: data.writerIndex - Int(part.byteTailIgnore))
                    }
                    
                    if last {
                        switch tailIntersectionResult {
                        case .all: break
                        case .intersection(let tailIntersection):
                            data.moveWriterIndex(to: data.readerIndex + Int(tailIntersection.rangeOffset))
                        }
                    }
                    
                    if first {
                        switch headIntersectionResult {
                        case .all: break
                        case .intersection(let headIntersection):
                            data.moveReaderIndex(forwardBy: Int(headIntersection.rangeOffset))
                        }
                    }
                    
                    logger.debug("文件块 \(curChunkIndex) 读取", metadata: [
                        "size": .stringConvertible(data.readableBytes)
                    ])
                    
                    await reader.send(.init(buffer: data))
                    
                    curChunkIndex += 1
                }
            }
        }
    }
}

extension File {
    
    struct Reader: __FileReader, @unchecked Sendable {
        typealias ReadableFileHandle = ReadFileHandle
        
        let fileIndex: FileIndex
        let fileCrypto: FileCrypto
        let key: Crypto.Symm.Key
        let filePath: StoragePath
        let fileRealPath: FilePath
        let logger: Logger
        
        let lock = NIOLock()
        let __fileHandler: any FileHandleProtocol
        unowned let storage: FileStorage
        
        init(
            fileIndex: FileIndex,
            fileCrypto: FileCrypto,
            key: Crypto.Symm.Key,
            filePath: StoragePath,
            fileRealPath: FilePath,
            fileHandler: ReadableFileHandle,
            logger: Logger,
            storage: FileStorage
        ) {
            self.fileIndex = fileIndex
            self.fileCrypto = fileCrypto
            self.key = key
            self.storage = storage
            self.filePath = filePath
            self.fileRealPath = fileRealPath
            self.logger = logger
            self.__fileHandler = fileHandler
        }
    }
}
