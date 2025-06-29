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
    case begin(of: Int64 = 0)
    case end(of: Int64 = 0)
}

public protocol FileWriter: FileContentHandler {
    func insert(at: ByteIndex, from: AsyncThrowingChannel<ByteBuffer, Error>) -> EventLoopResult<Void, BscError<File.Errcase>>
    func replace(at: ByteIndex, from: AsyncThrowingChannel<ByteBuffer, Error>) -> EventLoopResult<Void, BscError<File.Errcase>>
    func remove(in: Range<Int64>) -> EventLoopResult<Void, BscError<File.Errcase>>
    func remove(in: ClosedRange<Int64>) -> EventLoopResult<Void, BscError<File.Errcase>>
}

extension ByteIndex {
    internal func index(fileSize: Int64) -> Int64 {
        switch self {
        case .begin(of: let i):
            return i
        case .end(of: let i):
            return fileSize - i
        }
    }
}

protocol __FileWriter: FileWriter, __FileContentHandler {
    associatedtype WritableFileHandle: WritableFileHandleProtocol
    var fileWriteHandler: WritableFileHandle { get }
}

extension __FileWriter {
    var fileWriteHandler: WritableFileHandle {
        guard let handler = self.fileHandler as? WritableFileHandle else {
            fatalError("FileHandler 配置不正确")
        }
        return handler
    }
    
    func insert(at index: ByteIndex, from channel: AsyncThrowingChannel<ByteBuffer, Error>) -> EventLoopResult<Void, BscError<File.Errcase>> {
        let insertIndex = index.index(fileSize: fileCrypto.encryptedSize)
        return storage.db.eventLoop.makeResultWithTask { () throws(BscError<File.Errcase>) in
            try await backPressureInsert(at: insertIndex, from: channel)
        }.flatMap { appendRes, dbOperation in
            storage.db.trans { db in
                dbOperation(db)
            }.map {
                fileIndex.size = fileIndex.size! + appendRes.readBytes
            }
        }
    }
    
    func replace(at index: ByteIndex, from channel: AsyncThrowingChannel<ByteBuffer, Error>) -> EventLoopResult<Void, BscError<File.Errcase>> {
        let insertIndex = index.index(fileSize: fileCrypto.encryptedSize)
        return storage.db.eventLoop.makeResultWithTask { () throws(BscError<File.Errcase>) in
            let op1 = try await backPressureInsert(at: insertIndex, from: channel)
            let op2 = try await removeBytes(in: insertIndex..<(insertIndex + op1.appendRes.readBytes))
            return (op1.appendRes, op1.dbOperation, op2)
        }.flatMap { appendRes, op1, op2 in
            let composedOp: @Sendable (FileStorage.PGDatabase) -> EventLoopResult<Void, BscError<File.Errcase>> = { db in
                op1(db).flatMap { _ in op2(db) }
            }
            return storage.db.trans { db in composedOp(db) }.map {
                fileIndex.size = fileIndex.size! + appendRes.readBytes
            }
        }
    }
    
    func remove(in range: Range<Int64>) -> EventLoopResult<Void, BscError<File.Errcase>> {
        storage.db.eventLoop.makeResultWithTask { () throws(BscError<File.Errcase>) in
            try await removeBytes(in: range)
        }.flatMap { dbOperation in
            storage.db.trans { db in
                dbOperation(db)
            }
        }
    }
    
    func remove(in range: ClosedRange<Int64>) -> EventLoopResult<Void, BscError<File.Errcase>> {
        remove(in: .init(range))
    }
}

enum FileWriterError: String, ErrList {
    case separateFilePartFailed = "文件数据片分割失败"
    case appendDataFailed = "向文件追加数据时失败"
}

enum FileWriterSeparationResult {
    case noNeed(part: FilePart)
    case separated(left: FilePart, right: FilePart)
}

enum RemoveBytesSeparationResult {
    case eof
    case notEof(FileWriterSeparationResult)
}

