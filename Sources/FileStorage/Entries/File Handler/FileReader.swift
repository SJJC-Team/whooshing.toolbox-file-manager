import NIOFileSystem
import NIOConcurrencyHelpers
import NIOCore
import NIOAdvanced
import ErrorHandle
import AsyncAlgorithms
import Cryptos

public enum ReadPart: Sendable {
    case all
    case range(Range<Int64>)
    case closedRange(ClosedRange<Int64>)
}

public protocol FileReader: FileContentHandler {
    func read(part: ReadPart) -> AsyncThrowingChannel<ByteBuffer, BscError<File.Errcase>>
}

protocol __FileReader: FileReader, __FileContentHandler {}

extension __FileReader {
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

extension __FileReader {
    // 带有 back pressure 机制地从加密文件中按指定的块读取数据并解密
    func backPressureRead(part: ReadPart, reader: AsyncThrowingChannel<ByteBuffer, Error>) async throws(BscError<File.Errcase>) {
        guard fileCrypto.chunks.count == fileCrypto.chunkTags.count else {
            throw File.Errcase.readFileFailed.d("未知错误，数据块划分参数不同步")
        }
        
        // 准备读取的范围
        let readRange: Range<Int64>
        
        // 计算数据的落点分布
        let intersectionResult: ChunkHelpers.IntersectionResult
        
        switch part {
        case .all:
            readRange = 0..<fileCrypto.encryptedSize
            intersectionResult = .init(rangeOffset: 0, chunkIndex: 0, chunkBegin: 0, chunks: fileCrypto.chunks)
        case .closedRange(let r):
            readRange = .init(r)
            intersectionResult = try required(throws: File.Errcase.readFileFailed, "ClosedRange 数据落点计算失败") {
                try ChunkHelpers.rangeIntersection(r, in: .init(.array(fileCrypto.chunks)), offset: Int64(Crypto.Symm.Stream.cipherExtraLength))
            }
        case .range(let r):
            readRange = r
            intersectionResult = try required(throws: File.Errcase.readFileFailed, "Range 数据落点计算失败") {
                try ChunkHelpers.rangeIntersection(r, in: .init(.array(fileCrypto.chunks)), offset: Int64(Crypto.Symm.Stream.cipherExtraLength))
            }
        }
        
        // 遍历读取数据
        var curCryptedChunkIndex = intersectionResult.chunkBegin
        var curChunkIndex = intersectionResult.chunkIndex
        var curByteIndex = 0
        for chunkSize in intersectionResult.chunks {
            
            guard curByteIndex < readRange.count else { break }
            
            // 判断当读取的数据大小
            let size = min(readRange.count - curByteIndex, Int(chunkSize))
            
            // 读取文件中的加密数据
            let chunk = try await required(throws: File.Errcase.readFileFailed, "从文件中读取数据块时失败") {
                if let readHandler = fileHandler as? ReadFileHandle {
                    return try await readHandler.readChunks(
                        in: curCryptedChunkIndex..<(curCryptedChunkIndex + chunkSize),
                        chunkLength: .bytes(chunkSize)
                    ).collect(upTo: Int(chunkSize))
                } else if let rwHandler = fileHandler as? ReadWriteFileHandle {
                    return try await rwHandler.readChunks(
                        in: curCryptedChunkIndex..<(curCryptedChunkIndex + chunkSize),
                        chunkLength: .bytes(chunkSize)
                    ).collect(upTo: Int(chunkSize))
                } else {
                    fatalError("FileHandler")
                }
            }
            
            // 解密数据
            let c: ByteBuffer = try required(throws: File.Errcase.readFileFailed, "解密数据块时失败") {
                try Crypto.Symm.Stream.decrypt(chunk.data(), key: key, chunkTag: fileCrypto.chunkTags[curChunkIndex])
            }
            
            guard c.readableBytes >= size else {
                throw File.Errcase.readFileFailed.d("所要读取的大小大过文件数据的大小")
            }
            
            guard let slice = c.peekSlice(length: size) else {
                throw File.Errcase.readFileFailed.d("数据切片失败")
            }
                    
            // 通过数据通道传输数据
            await reader.send(slice)
            
            curChunkIndex += 1
            curByteIndex += size
            curCryptedChunkIndex += chunkSize
        }
    }
}

fileprivate extension AsyncThrowingChannel where Failure == Error {
    func castError<NewError: Error>(to _: NewError.Type) -> AsyncThrowingChannel<Element, NewError> {
        unsafeBitCast(self, to: AsyncThrowingChannel<Element, NewError>.self)
    }
}

extension File {
    struct Reader: __FileReader, @unchecked Sendable {
        var fileIndex: FileIndex
        var fileCrypto: FileCrypto
        var key: Crypto.Symm.Key
        
        var lock = NIOLock()
        var __fileHandler: any FileHandleProtocol
        
        init(
            fileIndex: FileIndex,
            fileCrypto: FileCrypto,
            key: Crypto.Symm.Key,
            fileHandler: ReadFileHandle
        ) {
            self.fileIndex = fileIndex
            self.fileCrypto = fileCrypto
            self.key = key
            self.__fileHandler = fileHandler
        }
    }
}
