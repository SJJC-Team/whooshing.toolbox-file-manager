import NIOFileSystem
import NIOConcurrencyHelpers
import NIOCore
import NIOAdvanced
import ErrorHandle
import AsyncAlgorithms
import Cryptos

import Foundation

public enum WriteMethod: Sendable {
    case overwrite
    case insert
}

public protocol FileWriter: FileContentHandler {
//    func write(from start: Int64, with data: ByteBuffer) -> EventLoopResult<Void, BscError<File.Errcase>>
}

protocol __FileWriter: FileWriter, __FileContentHandler {
    var storage: FileStorage { get }
    var fileWriteHandler: ReadWriteFileHandle { get }
}

extension __FileWriter {
    var fileWriteHandler: ReadWriteFileHandle {
        guard let handler = self.fileHandler as? ReadWriteFileHandle else {
            fatalError("FileHandler 配置不正确")
        }
        return handler
    }
    
//    func write(from start: Int64 = 0, with data: ByteBuffer) -> EventLoopResult<Void, BscError<File.Errcase>> {
//        // 创建读取任务准备进行异步写入
//        
//    }
}

public enum WriteSubActionErrcase: String, ErrList {
    case writeChunkToFileFailed = "将数据写入文件时失败"
    case readChunkFromFileFailed = "从文件中读取数据时失败"
}

extension __FileWriter {
    func backPressureWrite(
        from startIndex: Int64,
        in dataBuffer: AsyncThrowingChannel<ByteBuffer, Error>,
        as space: BufferSpace,
        method: WriteMethod = .insert
    ) async throws(BscError<File.Errcase>) {
        guard fileCrypto.encryptedSize >= startIndex else {
            throw File.Errcase.writeFileFailed.d("写指针起始索引超出限制，总大小为 \(fileCrypto.encryptedSize), 却得到 \(startIndex)")
        }
        
        // 计算数据落点
        let intersectionResult = try required(throws: File.Errcase.writeFileFailed, "插入数据-数据落点计算失败") {
            try ChunkHelpers.index(startIndex, in: .init(.array(fileCrypto.chunks)), offset: Int64(Crypto.Symm.Stream.cipherExtraLength))
        }
        
        // 进行重分割
        let resepResult = try required(throws: File.Errcase.writeFileFailed, "重分割失败") {
            try ChunkHelpers.insertionReseparation(space, at: intersectionResult.rangeOffset, in: intersectionResult.chunks.first ?? 0, offset: Int64(Crypto.Symm.Stream.cipherExtraLength))
        }
        
        // 根据 数据落点 和 重分割 结果准备新数据
        let tagStart = fileCrypto.chunkTags[intersectionResult.chunkIndex]
        let dataChannel = asyncDataPrepare(in: dataBuffer, as: space, intersectionResult: intersectionResult, resepResult: resepResult)
        
        // 创建新的临时文件
        let tempFileHandler = try await required(throws: File.Errcase.writeFileFailed, "创建临时文件失败") {
            try await FileSystem.shared.openFile(forWritingAt: .init("\(storage.storagePath)/temp_\(fileCrypto.storageKey)"), options: .newFile(replaceExisting: true))
        }
        // 将数据写入临时文件
        try await required(throws: File.Errcase.writeFileFailed, "将数据写入临时文件时失败") {
            var curTag = fileCrypto.chunkTags[intersectionResult.chunkIndex]
            let tempFileWriteIndex =  try await writeToFile(fileChunks: dataChannel, at: 0, with: tempFileHandler) { data in
                // 对数据块进行加密
                let res = try Crypto.Symm.Stream.encrypt(data, key: key, chunkTag: curTag)
                curTag += 1
                return ByteBuffer(data: res)
            }
            
            let remainDataStart = intersectionResult.chunkBegin + intersectionResult.chunkTotalLength
            let remainChunks = fileWriteHandler.readChunks(in: remainDataStart..<fileCrypto.encryptedSize, chunkLength: .bytes(ChunkHelpers.commonChunkSize))
            
            try await writeToFile(fileChunks: remainChunks, at: tempFileWriteIndex, with: tempFileHandler) { $0 }
        }
    }
    