extension __FileWriter {
    /// 将提供的数据插入到某个位置。
    /// 该函数会进行数据写入，但不会更新数据库中的指针位置，数据库操作将会作为返回值返回，需要调用者自行执行数据库操作
    func backPressureInsert(
        at byteStartIndex: Int64,
        from channel: AsyncThrowingChannel<ByteBuffer, Error>
    ) async throws(BscError<File.Errcase>) -> (
        appendRes: DataAppendingResult,
        dbOperation: @Sendable (FileStorage.PGDatabase) -> EventLoopRes<Void, File.Errcase>
    ) {
        guard byteStartIndex <= fileCrypto.encryptedSize, byteStartIndex >= 0 else {
            throw File.Errcase.writeFileFailed.d("插入索引不正确，预期最大为 \(fileCrypto.encryptedSize) 且 >= 0，却得到 \(byteStartIndex)")
        }
        
        // 将数据直接写入到加密文件中
        let appendRes = try await required(throws: File.Errcase.writeFileFailed, "将数据写入到文件中时失败") {
            try await appendChannelDataAndEncryptToFile(fileWriteHandler, tagStart: fileCrypto.lastTag, channel: channel)
        }
        
        let separateTask: @Sendable (FileStorage.PGDatabase) -> EventLoopFuture<Void>
        
        if byteStartIndex == fileCrypto.encryptedSize {
            // 追加到文件最后
            // 查询最后一个 filePart 记录，以用于追加
            // 若 last 不存在，则表示该文件是空的
            let last = try await required(throws: File.Errcase.writeFileFailed, "数据库检索失败") {
                try await FilePart.query(on: storage.db)
                    .filter(\.$fileIndex.$id == fileIndex.requireID())
                    .sort(\.$byteEnd, .descending)
                    .first()
            }
            
            // 创建新的 Part 记录，并填入相应的参数
            let newPart = FilePart(
                fileIndex: fileIndex,
                tagStart: fileCrypto.lastTag,
                byteStart: last?.byteStart ?? 0,
                byteEnd: (last?.byteEnd ?? 0) + appendRes.readBytes,
                byteHeadIgnore: 0,
                byteTailIgnore: 0,
                encryptedStart: fileCrypto.encryptedSize,
                encryptedEnd: fileCrypto.encryptedSize + appendRes.writtenBytes
            )
            
            separateTask = { db in
                newPart.save(on: db)
            }
        } else {
            // 进行数据插入，而非追加
            // 先对影响块进行分割
            let separateResult = try await required(throws: File.Errcase.writeFileFailed, "文件块分割失败") {
                try await separateFilePart(from: byteStartIndex)
            }
            
            // 判断分割结果，并应用分割
            let markPart: FilePart
            let __task: @Sendable (FileStorage.PGDatabase) -> EventLoopFuture<Void>
            
            switch separateResult {
            case .noNeed(part: let part):
                // 无需分割
                __task = { $0.eventLoop.makeSucceededVoidFuture() }
                markPart = part
            case .separated(left: let left, right: let right):
                // 需要分割，将新割出的插入到数据库中，并更新被割出的原 Part
                __task = { db in
                    left.save(on: db).flatMap {
                        right.update(on: db)
                    }
                }
                markPart = right
            }
            
            let fileId = try required(throws: File.Errcase.writeFileFailed, "获取文件 ID 失败") {
                try fileIndex.requireID()
            }
            
            // 将数据库查询任务记录在一个闭包中，目前不执行，在最后使用 transaction 执行确保原子性
            separateTask = { db in
                __task(db).flatMap {
                    // 更新该插入点之后的所有数据库记录，使其均向后偏移该插入的字节量
                    appendRemainingPart(
                        with: appendRes.readBytes,
                        greaterEqualThan: markPart.byteStart,
                        in: db,
                        fileId: fileId
                    ).flatMap {
                        // 插入新的 FilePart 到数据库中
                        FilePart(
                            fileIndex: fileIndex,
                            tagStart: fileCrypto.lastTag,
                            byteStart: markPart.byteStart,
                            byteEnd: markPart.byteStart + appendRes.readBytes,
                            byteHeadIgnore: markPart.byteHeadIgnore,
                            byteTailIgnore: 0,
                            encryptedStart: fileCrypto.encryptedSize,
                            encryptedEnd: fileCrypto.encryptedSize + appendRes.writtenBytes
                        ).save(on: db)
                    }
                }
            }
        }
        
        return (
            appendRes,
            { db in
                separateTask(db).flatMap {
                    // 更新加密数据的信息
                    fileCrypto.lastTag = appendRes.lastTag
                    fileCrypto.encryptedSize += appendRes.writtenBytes
                    return fileCrypto.update(on: db)
                }.withError(File.Errcase.writeFileFailed, "数据库操作失败")
            }
        )
    }
    
