import NIOFileSystem
import NIOConcurrencyHelpers
import NIOCore
import NIOAdvanced
import ErrorHandle
import AsyncAlgorithms
import Cryptos
import FluentKit

public enum ReadPart: Sendable {
    case all
    case range(Range<Int64>)
    case closedRange(ClosedRange<Int64>)
}

public protocol FileReader: FileContentHandler {
    func read(part: ReadPart) -> AsyncThrowingChannel<ByteBuffer, BscError<File.Errcase>>
}

protocol __FileReader: FileReader, __FileContentHandler {
    associatedtype ReadableFileHandle: ReadableFileHandleProtocol
    var fileReadHandler: ReadableFileHandle { get }
}

extension __FileReader {
    var fileReadHandler: ReadableFileHandle {
        guard let handler = self.fileHandler as? ReadableFileHandle else {
            fatalError("FileHandler 配置不正确")
        }
        return handler
    }
    
    func read(part: ReadPart) -> AsyncThrowingChannel<ByteBuffer, BscError<File.Errcase>> {
        // 创建读取任务准备进行异步读取
        let reader = AsyncThrowingChannel<ByteBuffer, Error>()
        Task {
            do {
                try await self.backPressureRead(part: part, reader: reader)
                reader.finish()
            } catch {
                reader.fail(error)
            }
        }
        return reader.castError(to: BscError<File.Errcase>.self)
    }
}

enum PartIntersectionResult {
    case all
    case intersection(ChunkHelpers.IntersectionResult)
}

extension __FileReader {
    // 带有 back pressure 机制地从加密文件中按指定的块读取数据并解密
    func backPressureRead(part: ReadPart, reader: AsyncThrowingChannel<ByteBuffer, Error>) async throws(BscError<File.Errcase>) {
        // 准备读取的范围
        let readRange: Range<Int64>
        
        switch part {
        case .all:
            readRange = 0..<fileCrypto.encryptedSize
        case .closedRange(let r):
            readRange = .init(r)
        case .range(let r):
            readRange = r
        }
        
        let fileId = try required(throws: File.Errcase.readFileFailed, "获取文件 ID 失败") {
            try fileIndex.requireID()
        }
        
        let fileParts = try await required(throws: File.Errcase.readFileFailed, "数据库查询文件数据块时失败") {
            try await FilePart.query(on: storage.db)
                .filter(\.$fileIndex.$id == fileId)
                .filter(\.$byteStart < readRange.upperBound)
                .filter(\.$byteEnd >= readRange.lowerBound)
                .all()
                .get()
        }
        
        for (i, part) in fileParts.enumerated() {
            let partLength = part.encryptedEnd - part.encryptedStart - 1
            
            let headIntersectionResult: PartIntersectionResult
            let tailIntersectionResult: PartIntersectionResult
            
            if i == 0 {
                headIntersectionResult = .intersection(
                    try required(throws: File.Errcase.readFileFailed, "头指针落点分析失败") {
                        try ChunkHelpers.index(
                            readRange.lowerBound - part.encryptedStart,
                            in: .init(.chunk(fileCrypto.chunkSize + Crypto.Symm.Stream.cipherExtraLength, total: partLength)),
                            offset: Crypto.Symm.Stream.cipherExtraLength
                        )
                    }
                )
            } else {
                headIntersectionResult = .all
            }
            
            if i == fileParts.count - 1 {
                tailIntersectionResult = .intersection(
                    try required(throws: File.Errcase.readFileFailed, "尾指针落点分析失败") {
                        try ChunkHelpers.index(
                            readRange.upperBound - part.encryptedStart,
                            in: .init(.chunk(fileCrypto.chunkSize + Crypto.Symm.Stream.cipherExtraLength, total: partLength)),
                            offset: Crypto.Symm.Stream.cipherExtraLength
                        )
                    }
                )
            } else {
                tailIntersectionResult = .all
            }
            
            let chunks = fileReadHandler.readChunks(
                in: part.encryptedRange,
                chunkLength: .bytes(fileCrypto.chunkSize + Crypto.Symm.Stream.cipherExtraLength)
            )

            try await required(throws: File.Errcase.readFileFailed, "未知错误") {

                var curPartSize = 0
                var curChunkIndex = 0
                for try await chunk in chunks {
                    
                    var data: ByteBuffer = try Crypto.Symm.Stream.decrypt(chunk.data, key: key, chunkTag: part.tagStart + curChunkIndex).get()
                    
                    if curPartSize == 0 {
                        data.moveReaderIndex(forwardBy: Int(part.byteHeadIgnore))
                    }
                    
                    if curPartSize + data.readableBytes >= partLength {
                        data.moveWriterIndex(to: data.writerIndex - Int(part.byteTailIgnore))
                    }
                    
                    curPartSize += data.readableBytes
                    
                    switch tailIntersectionResult {
                    case .all: break
                    case .intersection(let tailIntersection):
                        data.moveWriterIndex(to: data.readerIndex + Int(tailIntersection.chunkBegin + tailIntersection.rangeOffset))
                    }
                    
                    switch headIntersectionResult {
                    case .all: break
                    case .intersection(let headIntersection):
                        data.moveReaderIndex(forwardBy: Int(headIntersection.chunkBegin + headIntersection.rangeOffset))
                    }
                    
                    await reader.send(data)
                    
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
        
        let lock = NIOLock()
        let __fileHandler: any FileHandleProtocol
        unowned let storage: FileStorage
        
        init(
            fileIndex: FileIndex,
            fileCrypto: FileCrypto,
            key: Crypto.Symm.Key,
            fileHandler: ReadableFileHandle,
            storage: FileStorage
        ) {
            self.fileIndex = fileIndex
            self.fileCrypto = fileCrypto
            self.key = key
            self.storage = storage
            self.__fileHandler = fileHandler
        }
    }
}
