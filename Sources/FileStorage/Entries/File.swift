import AsyncAlgorithms
import NIOCore
import Foundation
import FluentKit
import ErrorHandle
import Cryptos
import NIOFileSystem
import NIOAdvanced

public typealias FileReaderAndWriter = FileReader & FileWriter

public struct File: StorageEntry, Sendable {
    
    public let id: UUID
    public let name: String
    public let mimeType: MimeType
    public var size: Int64 { fileIndex.size! }
    public let path: StoragePath
    public let createdAt: Date
    public var updatedAt: Date { fileIndex.updatedAt }
    
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
        self.path = parent + index.name
        self.createdAt = index.createdAt
        self.storage = storage
        self.fileIndex = index
    }
}

public extension File {
    func openForRead() async -> Res<FileReader, Errcase> {
         await .async { () throws(BscError<Errcase>) in
            let (fileCrypto, key, filePath) = try await makeFileHandleParas()
            let fileHandler = try await required(throws: File.Errcase.openFileFailed) {
                try await FileSystem.shared.openFile(forReadingAt: filePath, options: .init())
            }
            return Reader(
                fileIndex: fileIndex,
                fileCrypto: fileCrypto,
                key: key,
                fileHandler: fileHandler,
                storage: storage
            )
        }
    }
    
    func openForWrite() async -> Res<FileWriter, Errcase> {
        await .async { () throws(BscError<Errcase>) in
            let (fileCrypto, key, filePath) = try await makeFileHandleParas()
            let fileHandler = try await required(throws: File.Errcase.openFileFailed) {
                try await FileSystem.shared.openFile(forWritingAt: filePath, options: .modifyFile(createIfNecessary: false))
            }
            return Writer(
                fileIndex: fileIndex,
                fileCrypto: fileCrypto,
                key: key,
                fileHandler: fileHandler,
                storage: storage
            )
        }
    }
    
    func openForReadAndWrite() async -> Res<FileReaderAndWriter, Errcase> {
        await .async { () throws(BscError<Errcase>) in
            let (fileCrypto, key, filePath) = try await makeFileHandleParas()
            let fileHandler = try await required(throws: File.Errcase.openFileFailed) {
                try await FileSystem.shared.openFile(forReadingAndWritingAt: filePath, options: .modifyFile(createIfNecessary: false))
            }
            return ReaderAndWriter(
                fileIndex: fileIndex,
                fileCrypto: fileCrypto,
                key: key,
                fileHandler: fileHandler,
                storage: storage
            )
        }
    }
}

public extension File {
    
    func isExist() -> Bool {
        (try? FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first().wait()) != nil
    }
    
    func isExist() async -> Bool {
        (try? await FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first()) != nil
    }
    
    func delete(force: Bool = false) -> EventLoopRes<Void, Errcase> {
        FileIndex.query(on: storage.indexDatabase)
            .filter(\.$id == id)
            .delete(force: force)
            .withError(Errcase.deleteFileFailed, "数据库删除记录失败")
    }
    
    func rename(as name: String) -> EventLoopRes<File, Errcase> {
        fileIndex.name = name
        fileIndex.mimeType = name.fileExtension == nil ? .unknow : .init(fileExtension: name.fileExtension!)
        return fileIndex.update(on: storage.indexDatabase)
            .withError(Errcase.renameFileFailed, "数据库更新失败")
            .flatMapThrowing
        { () throws(BscError<Errcase>) in
            try required(throws: Errcase.renameFileFailed, "未知错误") {
                try .init(from: fileIndex, parent: self.path.parent, storage: storage)
            }
        }
    }
    
    func move(to dir: Directory, as name: String? = nil) -> EventLoopRes<File, Errcase> {
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
    func makeFileHandleParas() async throws(BscError<Errcase>) -> (
        FileCrypto, Crypto.Symm.Key, FilePath
    ) {
        guard
            let fileCrypto = try await FileCrypto.query(on: storage.indexDatabase)
                .filter(\.$id == id)
                .first()
                .withError(Errcase.writeFileFailed, "数据库查询失败")
                .get()
        else {
            throw Errcase.writeFileFailed.d("文件不存在")
        }
        
        // 创建派生密钥
        let key = try required(throws: Errcase.writeFileFailed, "派生密钥生成失败") {
            try self.storage.masterKey.derive(salt: fileCrypto.salt, info: fileCrypto.sharedData).get()
        }
        
        let filePath = FilePath("\(self.storage.storagePath)/\(fileCrypto.storageKey).\(FileStorage.CryptoFileExtension)")
        
        return (fileCrypto, key, filePath)
    }
}
