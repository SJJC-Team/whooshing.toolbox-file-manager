import Fluent
import Foundation
import Cryptos
import DataConvertable
import ErrorHandle
import NIOCore
import NIOFileSystem
import CryptoKit

public extension FileStorage {
    enum Err: String, ErrList {
        public var domain: String { "woo.sys.file.storage.err" }
        case databaseInitFailed = "数据库连接失败"
        case fileSystemInitFailed = "文件系统初始化失败"
        case fileCreateFailed = "文件创建失败"
        case directoryCreateFailed = "目录创建失败"
        case fileGetFailed = "文件获取失败"
        case directoryGetFailed = "目录获取失败"
        case unknow = "未知错误"
    }
}

public extension FileStorage {
    func createDirectory(
        at path: StoragePath,
        withIntermediateDirectories createIfNeed: Bool = false,
        slience: Bool = false
    ) -> EventLoopFuture<Directory> {
        getParent(at: path, withIntermediateDirectories: createIfNeed).flatMap { parent in
            // 检查要创建的目录是否已经存在
            self.getChild(at: parent, name: path.last!).flatMap { fileIndex in
                if let existedIndex = fileIndex, existedIndex.type == .directory {
                    // 要创建的目录已经存在，若指定 slience 则不做任何事，否则抛出错误
                    if slience {
                        return self.eventLoop.makeSucceededFuture(existedIndex)
                    } else {
                        return self.eventLoop.makeFailedFuture(Err.directoryCreateFailed.d("目录 \"\(path)\" 已存在", 16026))
                    }
                } else {
                    // 要创建的目录不存在，创建新目录
                    return self.newDirIndex(parent: parent, path: path)
                }
            }
        }.flatMapThrowing { fileIndex in
            try Directory(from: fileIndex, parent: path.parent, storage: self)
        }.flatMapErrorThrowing { error in
            throw Err.directoryCreateFailed.d(16032).subErr(error)
        }
    }
    
    func getDirectory(at path: StoragePath) -> EventLoopFuture<Directory> {
        get(at: path).flatMapThrowing { fileIndex in
            try .init(from: fileIndex, parent: path.parent, storage: self)
        }.flatMapErrorThrowing { error in
            throw Err.directoryGetFailed.d(16030).subErr(error)
        }
    }
}

public extension FileStorage {
    func createFile(
        at path: StoragePath,
        withIntermediateDirectories createIfNeed: Bool = false,
        slience: Bool = false
    ) -> EventLoopFuture<File> {
        getParent(at: path, withIntermediateDirectories: createIfNeed).flatMap { parent in
            // 检查要创建的文件是否已经存在
            self.getChild(at: parent, name: path.last!).flatMap { fileIndex in
                if let existedIndex = fileIndex, existedIndex.type == .file {
                    // 要创建的文件已经存在，若指定 slience 则不做任何事，否则抛出错误
                    if slience {
                        return self.eventLoop.makeSucceededFuture(existedIndex)
                    } else {
                        return self.eventLoop.makeFailedFuture(Err.directoryCreateFailed.d("目录 \"\(path)\" 已存在", 16026))
                    }
                } else {
                    // 要创建的文件不存在，创建新文件
                    return self.newFileIndex(parent: parent, path: path)
                }
            }
        }.flatMapThrowing { fileIndex in
            try .init(from: fileIndex, parent: path.parent, storage: self)
        }.flatMapErrorThrowing { error in
            throw Err.fileCreateFailed.d(16032).subErr(error)
        }
    }
    
    func getFile(at path: StoragePath) -> EventLoopFuture<File> {
        get(at: path).flatMapThrowing { fileIndex in
            try File(from: fileIndex, parent: path.parent, storage: self)
        }.flatMapErrorThrowing { error in
            throw Err.fileGetFailed.d(16031).subErr(error)
        }
    }
}

extension FileStorage {
    
    enum GetError: Error {
        case entryNotExist
    }
    func get(at path: StoragePath) -> EventLoopFuture<FileIndex> {
        findEntry(at: path) {
            guard let fileIndex = $0.index else {
                return self.eventLoop.makeFailedFuture(GetError.entryNotExist)
            }
            return self.eventLoop.makeSucceededFuture(fileIndex)
        }
    }
    
    typealias ActionContext = (index: FileIndex?, path: StoragePath, parent: FileIndex)
    
