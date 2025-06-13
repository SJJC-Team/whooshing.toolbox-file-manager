import AsyncAlgorithms
import NIOCore
import Foundation
import FluentKit
import ErrorHandle
import Cryptos
import NIOFileSystem

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
    
    let fileIndex: FileIndex
    
    init(
        from index: FileIndex,
        parent: StoragePath,
        storage: FileStorage
    ) throws {
        guard
            index.type == .file,
            let size = index.size
        else { throw Err.indexTypeIsNotFile.d(16022) }
        
        self.id = try index.requireID()
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
    
    enum Err: String, ErrList {
        public var domain: String { "woo.sys.file.storage.file.err" }
        case fileIsNotExist = "文件不存在"
        case indexTypeIsNotFile = "目标并非是一个文件"
    }
    
    func isExist() -> Bool {
        (try? FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first().wait()) != nil
    }
    
    func isExist() async -> Bool {
        (try? await FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first()) != nil
    }
    
    func makeReader() -> EventLoopFuture<Handler> {
        FileCrypto.query(on: storage.indexDatabase).filter(\.$id == id).first().hop(to: storage.eventLoop).flatMap { fileCrypto in
            guard let fileCrypto = fileCrypto else {
                return self.storage.eventLoop.makeFailedFuture(Err.fileIsNotExist.d(16020))
            }
            return self.storage.eventLoop.makeFutureWithTask {
                // 创建派生密钥
                let key = try self.storage.masterKey.derive(fileCrypto.salt, info: fileCrypto.sharedData)
                // 打开加密文件，准备读取其加密内容
                let filePath = "\(self.storage.storagePath)/\(fileCrypto.storageKey)/\(FileStorage.CryptoFileExtension)"
                let fileHandler = try await FileSystem.shared.openFile(forReadingAt: .init(filePath), options: .init())
                // 将加密文件分割为 chunks，块大小为当初加密的块大小 + 加密增量大小
                let chunks = fileHandler.readChunks(chunkLength: .bytes(fileCrypto.chunkSize + Int64(Crypto.Symm.Stream.cipherExtraLength)))
                // 创建读取任务并异步进行读取
                let reader = Handler()
                Task {
                    do {
                        var i = 0
                        for try await chunk in chunks {
                            // 解密数据
                            let c: Data = try Crypto.Symm.Stream.decrypt(.init(buffer: chunk), key: key, chunkTag: i)
                            await reader.send(.init(data: c))
                            i += 1
                        }
                        try await fileHandler.close()
                        reader.finish()
                    } catch {
                        try? await fileHandler.close()
                        reader.fail(error)
                    }
                }
                return reader
            }
        }
    }
    
    func delete(force: Bool = false) -> EventLoopFuture<Void> {
        FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).delete(force: force)
    }
    
    func rename(as name: String) -> EventLoopFuture<File> {
        fileIndex.name = name
        return fileIndex.update(on: storage.indexDatabase).flatMapThrowing {
            try .init(from: fileIndex, parent: self.path.parent, storage: storage)
        }
    }
    
    func move(to dir: Directory, as name: String? = nil) -> EventLoopFuture<File> {
        fileIndex.parent = dir.fileIndex.isRoot ? nil : dir.fileIndex
        if let name = name {
            fileIndex.name = name
        }
        return fileIndex.update(on: storage.indexDatabase).flatMapThrowing {
            try .init(from: fileIndex, parent: self.path.parent, storage: storage)
        }
    }
}
