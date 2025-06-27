import NIOFileSystem
import NIOConcurrencyHelpers
import NIOCore
import NIOAdvanced
import ErrorHandle
import AsyncAlgorithms
import Cryptos
import FluentKit
import FluentSQL

public enum ByteIndex: Sendable {
    case begin(of: Int64)
    case end(of: Int64)
}

public protocol FileWriter: FileContentHandler {
//    func insert(from start: Int64, with data: ByteBuffer) -> EventLoopResult<Void, BscError<File.Errcase>>
}

protocol __FileWriter: FileWriter, __FileContentHandler {
    associatedtype WritableFileHandle: WritableFileHandleProtocol
    var storage: FileStorage { get }
    var fileWriteHandler: WritableFileHandle { get }
}

extension __FileWriter {
    var fileWriteHandler: WritableFileHandle {
        guard let handler = self.fileHandler as? WritableFileHandle else {
            fatalError("FileHandler 配置不正确")
        }
        return handler
    }
    
//    func write(from start: Int64 = 0, with data: ByteBuffer) -> EventLoopResult<Void, BscError<File.Errcase>> {
//        // 创建读取任务准备进行异步写入
//        
//    }
}

enum FileWriterError: String, ErrList {
    case separateFilePartFailed = "文件数据片分割失败"
    case appendDataFailed = "向文件追加数据时失败"
}

enum FileWriterSeparationResult {
    case noNeed(part: FilePart)
    case separated(left: FilePart, right: FilePart)
}

extension __FileWriter {
    func backPressureInsert(
        at insertIndex: ByteIndex,
        from channel: AsyncThrowingChannel<ByteBuffer, Error>
    ) async throws(BscError<File.Errcase>) {
        
        let byteStartIndex: Int64
        
        switch insertIndex {
        case .begin(of: let i):
            byteStartIndex = i
        case .end(of: let i):
            byteStartIndex = fileCrypto.encryptedSize - i
        }
        
        let separateResult = try await required(throws: File.Errcase.writeFileFailed, "文件块分割失败") {
            try await separateFilePart(from: byteStartIndex)
        }
        
        // 将数据直接写入到加密文件中
        let appendRes = try await required(throws: File.Errcase.writeFileFailed, "将数据写入到 wal 文件中时失败") {
            try await appendChannelDataAndEncryptToFile(fileWriteHandler, tagStart: fileCrypto.lastTag, channel: channel)
        }
        
        let separateTask: EventLoopFuture<Void>
        let markPart: FilePart
        
        switch separateResult {
        case .noNeed(part: let part):
            // 无需分割
            separateTask = storage.db.eventLoop.makeSucceededVoidFuture()
            markPart = part
        case .separated(left: let left, right: let right):
            // 需要分割，将新割出的插入到数据库中，并更新被割出的原 Part
            separateTask = left.save(on: storage.db).flatMap {
                right.update(on: storage.db)
            }
            markPart = right
        }
        
        try await required(throws: File.Errcase.writeFileFailed, "数据库更新失败") {
            let fileId = try fileIndex.requireID()
            try await storage.db.trans { db in
                separateTask.flatMap {
                    // 更新该插入点之后的所有数据库记录，使其均向后偏移该插入的字节量
                    db.query("""
                    UPDATE "\(FilePart.schema)"
                    SET 
                        "\(FilePart.fields.byteStart.name)" = "\(FilePart.fields.byteStart.name)" + \(appendRes.readBytes),
                        "\(FilePart.fields.byteEnd.name)" = "\(FilePart.fields.byteEnd.name)" + \(appendRes.readBytes)
                    WHERE
                        "\(FilePart.fields.fileId.name)" = '\(fileId.uuidString)' AND
                        "\(FilePart.fields.byteStart.name)" >= \(markPart.byteStart)
                    """)
                    .flatMap { _ in
                        // 插入新的 FilePart 到数据库中
                        FilePart(
                            fileIndex: fileIndex,
                            tagStart: fileCrypto.lastTag,
                            byteStart: markPart.byteStart,
                            byteEnd: markPart.byteStart + appendRes.readBytes,
                            byteHeadIgnore: markPart.byteHeadIgnore,
                            byteTailLimit: 0,
                            encryptedStart: 0,
                            encryptedEnd: fileCrypto.encryptedSize + appendRes.writtenBytes
                        ).save(on: db)
                    }
                    .flatMap {
                        // 更新加密数据的信息
                        fileCrypto.lastTag = appendRes.lastTag
                        fileCrypto.encryptedSize += appendRes.writtenBytes
                        return fileCrypto.update(on: db)
                    }
                }
            }.get()
        }
    }
    