    /// 从文件中移除某个区间的字节数据。
    /// 该函数不会进行任何文件系统操作，也不会更新数据库中的指针位置，数据库操作将会作为返回值返回，需要调用者自行执行数据库操作
    func removeBytes(
        in range: Range<Int64>
    ) async throws(BscError<File.Errcase>) -> (@Sendable (FileStorage.PGDatabase) -> EventLoopRes<Void, File.Errcase>) {
        guard
            range.lowerBound <= fileCrypto.encryptedSize,
            range.lowerBound >= 0,
            range.upperBound <= fileCrypto.encryptedSize,
            range.upperBound >= 0
        else {
            throw File.Errcase.removeFileDataFailed.d("提供的索引不正确，文件数据范围为 \"0..<\(fileCrypto.encryptedSize)\"，却得到 \"\(range)\"")
        }
        
        guard !range.isEmpty else { return { $0.eventLoop.makeSucceededVoidResult() } }
        
        let removingBytes = range.upperBound - range.lowerBound - 1
        
        let (lowerBoundSepResult, upperBoundSepResult) = try await required(throws: File.Errcase.removeFileDataFailed, "文件块分割失败") {
            (
                // 以 lowerBound 对影响块进行分割
                try await separateFilePart(from: range.lowerBound),
                // 以 upperBound 对影响块进行分割，注意如果指定的 removeBound 在文件最后，则不进行分割计算，直接将删除指针设为 eof
                range.upperBound == fileCrypto.chunkSize ? RemoveBytesSeparationResult.eof : .notEof(try await separateFilePart(from: range.upperBound))
            )
        }
        
        let task: @Sendable (FileStorage.PGDatabase) -> EventLoopFuture<Void>
        
        let fileId = try required(throws: File.Errcase.removeFileDataFailed, "获取文件 ID 失败") {
            try fileIndex.requireID()
        }
        
        switch (lowerBoundSepResult, upperBoundSepResult) {
        case (.noNeed(part: let lowerPart), .eof):
            
            //              |- - - - - - - - - - - - - - - - - - - - -|     : will remove
            //              v                                         v
            // |------------|-------------|-------------|-------------|     : origin data chunks
            //              |             |
            //              <------------->                                 : lowerPart
            
            task = { db in
                FilePart.query(on: db)
                    .filter(\.$fileIndex.$id == fileId)
                    .filter(\.$byteStart >= lowerPart.byteStart)
                    .delete()
            }
            
        case (.separated(left: let lowerLeft, right: let lowerRight), .eof):
            
            //        |- - - - - - - - - - - - - - - - - - - - - - - -|     : will remove
            //        v                                               v
            // |------------|-------------|-------------|-------------|     : origin data chunks
            // |      |     |
            // <------>     |                                               : lowerLeft
            //        <----->                                               : lowerRight
         
            task = { db in
                FilePart.query(on: db)
                    .filter(\.$fileIndex.$id == fileId)
                    .filter(\.$byteStart >= lowerRight.byteStart)
                    .delete()
                .flatMap {
//                    FilePart.query(on: db)
//                        .filter(\.$fileIndex.$id == fileId)
//                        .filter(\.$byteStart == lowerLeft.byteStart)
//                        .delete()
                    lowerRight.delete(on: db)
                }.flatMap {
                    lowerLeft.save(on: db)
                }
            }
            
        case (.noNeed(part: let lowerPart), .notEof(.noNeed(part: let upperPart))):
            
            //              |- - - - - - - - - - - - - -|                   : will remove
            //              v                           v
            // |------------|-------------|-------------|-------------|     : origin data chunks
            //              |             |             |             |
            //              <------------->             |             |     : lowerPart
            //                                          <------------->     : upperPart
            
            task = { db in
                FilePart.query(on: db)
                    .filter(\.$fileIndex.$id == fileId)
                    .filter(\.$byteStart >= lowerPart.byteStart)
                    .filter(\.$byteStart < upperPart.byteStart)
                    .delete()
                .flatMap {
                    appendRemainingPart(
                        with: -removingBytes,
                        greaterEqualThan: upperPart.byteStart,
                        in: db,
                        fileId: fileId
                    )
                }
            }
            
        case (.noNeed(part: let lowerPart), .notEof(.separated(left: let upperLeft, right: let upperRight))):
            
            //              |- - - - - - - - - - - - - - - - -|             : will remove
            //              v                                 v
            // |------------|-------------|-------------|-------------|     : origin data chunks
            //              |             |             |     |       |
            //              <------------->             |     |       |     : lowerPart
            //                                          |     <------->     : upperRight
            //                                          <----->             : upperLeft
            
            task = { db in
                FilePart.query(on: db)
                    .filter(\.$fileIndex.$id == fileId)
                    .filter(\.$byteStart >= lowerPart.byteStart)
                    .filter(\.$byteStart < upperLeft.byteStart)
                    .delete()
                .flatMap {
                    upperRight.update(on: db)
                }.flatMap {
                    appendRemainingPart(
                        with: -removingBytes,
                        greaterEqualThan: upperRight.byteStart,
                        in: db,
                        fileId: fileId
                    )
                }
            }
            
        case (.separated(left: let lowerLeft, right: let lowerRight), .notEof(.noNeed(part: let upperPart))):
            
            //        |- - - - - - - - - - - - - - - - -|                   : will remove
            //        v                                 v
            // |------------|-------------|-------------|-------------|     : origin data chunks
            // |      |     |                           |             |
            // |      |     |                           <------------->     : upperPart
            // <------>     |                                               : lowerLeft
            //        <----->                                               : lowerRight
         
            task = { db in
                FilePart.query(on: db)
                    .filter(\.$fileIndex.$id == fileId)
                    .filter(\.$byteStart >= lowerRight.byteStart)
                    .filter(\.$byteStart < upperPart.byteStart)
                    .delete()
                .flatMap {
//                    FilePart.query(on: db)
//                        .filter(\.$fileIndex.$id == fileId)
//                        .filter(\.$byteStart == lowerLeft.byteStart)
//                        .delete()
                    lowerRight.delete(on: db)
                }.flatMap {
                    lowerLeft.save(on: db)
                }.flatMap {
                    appendRemainingPart(
                        with: -removingBytes,
                        greaterEqualThan: upperPart.byteStart,
                        in: db,
                        fileId: fileId
                    )
                }
            }
            
        case (.separated(left: let lowerLeft, right: let lowerRight), .notEof(.separated(left: let upperLeft, right: let upperRight))):
            
            //        |- - - - - - - - - - - - - - - - - - - -|             : will remove
            //        v                                       v
            // |------------|-------------|-------------|-------------|     : origin data chunks
            // |      |     |                           |     |       |
            // |      |     |                           <----->       |     : upperLeft
            // |      |     |                                 <------->     : upperRight
            // <------>     |                                               : lowerLeft
            //        <----->                                               : lowerRight
         
            task = { db in
                FilePart.query(on: db)
                    .filter(\.$fileIndex.$id == fileId)
                    .filter(\.$byteStart >= lowerRight.byteStart)
                    .filter(\.$byteStart < upperLeft.byteStart)
                    .delete()
                .flatMap {
                    lowerRight.delete(on: db)
                }.flatMap {
                    lowerLeft.save(on: db)
                }.flatMap {
                    upperRight.update(on: db)
                }.flatMap {
                    appendRemainingPart(
                        with: -removingBytes,
                        greaterEqualThan: upperRight.byteStart,
                        in: db,
                        fileId: fileId
                    )
                }
            }
        }
        
        return { db in
            task(db).flatMap {
                // 更新加密数据的信息
                fileCrypto.encryptedSize -= removingBytes
                return fileCrypto.update(on: db)
            }.withError(File.Errcase.removeFileDataFailed, "数据库操作失败")
        }
    }
}

