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
        guard index.type == .file else { throw Errcase.getFileFailed.d("目标并非是一个文件，而是 \(index.type)") }
        guard let mimeType = index.mimeType else { throw Errcase.getFileFailed.d("文件 mime-type 未找到") }
        
        self.id = try required(throws: Errcase.getFileFailed, "获取文件 ID 失败") {
            try index.requireID()
        }
        
        self.name = index.name
        self.mimeType = mimeType
        self.path = parent + index.name
        self.createdAt = index.createdAt
        self.storage = storage
        self.fileIndex = index
    }
}

public extension File {
    func openForRead() async -> Res<FileReader, Errcase> {
        await .async { () throws(BscError<Errcase>) in
            let (fileCrypto, key, filePath) = try await required(throws: Errcase.openFileFailed, "获取文件信息失败") {
                try await makeFileHandleParas()
            }
            let fileHandler = try await required(throws: File.Errcase.openFileFailed) {
                try await FileSystem.shared.openFile(forReadingAt: filePath, options: .init())
            }
            return Reader(
                fileIndex: fileIndex,
                fileCrypto: fileCrypto,
                key: key,
                filePath: path,
                fileRealPath: filePath,
                fileHandler: fileHandler,
                storage: storage
            )
        }
    }
    
    func openForWrite() async -> Res<FileWriter, Errcase> {
        await .async { () throws(BscError<Errcase>) in
            let (fileCrypto, key, filePath) = try await required(throws: Errcase.openFileFailed, "获取文件信息失败") {
                try await makeFileHandleParas()
            }
            let fileHandler = try await required(throws: File.Errcase.openFileFailed) {
                try await FileSystem.shared.openFile(forWritingAt: filePath, options: .modifyFile(createIfNecessary: false))
            }
            return Writer(
                fileIndex: fileIndex,
                fileCrypto: fileCrypto,
                key: key,
                filePath: path,
                fileRealPath: filePath,
                fileHandler: fileHandler,
                storage: storage
            )
        }
    }
    
    func openForReadAndWrite() async -> Res<FileReaderAndWriter, Errcase> {
        await .async { () throws(BscError<Errcase>) in
            let (fileCrypto, key, filePath) = try await required(throws: Errcase.openFileFailed, "获取文件信息失败") {
                try await makeFileHandleParas()
            }
            let fileHandler = try await required(throws: File.Errcase.openFileFailed) {
                try await FileSystem.shared.openFile(forReadingAndWritingAt: filePath, options: .modifyFile(createIfNecessary: false))
            }
            return ReaderAndWriter(
                fileIndex: fileIndex,
                fileCrypto: fileCrypto,
                key: key,
                filePath: path,
                fileRealPath: filePath,
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
        if force {
            return storage.db.eventLoop.makeFutureWithTask {
                try await getRealFilePath().0
            }.withError(Errcase.deleteFileFailed, "获取文件路径失败")
            .flatMap { filePath in
                fileIndex.delete(force: force, on: storage.db)
                    .map { filePath }
                    .withError(Errcase.deleteFileFailed, "数据库删除记录失败")
            }.flatMap { filePath in
                storage.db.eventLoop.makeFutureWithTask {
                    try await FileSystem.shared.removeItem(at: filePath)
                }.withError(Errcase.deleteFileFailed, "从文件系统删除加密文件失败")
            }
        } else {
            return fileIndex.delete(force: force, on: storage.db)
                .withError(Errcase.deleteFileFailed, "数据库删除记录失败")
        }
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
        fileIndex.$parent.id = dir.fileIndex.isRoot ? nil : dir.id
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
    
    enum FileParaFetchErrcase: String, ErrList {
        case databaseFailed = "数据库查询失败"
        case fileNotExist = "文件不存在"
        case keyDeriveFailed = "派生密钥生成失败"
    }
    
    func getRealFilePath() async throws(BscError<FileParaFetchErrcase>) -> (FilePath, FileCrypto) {
        guard
            let fileCrypto = try await FileCrypto.query(on: storage.indexDatabase)
                .filter(\.$id == id)
                .first()
                .withError(FileParaFetchErrcase.databaseFailed)
                .get()
        else {
            throw FileParaFetchErrcase.fileNotExist.d(self.path.string)
        }
         
        return (
            .init("\(self.storage.storagePath)/\(fileCrypto.storageKey).\(FileStorage.CryptoFileExtension)"),
            fileCrypto
        )
    }
    
    func makeFileHandleParas() async throws(BscError<FileParaFetchErrcase>) -> (
        FileCrypto, Crypto.Symm.Key, FilePath
    ) {
        let (filePath, fileCrypto) = try await getRealFilePath()
        
        // 创建派生密钥
        let key = try required(throws: FileParaFetchErrcase.keyDeriveFailed) {
            try self.storage.masterKey.derive(salt: fileCrypto.salt, info: fileCrypto.sharedData).get()
        }
        
        return (fileCrypto, key, filePath)
    }
}

extension File: CustomStringConvertible {
    public var description: String {
        """
        File (
            id: \(id.uuidString)
            name: \(name)
            mimeType: \(mimeType.rawValue)
            size: \(size)
            path: \(path.string)
            createdAt: \(createdAt)
            updatedAt: \(updatedAt)
        )
        """
    }
}