    func findEntry(
        at path: StoragePath,
        action: @escaping @Sendable (ActionContext) -> EventLoopFuture<FileIndex>
    ) -> EventLoopFuture<FileIndex> {
        
        let curPath = StoragePath.root
        var r = self.eventLoop.makeSucceededFuture((self.rootDirIndex, curPath))
        
        for component in path {
            r = r.flatMap { fileIndex, path in
                let curPath = path + component
                return self.getChild(at: fileIndex, name: component)
                    .flatMap { action(($0, curPath, fileIndex)) }
                    .flatMap
                { fileIndex in
                    self.eventLoop.makeSucceededFuture((fileIndex, curPath))
                }
            }
        }
        
        return r.map { $0.0 }
    }
    
    func getChild(
        at index: FileIndex,
        name: String
    ) -> EventLoopFuture<FileIndex?> {
        do {
            let id = try index.getId()
            return FileIndex.query(on: self.indexDatabase)
                .filter(\.$parent.$id == id)
                .filter(\.$name == name)
                .first()
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
    }
    
    enum GetParentErr: Error {
        case directoryExisted
        case directoryNotExist
    }
    func getParent(
        at path: StoragePath,
        withIntermediateDirectories createIfNeed: Bool = false
    ) -> EventLoopFuture<FileIndex> {
        guard !path.isRoot else { preconditionFailure("不允许创建系统根") }
        if path.parent.isRoot {
            // 在根目录下创建文件夹
            return self.eventLoop.makeSucceededFuture(self.rootDirIndex)
        } else {
            // 非根目录下创建文件夹，需要找到要创建目录的父目录
            return findEntry(at: path.parent) { index, path, parent in
                if let fileIndex = index {
                    // 该级目录存在
                    guard fileIndex.type == .directory else {
                        return self.eventLoop.makeFailedFuture(GetParentErr.directoryExisted)
                    }
                    return self.eventLoop.makeSucceededFuture(fileIndex)
                } else {
                    // 该级目录不存在
                    if !createIfNeed {
                        // 若用户指定 createIfNeed 为 false，直接抛出错误
                        return self.eventLoop.makeFailedFuture(GetParentErr.directoryNotExist)
                    }
                    // 为该级创建新目录，因为用户指定了 createIfNeed
                    return self.newDirIndex(parent: parent, path: path)
                }
            }
        }
    }
    
    @Sendable func newDirIndex(parent: FileIndex?, path: StoragePath) -> EventLoopFuture<FileIndex> {
        let new = FileIndex()
        new.id = .init()
        new.parent = parent
        new.type = .directory
        new.mimeType = nil
        new.name = path.last!
        return new.save(on: self.indexDatabase).map { new }
    }
    
    @Sendable func newFileIndex(parent: FileIndex?, path: StoragePath) -> EventLoopFuture<FileIndex> {
        let file = FileIndex()
        file.id = .init()
        file.name = path.last!
        if let extensionName = file.name.components(separatedBy: ".").last {
            file.mimeType = .init(rawValue: extensionName)
        } else {
            file.mimeType = .unknow
        }
        file.type = .file
        file.size = 0
        file.parent = parent
        
        let fileCrypto = FileCrypto()
        fileCrypto.fileIndex = file
        fileCrypto.chunkSize = 65535
        fileCrypto.encryptedSize = 0
        fileCrypto.salt = saltGenerate()
        fileCrypto.sharedData = sharedDataGenerate(file: file)
        fileCrypto.storageKey = storageKeyGenerate(file: file)
        
        return indexDatabase.transaction { db in
            file.save(on: db).flatMap {
                fileCrypto.save(on: db).map { file }
            }
        }
        
        func saltGenerate() -> Base64String {
            var salt = Data()
            let timestamp = UInt64(Date().timeIntervalSince1970)
            // 时间戳
            salt += timestamp.data()
            // 加一段 16 字节的随机数
            salt += Crypto.randomDataGenerate(length: 16)
            return .init(data: salt)
        }
        
        func sharedDataGenerate(file: FileIndex) -> String {
            var res = ""
            // 加文件名称
            res += "<" + file.name + ">-<"
            // 加文件的 UUID
            res += file.id!.uuidString + ">"
            return res
        }
        
        func storageKeyGenerate(file: FileIndex) -> String {
            var key = Data()
            let timestamp = UInt64(Date().timeIntervalSince1970)
            // 时间戳
            key += timestamp.data()
            // 加一段 32 字节的随机数
            key += Crypto.randomDataGenerate(length: 32)
            let hash = SHA256.hash(data: key)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        }
    }
}
