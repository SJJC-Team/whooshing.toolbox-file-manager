import AsyncAlgorithms
import NIOCore
import Foundation
import FluentKit
import ErrorHandle
import Cryptos
import NIOFileSystem
import NIOAdvanced

public struct File: StorageEntry, Sendable {
    
    public typealias Handler = AsyncThrowingChannel<ByteBuffer, Error>
    
    public let id: UUID
    public let name: String
    public let mimeType: MimeType
    public let size: Int64
    public let path: StoragePath
    public let createdAt: Date
    public let updatedAt: Date
    
    public unowned let storage: FileStorage
    
    public typealias Errcase = FileStorage.Errcase
    
    let fileIndex: FileIndex
    
    init(
        from index: FileIndex,
        parent: StoragePath,
        storage: FileStorage
    ) throws(BscError<Errcase>) {
        guard
            index.type == .file,
            let size = index.size
        else { throw Errcase.indexTypeIsNotFile.d() }
        
        self.id = try required(throws: Errcase.fetchFileIdFailed) {
            try index.requireID()
        }
        
        self.name = index.name
        self.mimeType = index.mimeType!
        self.size = size
        self.path = parent + index.name
        self.createdAt = index.createdAt
        self.updatedAt = index.updatedAt
        self.storage = storage
        self.fileIndex = index
    }
}

public extension File {
    
    func isExist() -> Bool {
        (try? FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first().wait()) != nil
    }
    
    func isExist() async -> Bool {
        (try? await FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first()) != nil
    }
    
//    func write(_ data: ByteBuffer, start from: Int = 0) -> EventLoopFuture<Handler> {
//        
//    }
//    
//    func read(in: Range<Int64>) -> EventLoopFuture<ByteBuffer> {
//        
//    }
    
    
    
//    func makeReader() -> EventLoopFuture<Handler> {
//        FileCrypto.query(on: storage.indexDatabase).filter(\.$id == id).first().hop(to: storage.eventLoop).flatMap { fileCrypto in
//            guard let fileCrypto = fileCrypto else {
//                return self.storage.eventLoop.makeFailedFuture(Err.fileIsNotExist.d(16020))
//            }
//            return self.storage.eventLoop.makeFutureWithTask {
//                // 创建派生密钥
//                let key = try self.storage.masterKey.derive(fileCrypto.salt, info: fileCrypto.sharedData)
//                // 打开加密文件，准备读取其加密内容
//                let filePath = "\(self.storage.storagePath)/\(fileCrypto.storageKey)/\(FileStorage.CryptoFileExtension)"
//                let fileHandler = try await FileSystem.shared.openFile(forReadingAt: .init(filePath), options: .init())
//                // 将加密文件分割为 chunks，块大小为当初加密的块大小 + 加密增量大小
//                let chunks = fileHandler.readChunks(chunkLength: .bytes(fileCrypto.chunkSize + Int64(Crypto.Symm.Stream.cipherExtraLength)))
//                // 创建读取任务并异步进行读取
//                let reader = Handler()
//                Task {
//                    do {
//                        var i = 0
//                        for try await chunk in chunks {
//                            // 解密数据
//                            let c: Data = try Crypto.Symm.Stream.decrypt(.init(buffer: chunk), key: key, chunkTag: i)
//                            await reader.send(.init(data: c))
//                            i += 1
//                        }
//                        try await fileHandler.close()
//                        reader.finish()
//                    } catch {
//                        try? await fileHandler.close()
//                        reader.fail(error)
//                    }
//                }
//                return reader
//            }
//        }
//    }
    
    func delete(force: Bool = false) -> EventLoopResult<Void, BscError<Errcase>> {
        FileIndex.query(on: storage.indexDatabase)
            .filter(\.$id == id)
            .delete(force: force)
            .withError(Errcase.deleteFileFailed, "数据库删除记录失败")
    }
    
    func rename(as name: String) -> EventLoopResult<File, BscError<Errcase>> {
        fileIndex.name = name
        return fileIndex.update(on: storage.indexDatabase)
            .withError(Errcase.renameFileFailed, "数据库更新失败")
            .flatMapThrowing
        { () throws(BscError<Errcase>) in
            try required(throws: Errcase.renameFileFailed, "未知错误") {
                try .init(from: fileIndex, parent: self.path.parent, storage: storage)
            }
        }
    }
    
    func move(to dir: Directory, as name: String? = nil) -> EventLoopResult<File, BscError<Errcase>> {
        fileIndex.parent = dir.fileIndex.isRoot ? nil : dir.fileIndex
        if let name = name {
            fileIndex.name = name
        }
        return fileIndex.update(on: storage.indexDatabase)
            .withError(Errcase.moveFileFailed, "数据库更新失败")
            .flatMapThrowing
        { () throws(BscError<Errcase>) in
            try required(throws: Errcase.moveFileFailed, "未知错误") {
                try .init(from: fileIndex, parent: self.path.parent, storage: storage)
            }
        }
    }
}

