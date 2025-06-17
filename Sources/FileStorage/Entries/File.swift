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
//    
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
        let intersectionResult: ChunkHelpers.IntersectionResult
        
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

extension AsyncThrowingChannel where Failure == Error {
    func castError<NewError: Error>(to _: NewError.Type) -> AsyncThrowingChannel<Element, NewError> {
        unsafeBitCast(self, to: AsyncThrowingChannel<Element, NewError>.self)
    }
}
