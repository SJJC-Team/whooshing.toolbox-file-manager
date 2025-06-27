import NIOFileSystem
import NIOConcurrencyHelpers
import NIOCore
import NIOAdvanced
import ErrorHandle
import AsyncAlgorithms
import Cryptos
import FluentKit

public enum ByteIndex: Sendable {
    case begin(of: Int64)
    case end(of: Int64)
}

public protocol FileWriter: FileContentHandler {
//    func insert(from start: Int64, with data: ByteBuffer) -> EventLoopResult<Void, BscError<File.Errcase>>
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

enum FileWriterSeparationResult {
    case noNeed(part: FilePart)
    case separated(left: FilePart, right: FilePart)
}

extension __FileWriter {
    func backPressureInsert(
        from insertIndex: ByteIndex,
        in dataBuffer: AsyncThrowingChannel<ByteBuffer, Error>
    ) async throws(BscError<File.Errcase>) {
//        let chunkBegin = indexResult.chunkBegin + part.encryptedStart
//        let chunkEnd = chunkBegin + chunkSize
        
//        let walFile = try await required(throws: File.Errcase.writeFileFailed, "Wal 文件创建失败") {
//            try await FileSystem.shared.openFile(
//                forReadingAndWritingAt: .init("\(storage.walPath)/\(fileCrypto.storageKey)"),
//                options: .newFile(replaceExisting: true)
//            )
//        }
//        
//        let chunkBegin = indexResult.chunkBegin + part.encryptedStart
//        let chunkEnd = chunkBegin + chunkSize
//        
//        let fileChunks = fileWriteHandler.readChunks(in: chunkBegin..<chunkSize, chunkLength: .bytes(fileCrypto.chunkSize + Crypto.Symm.Stream.cipherExtraLength))
//        
//        do {
//            for try await dataChunk in fileChunks {
//                
//            }
//        } catch {
//            throw File.Errcase.writeFileFailed.d("从数据片段中读取数据时发生未知错误").subErr(error)
//        }
        
        //        // 读取分割处的 chunk
        //        let chunkBegin = indexResult.chunkBegin + part.encryptedStart
        //
        //        let (leftPart, rightPart) = try await required(throws: File.Errcase.writeFileFailed, "从数据片段中读取数据时发生未知错误") {
        //            let cipherData = try await fileWriteHandler.readChunk(fromAbsoluteOffset: chunkBegin, length: .bytes(chunkSize))
        //            var plain: ByteBuffer = try Crypto.Symm.Stream.decrypt(cipherData.data, key: key, chunkTag: part.tagStart + indexResult.chunkIndex).get()
        //            return (plain.readSlice(length: Int(indexResult.rangeOffset)), plain)
        //        }
        //
        //        guard let leftPart = leftPart else {
        //            throw File.Errcase.writeFileFailed.d("数据块分割失败")
        //        }
        //
        //        let cipherLeft
        //
    }
    
    /// 从数据库的层面上分割文件块，对文件系统 0 操作，仅对数据库进行读操作，不负责更新操作
    ///
    /// - Parameters:
    ///     - index: 要分割的索引位置
    /// - Returns: 分割的结果，需要调用者自己将数据更新入数据库中
    func seperateFilePart(
        from index: ByteIndex
    ) async throws(BscError<File.Errcase>) -> FileWriterSeparationResult {
        
        let byteStartIndex: Int64
        
        switch index {
        case .begin(of: let i):
            byteStartIndex = i
        case .end(of: let i):
            byteStartIndex = fileCrypto.encryptedSize - i
        }
        
        // 从数据库中取得包括该插入位置的范围块
        let p = try await required(throws: File.Errcase.separateFilePartFailed, "数据库查询失败") {
            try await FilePart.query(on: storage.db)
                .filter(\.$id == fileIndex.requireID())
                .filter(\.$byteStart <= byteStartIndex)
                .filter(\.$byteEnd > byteStartIndex)
                .first()
        }
        
        guard let part = p else {
            // 查找要进行分割的索引位置时，未命中任何 FilePart
            // 1. 可能该文件是空的
            // 2. 可能是索引大小超限
            throw File.Errcase.separateFilePartFailed.d("索引超限")
        }
        
        let indexResult = try required(throws: File.Errcase.separateFilePartFailed, "落点判断失败") {
            try ChunkHelpers.index(
                byteStartIndex - part.byteStart,
                in: .init(.chunk(fileCrypto.chunkSize, total: part.byteEnd - part.byteStart)),
                offset: Crypto.Symm.Stream.cipherExtraLength
            )
        }
        
        let separationRes = try required(throws: File.Errcase.separateFilePartFailed, "数据片段分割失败") {
            try Self.filePartSeperate(in: part, fileCrypto: fileCrypto, indexResult: indexResult)
        }
        
        guard let newPart = separationRes else {
            return .noNeed(part: part)
        }
        
        return .separated(left: newPart, right: part)
    }
}

enum FileWriterSeperateError: String, ErrList {
    case indexFailed = "落点判断失败"
}

extension __FileWriter {
    
    /// 将一个 FilePart 数据库记录照指定的 indexResult 进行分割，产生新实例，不进行任何数据库操作
    ///
    /// - Parameters:
    ///     - part: 要进行分割的 FilePart 实例(一条数据库表记录)
    ///     - fileCrypto: 该分割的 FilePart 的加密分割信息
    ///     - indexResult: 该次分割的详细描述
    /// - Returns: 修改原 part 中的参数的同时，返回新的分割出来的 filePart, 若无法进行分割则返回 nil
    static func filePartSeperate(
        in part: FilePart,
        fileCrypto: FileCrypto,
        indexResult: ChunkHelpers.IntersectionResult
    ) throws(BscError<FileWriterSeperateError>) -> FilePart? {
        if indexResult.rangeInIntersection && indexResult.chunkIndex == 0 && indexResult.rangeOffset == 0 {
            return nil
        }
        
        guard let chunkSize = indexResult.chunks.first else {
            throw FileWriterSeperateError.indexFailed.d("没有得到 chunk 位置")
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