    // 将数据写入文件中，返回写入的长度
    @discardableResult
    func writeToFile<T>(
        fileChunks: T,
        at index: Int64,
        with fileHandler: WriteFileHandle,
        chunkHandler: (ByteBuffer) async throws -> ByteBuffer
    ) async throws(BscError<WriteSubActionErrcase>) -> Int64 where T: AsyncSequence, T.Element == ByteBuffer {
        var writer = fileHandler.bufferedWriter(startingAtAbsoluteOffset: index)
        var length: Int64 = 0
        try await required(throws: WriteSubActionErrcase.writeChunkToFileFailed.d("写数据时失败")) {
            for try await chunk in fileChunks {
                let data = try await chunkHandler(chunk)
                length += Int64(data.readableBytes)
                try await writer.write(contentsOf: data)
            }
        }
        
        try await required(throws: WriteSubActionErrcase.writeChunkToFileFailed.d("将缓冲区数据放入文件系统时失败")) {
            try await writer.flush()
        }
        
        return length
    }
    
    func decryptContent(start: Int64, length: Int64, readOffset: Int64, readLength: Int64, tag: Int) async throws(BscError<WriteSubActionErrcase>) -> ByteBuffer {
        let range = start..<(start + length)
        do {
            let cipher = try await fileWriteHandler.readChunks(in: range).collect(upTo: Int(length))
            var headChunk: ByteBuffer = try Crypto.Symm.Stream.decrypt(cipher.data(), key: key, chunkTag: tag)
            return headChunk.getSlice(at: Int(readOffset), length: Int(readLength))!
        } catch {
            throw WriteSubActionErrcase.readChunkFromFileFailed.d("读取并解密块失败")
        }
    }
    
    // 根据落点和重分割结果异步产生新数据
    func asyncDataPrepare(
        in dataBuffer: AsyncThrowingChannel<ByteBuffer, Error>,
        as space: BufferSpace,
        intersectionResult: ChunkHelpers.IntersectionResult,
        resepResult: ChunkHelpers.ReseparationResult
    ) -> AsyncThrowingChannel<ByteBuffer, Error> {
        // 准备写入通道
        let writeChannel = AsyncThrowingChannel<ByteBuffer, Error>()
        
        // 将数据异步写入准备通道
        Task {
            do {
                for (i, curChunklength) in space.enumerated() {
                    let curChunk = try await dataBuffer.collect(upTo: Int(curChunklength))
                    
                    var chunks: [ByteBuffer] = [curChunk]
                    
                    if i == 0 && resepResult.headCombine != .none {
                        var headChunk: ByteBuffer = try await decryptContent(
                            start: intersectionResult.chunkBegin,
                            length: intersectionResult.chunks.first!,
                            readOffset: 0,
                            readLength: intersectionResult.rangeOffset,
                            tag: fileCrypto.chunkTags[intersectionResult.chunkIndex]
                        )
                        
                        if resepResult.headCombine == .separate {
                            chunks = [headChunk, curChunk]
                        } else {
                            headChunk.writeImmutableBuffer(curChunk)
                            chunks = [headChunk]
                        }
                    }
                    
                    if i == (space.count - 1), let tail = resepResult.tailCombine.tail {
                        var tailChunk: ByteBuffer = try await decryptContent(
                            start: intersectionResult.chunkBegin + tail.chunkBegin,
                            length: intersectionResult.chunks.last!,
                            readOffset: tail.byteOffset,
                            readLength: tail.length,
                            tag: fileCrypto.chunkTags[intersectionResult.chunkIndex + tail.chunkIndex]
                        )
                        
                        if case .separate = resepResult.tailCombine {
                            chunks.append(tailChunk)
                        } else {
                            var last = chunks.removeLast()
                            last.writeImmutableBuffer(tailChunk)
                            chunks.append(last)
                        }
                    }
                    
                    for chunk in chunks {
                        await writeChannel.send(chunk)
                    }
                }
                writeChannel.finish()
            } catch {
                writeChannel.fail(File.Errcase.writeFileFailed.d().subErr(error))
            }
        }
        
        return writeChannel
    }
}

extension File {
    struct Writer: __FileWriter, @unchecked Sendable {
        let fileIndex: FileIndex
        let fileCrypto: FileCrypto
        let key: Crypto.Symm.Key
        
        let lock = NIOLock()
        let __fileHandler: FileHandleProtocol
        unowned let storage: FileStorage
        
        init(
            fileIndex: FileIndex,
            fileCrypto: FileCrypto,
            key: Crypto.Symm.Key,
            fileHandler: ReadWriteFileHandle,
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