    /// 将 channel 中的数据进行加密并追加到文件 fileHandler 的末尾
    func appendChannelDataAndEncryptToFile(
        _ fileHandler: WritableFileHandle,
        tagStart: Int,
        channel: AsyncThrowingChannel<ByteBuffer, Error>
    ) async throws(BscError<FileWriterError>) -> (readBytes: Int64, writtenBytes: Int64, lastTag: Int) {
        // 取得该文件的大小，用于追加数据
        let size = try await required(throws: FileWriterError.appendDataFailed, "获取文件大小信息时失败") {
            try await fileHandler.info().size
        }
        var writer = fileHandler.bufferedWriter(startingAtAbsoluteOffset: size)
        var writtenBytes: Int64 = 0
        var readBytes: Int64 = 0
        var curTag = tagStart
        try await required(throws: FileWriterError.appendDataFailed, "将数据写入文件中时失败") {
            // 按照 fileCrypto.chunkSize 大小读取每一块数据
            for try await chunk in channel.chunkedChannel(fileCrypto.chunkSize) {
                // 自动将 channel 中的数据流加密写入
                let cipher = try Crypto.Symm.Stream.encrypt(chunk, key: key, chunkTag: tagStart).get()
                try await writer.write(contentsOf: ByteBuffer(data: cipher))
                curTag += 1
                writtenBytes += Int64(cipher.count)
                readBytes += Int64(chunk.readableBytes)
            }
        }
        return (readBytes, writtenBytes, curTag)
    }
    
    /// 从数据库的层面上分割文件块，对文件系统 0 操作，仅对数据库进行读操作，不负责更新操作
    ///
    /// - Parameters:
    ///     - index: 要分割的索引位置
    /// - Returns: 分割的结果，需要调用者自己将数据更新入数据库中
    func separateFilePart(
        from index: Int64
    ) async throws(BscError<FileWriterError>) -> FileWriterSeparationResult {
        // 从数据库中取得包括该插入位置的范围块
        let p = try await required(throws: FileWriterError.separateFilePartFailed, "数据库查询失败") {
            try await FilePart.query(on: storage.db)
                .filter(\.$fileIndex.$id == fileIndex.requireID())
                .filter(\.$byteStart <= index)
                .filter(\.$byteEnd > index)
                .first()
        }
        
        guard let part = p else {
            // 查找要进行分割的索引位置时，未命中任何 FilePart
            // 1. 可能该文件是空的
            // 2. 可能索引分割位置 == 总大小
            // 3. 可能是索引大小超限
            throw FileWriterError.separateFilePartFailed.d("索引超限")
        }
        
        let indexResult = try required(throws: FileWriterError.separateFilePartFailed, "落点判断失败") {
            try ChunkHelpers.index(
                index - part.byteStart,
                in: .init(.chunk(fileCrypto.chunkSize, total: part.byteEnd - part.byteStart)),
                offset: Crypto.Symm.Stream.cipherExtraLength
            )
        }
        
        let separationRes = try required(throws: FileWriterError.separateFilePartFailed, "数据片段分割失败") {
            try Self.filePartSeparate(in: part, fileCrypto: fileCrypto, indexResult: indexResult)
        }
        
        guard let newPart = separationRes else {
            return .noNeed(part: part)
        }
        
        return .separated(left: newPart, right: part)
    }
}

extension __FileWriter {
    /// 将一个 FilePart 数据库记录照指定的 indexResult 进行分割，产生新实例，不进行任何数据库操作
    ///
    /// - Parameters:
    ///     - part: 要进行分割的 FilePart 实例(一条数据库表记录)
    ///     - fileCrypto: 该分割的 FilePart 的加密分割信息
    ///     - indexResult: 该次分割的详细描述
    /// - Returns: 修改原 part 中的参数的同时，返回新的分割出来的 filePart, 若无法进行分割则返回 nil
    static func filePartSeparate(
        in part: FilePart,
        fileCrypto: FileCrypto,
        indexResult: ChunkHelpers.IntersectionResult
    ) throws(BscError<FileWriterError>) -> FilePart? {
        if indexResult.rangeInIntersection && indexResult.chunkIndex == 0 && indexResult.rangeOffset == 0 {
            return nil
        }
        
        guard let chunkSize = indexResult.chunks.first else {
            throw FileWriterError.separateFilePartFailed.d("落点判断失败，没有得到 chunk 位置")
        }
        
        let newPartByteSize = Int64(indexResult.chunkIndex) * fileCrypto.chunkSize + indexResult.rangeOffset
        let newPartEncryptedSize = Int64(indexResult.chunkIndex) * (fileCrypto.chunkSize + Crypto.Symm.Stream.cipherExtraLength)
        
        let newPart = FilePart(
            fileIndex: part.fileIndex,
            tagStart: fileCrypto.lastTag,
            byteStart: part.byteStart,
            byteEnd: part.byteStart + newPartByteSize,
            byteHeadIgnore: part.byteHeadIgnore,
            byteTailLimit: indexResult.rangeInIntersection ? 0 : indexResult.rangeOffset,
            encryptedStart: part.encryptedStart,
            encryptedEnd: part.encryptedStart + newPartEncryptedSize + (indexResult.rangeInIntersection ? 0 : chunkSize)
        )
        
        part.tagStart += indexResult.chunkIndex - (indexResult.rangeInIntersection ? 0 : 1)
        part.byteStart += newPartByteSize
        part.byteHeadIgnore = indexResult.rangeInIntersection ? 0 : indexResult.rangeOffset
        part.encryptedStart += newPartEncryptedSize
        
        return newPart
    }
}

extension File {
    struct Writer: __FileWriter, @unchecked Sendable {
        typealias WritableFileHandle = WriteFileHandle
        
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
