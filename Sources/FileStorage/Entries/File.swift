import AsyncAlgorithms
import NIOCore
import Foundation
import FluentKit
import ErrorHandle
import Cryptos
import NIOFileSystem
import NIOAdvanced

public struct File: StorageEntry, Sendable {
    
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
    
    enum Part: Sendable {
        case all
        case range(Range<Int64>)
        case closedRange(ClosedRange<Int64>)
    }
    
    func isExist() -> Bool {
        (try? FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first().wait()) != nil
    }
    
    func isExist() async -> Bool {
        (try? await FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first()) != nil
    }
    
//    func write(from start: Int64 = 0, with data: ByteBuffer) -> EventLoopResult<Void, BscError<Errcase>> {
//        // 创建读取任务准备进行异步写入
//        
//    }
    
    func read(part: Part = .all) -> AsyncThrowingChannel<ByteBuffer, BscError<Errcase>> {
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
        return reader.castError(to: BscError<Errcase>.self)
    }
    
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

extension File {
    // 带有 back pressure 机制地从加密文件中按指定的块读取数据并解密
    func backPressureRead(part: Part, reader: AsyncThrowingChannel<ByteBuffer, Error>) async throws(BscError<Errcase>) {
        guard
            let fileCrypto = try await FileCrypto.query(on: storage.indexDatabase)
                .filter(\.$id == id)
                .first()
                .withError(Errcase.readFileFailed, "数据库查询失败")
                .get()
        else {
            throw Errcase.readFileFailed.d("文件不存在")
        }
        
        guard fileCrypto.chunks.count == fileCrypto.chunkTags.count else {
            throw Errcase.readFileFailed.d("未知错误，数据块划分参数不同步")
        }
        
        // 准备读取的范围
        let readRange: Range<Int64>
        
        // 计算数据的落点分布
        let intersectionResult: ChunkHelpers.Intersection
        
        switch part {
        case .all:
            readRange = 0..<fileCrypto.encryptedSize
            intersectionResult = .init(rangeOffset: 0, chunkIndex: 0, chunkBegin: 0, chunks: fileCrypto.chunks)
        case .closedRange(let r):
            readRange = .init(r)
            intersectionResult = try required(throws: Errcase.readFileFailed, "ClosedRange 数据落点计算失败") {
                try ChunkHelpers.rangeIntersection(r, in: fileCrypto.chunks, offset: Int64(Crypto.Symm.Stream.cipherExtraLength))
            }
        case .range(let r):
            readRange = r
            intersectionResult = try required(throws: Errcase.readFileFailed, "Range 数据落点计算失败") {
                try ChunkHelpers.rangeIntersection(r, in: fileCrypto.chunks, offset: Int64(Crypto.Symm.Stream.cipherExtraLength))
            }
        }
        
        // 创建派生密钥
        let key = try required(throws: Errcase.readFileFailed, "派生密钥生成失败") {
            try self.storage.masterKey.derive(fileCrypto.salt, info: fileCrypto.sharedData)
        }
        
        // 打开加密文件，准备读取其加密内容
        let filePath = "\(self.storage.storagePath)/\(fileCrypto.storageKey)/\(FileStorage.CryptoFileExtension)"
        let fileHandler = try await required(throws: Errcase.readFileFailed, "文件打开失败") {
            try await FileSystem.shared.openFile(forReadingAt: .init(filePath), options: .init())
        }
        
        do {
            // 遍历读取数据
            var curCryptedChunkIndex = intersectionResult.chunkBegin
            var curChunkIndex = intersectionResult.chunkIndex
            var curByteIndex = 0
            for chunkSize in intersectionResult.chunks {
                
                guard curByteIndex < readRange.count else { break }
                
                // 判断当读取的数据大小
                let size = min(readRange.count - curByteIndex, Int(chunkSize))
                
                // 读取文件中的加密数据
                let chunk = try await fileHandler.readChunks(
                    in: curCryptedChunkIndex..<(curCryptedChunkIndex + chunkSize),
                    chunkLength: .bytes(chunkSize)
                ).collect(upTo: Int(chunkSize))
                
                // 解密数据
                let c: ByteBuffer = try Crypto.Symm.Stream.decrypt(chunk.data(), key: key, chunkTag: fileCrypto.chunkTags[curChunkIndex])
                
                guard c.readableBytes >= size else {
                    throw Errcase.readFileFailed.d("所要读取的大小大过文件数据的大小")
                }
                
                guard let slice = c.peekSlice(length: size) else {
                    throw Errcase.readFileFailed.d("数据切片失败")
                }
                        
                // 通过数据通道传输数据
                await reader.send(slice)
                
                curChunkIndex += 1
                curByteIndex += size
                curCryptedChunkIndex += chunkSize
            }
            
            try await fileHandler.close()
        } catch let error as BscError<Errcase> {
            try? await fileHandler.close()
            throw error
        } catch let error {
            try? await fileHandler.close()
            throw Errcase.readFileFailed.d("读取数据失败").subErr(error)
        }
    }
    
    enum WriteMethod: Sendable {
        case overwrite
        case insert
    }
    
    func backPressureWrite(
        from startIndex: Int64,
        with data: ByteBuffer,
        method: WriteMethod = .insert
    ) async throws(BscError<Errcase>) {
        guard
            let fileCrypto = try await FileCrypto.query(on: storage.indexDatabase)
                .filter(\.$id == id)
                .first()
                .withError(Errcase.writeFileFailed, "数据库查询失败")
                .get()
        else {
            throw Errcase.writeFileFailed.d("文件不存在")
        }
        
        guard fileCrypto.encryptedSize >= startIndex else {
            throw Errcase.writeFileFailed.d("写指针起始索引超出限制，总大小为 \(fileCrypto.encryptedSize), 却得到 \(startIndex)")
        }
        
        
        
    }
}

enum ChunkHelpers {
    
    struct Intersection: Equatable, CustomStringConvertible {
        let rangeOffset: Int64
        let chunkIndex: Int
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
    ///     - **`chunkIndex`**: chunks 的起始索引
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
    /// <------->                                     |                     : chunkIndex(Index)
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
        var chunkIndex = -1
        for (i, chunk) in chunks.enumerated() {
            let curChunkRange = curChunkIndex..<(curChunkIndex + chunk)
            
            if curChunkRange.contains(range.lowerBound) {
                // 开始记录
                rangeBegin = range.lowerBound - curChunkRange.lowerBound
                chunkBegin = curChunkRange.lowerBound + Int64(i) * offset
                chunkIndex = i
                
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
        
        return .init(rangeOffset: rangeBegin, chunkIndex: chunkIndex, chunkBegin: chunkBegin, chunks: res)
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

extension AsyncThrowingChannel where Failure == Error {
    func castError<NewError: Error>(to _: NewError.Type) -> AsyncThrowingChannel<Element, NewError> {
        unsafeBitCast(self, to: AsyncThrowingChannel<Element, NewError>.self)
    }
}