enum ChunkHelpers {
    
    struct Intersection: Equatable, CustomStringConvertible {
        let rangeOffset: Int64
        let chunkBegin: Int64
        let chunks: [Int64]
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.rangeOffset == rhs.rangeOffset &&
            lhs.chunkBegin == rhs.chunkBegin &&
            lhs.chunks == rhs.chunks
        }
        
        var description: String {
            "(rangeOffset: \(rangeOffset), chunkBegin: \(chunkBegin), chunks: [\(chunks.map { String($0) }.joined(separator: ", "))])"
        }
    }
    
    /// 判断字节 range 具体落在哪些实际 buffers
    ///
    /// - Parameters:
    ///     - range: 字节范围
    ///     - chunks: 所有块大小
    ///     - offset: 块大小的大小偏移量，即 `offsetChunks = [chunks].map { $0 + offset }`
    ///
    /// - Returns:
    ///     - **`rangeOffset`**: range 的起始偏移地址，相对于 `chunkBegin`
    ///     - **`chunkBegin`**: chunks 的起始字节位
    ///     - **`chunks`**: 需要处理的 chunks
    ///
    /// -----------
    /// ### 输入参数:
    /// ```
    ///               [-------------------------]                           : range
    /// [----   |--------   |----   |------   |----   |------   |---   ]    : chunks
    /// [-------|-----------|-------|---------|-------|---------|------]
    ///      |  |        |  |    |  |      |  |    |  |      |  |   |  |
    ///      <-->        <-->    <-->      <-->    <-->      <-->   <-->    : offset
    /// ```
    ///
    /// ### 返回参数:
    /// ```
    ///               [-------------------------]                           : range
    /// [----   |--------   |----   |------   |----   |------   |---   ]    : chunks
    /// [-------|-----------|-------|---------|-------|---------|------]
    /// |       |     |                               |
    /// |       <----->                               |                     : rangeOffset
    /// <------->                                     |                     : chunkBegin
    ///         <------------------------------------->                     : chunks
    /// ```
    ///
    static func rangeIntersection(_ range: Range<Int64>, in chunks: [Int64], offset: Int64) throws(BscError<RangeIntersectionErrcase>) -> Intersection {
        var res: [Int64] = []
        var record = false
        var curChunkIndex = Int64(0)
        var rangeBegin = Int64(-1)
        var chunkBegin = Int64(-1)
        for (i, chunk) in chunks.enumerated() {
            
            let curChunkRange = curChunkIndex..<(curChunkIndex + chunk)
            
            if curChunkRange.contains(range.lowerBound) {
                // 开始记录
                rangeBegin = range.lowerBound - curChunkRange.lowerBound
                chunkBegin = curChunkRange.lowerBound + Int64(i) * offset
                
                // 如果 range 是空的，在此处退出，保证 rangeBegin 与 chunkBegin 正确设置
                guard !range.isEmpty else { break }
                
                record = true
            }
            
            if record {
                res.append(chunk + Int64(offset))
            }
            
            // 若查到 range 到头，则终止记录
            guard range.isEmpty || !curChunkRange.contains(range.upperBound - 1) else { record = false; break }
            
            curChunkIndex += chunk
        }
        
        guard record == false else { throw .init(.rangeSizeExceed) }
        guard rangeBegin != -1 else { throw .init(.rangeNotFound) }
        
        return .init(rangeOffset: rangeBegin, chunkBegin: chunkBegin, chunks: res)
    }
    
    public enum RangeIntersectionErrcase: String, ErrList {
        case rangeNotFound = "Range 起始边界未找到"
        case rangeSizeExceed = "Range 结束边界未找到，其大小超过限制"
    }
    
    static func rangeIntersection(_ range: ClosedRange<Int64>, in chunks: [Int64], offset: Int64) throws(BscError<RangeIntersectionErrcase>) -> Intersection {
        try rangeIntersection(.init(range), in: chunks, offset: offset)
    }
    
    public enum IndexErrcase: String, ErrList {
        case intersectionFailed = "落点计算失败"
    }
    
    static func index(_ index: Int64, in buffer: [Int64], offset: Int64) throws(BscError<IndexErrcase>) -> (rangeOffset: Int64, chunkBegin: Int64) {
        let intersection = try required(throws: BscError<IndexErrcase>(.intersectionFailed)) {
            try rangeIntersection(index..<index, in: buffer, offset: offset)
        }
        return (intersection.rangeOffset, intersection.chunkBegin)
    }
}