struct DataAppendingResult {
    let readBytes: Int64
    let writtenBytes: Int64
    let lastTag: Int
    
    init(_ readBytes: Int64, _ writtenBytes: Int64, _ lastTag: Int) {
        self.readBytes = readBytes
        self.writtenBytes = writtenBytes
        self.lastTag = lastTag
    }
}

extension __FileWriter {
    
    func appendRemainingPart(
        with byteOffset: Int64,
        greaterEqualThan bound: Int64,
        in db: FileStorage.PGDatabase,
        fileId: UUID
    ) -> EventLoopFuture<Void> {
        db.query("""
            UPDATE "\(FilePart.schema)"
            SET 
                "\(FilePart.fields.byteStart.name)" = "\(FilePart.fields.byteStart.name)" + \(byteOffset),
                "\(FilePart.fields.byteEnd.name)" = "\(FilePart.fields.byteEnd.name)" + \(byteOffset)
            WHERE
                "\(FilePart.fields.fileId.name)" = '\(fileId.uuidString)' AND
                "\(FilePart.fields.byteStart.name)" >= \(bound)
            """)
        .map { _ in }
    }
    
    /// 将 channel 中的数据进行加密并追加到文件 fileHandler 的末尾
    func appendChannelDataAndEncryptToFile(
        _ fileHandler: WritableFileHandle,
        tagStart: Int,
        channel: AsyncThrowingChannel<ByteBuffer, Error>
    ) async throws(BscError<FileWriterError>) -> DataAppendingResult {
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
        return .init(readBytes, writtenBytes, curTag)
    }
    
    /// 从数据库的层面上分割文件块，对文件系统 0 操作，且仅对数据库进行读操作，不负责更新操作
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
            byteTailIgnore: indexResult.rangeInIntersection ? 0 : (chunkSize - indexResult.rangeOffset),
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
            fileHandler: WritableFileHandle,
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
