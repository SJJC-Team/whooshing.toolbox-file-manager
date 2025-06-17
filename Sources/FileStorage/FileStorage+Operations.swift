import Fluent
import Foundation
import Cryptos
import DataConvertable
import ErrorHandle
import NIOCore
import NIOAdvanced
import NIOFileSystem
import CryptoKit

public extension FileStorage {
    enum Errcase: String, ErrList {
        case databaseInitFailed = "数据库连接失败"
        case fileSystemInitFailed = "文件系统初始化失败"
        case unknow = "未知错误"
        
        // 目录相关错误
        case directoryCreateFailed = "目录创建失败"
        case directoryGetFailed = "目录获取失败"
        case indexTypeIsNotDirectory = "目标并非是一个目录"
        case fetchDirectoryIdFailed = "获取目录 ID 失败"
        case fetchSubItemFailed = "获取子项目失败"
        case deleteDirectoryFailed = "删除目录失败"
        case renameDirectoryFailed = "重命名目录失败"
        case moveDirectoryFailed = "移动目录失败"
        
        // 文件相关错误
        case fileCreateFailed = "文件创建失败"
        case fileGetFailed = "文件获取失败"
        case fileIsNotExist = "文件不存在"
        case fetchFileIdFailed = "获取文件 ID 失败"
        case indexTypeIsNotFile = "目标并非是一个文件"
        case deleteFileFailed = "删除文件失败"
        case renameFileFailed = "重命名文件失败"
        case moveFileFailed = "移动文件失败"
        case readFileFailed = "文件读取失败"
        case writeFileFailed = "文件写入失败"
        case openFileFailed = "文件打开失败"
    }
}

public extension FileStorage {
    func createDirectory(
        at path: StoragePath,
        withIntermediateDirectories createIfNeed: Bool = false,
        slience: Bool = false
    ) -> EventLoopResult<Directory, BscError<Errcase>> {
        getParent(at: path, withIntermediateDirectories: createIfNeed)
            .errCast(Errcase.directoryCreateFailed, "获取父目录 \"\(path.parent)\" 失败")
            .flatMap
        { parent in
            // 检查要创建的目录是否已经存在
            self.getChild(at: parent, name: path.last!)
                .errCast(Errcase.directoryCreateFailed, "未知错误")
                .flatMap
            { fileIndex in
                if let existedIndex = fileIndex, existedIndex.type == .directory {
                    // 要创建的目录已经存在，若指定 slience 则不做任何事，否则抛出错误
                    if slience {
                        return self.eventLoop.makeSucceededResult(existedIndex)
                    } else {
                        return self.eventLoop.makeFailedResult(Errcase.directoryCreateFailed.d("目录 \"\(path)\" 已存在"))
                    }
                } else {
                    // 要创建的目录不存在，创建新目录
                    return self.newDirIndex(parent: parent, path: path).errCast(Errcase.directoryCreateFailed, "创建目录 \"\(path)\" 失败")
                }
            }
        }.flatMapThrowing { fileIndex throws(BscError<Errcase>) in
            try required(throws: Errcase.directoryGetFailed) {
                try .init(from: fileIndex, parent: path.parent, storage: self)
            }
        }
    }
    
    func getDirectory(at path: StoragePath) -> EventLoopResult<Directory, BscError<Errcase>> {
        get(at: path)
            .errCast(Errcase.directoryGetFailed)
            .flatMapThrowing
        { fileIndex throws(BscError<Errcase>) in
            try required(throws: Errcase.directoryGetFailed) {
                try .init(from: fileIndex, parent: path.parent, storage: self)
            }
        }
    }
}

public extension FileStorage {
    func createFile(
        at path: StoragePath,
        withIntermediateDirectories createIfNeed: Bool = false,
        slience: Bool = false
    ) -> EventLoopResult<File, BscError<Errcase>> {
        getParent(at: path, withIntermediateDirectories: createIfNeed)
            .errCast(Errcase.fileCreateFailed, "获取父目录 \"\(path.parent)\" 失败")
            .flatMap
        { parent in
            // 检查要创建的目录是否已经存在
            self.getChild(at: parent, name: path.last!)
                .errCast(Errcase.fileCreateFailed, "未知错误")
                .flatMap
            { fileIndex in
                if let existedIndex = fileIndex, existedIndex.type == .file {
                    // 要创建的文件已经存在，若指定 slience 则不做任何事，否则抛出错误
                    if slience {
                        return self.eventLoop.makeSucceededResult(existedIndex)
                    } else {
                        return self.eventLoop.makeFailedResult(Errcase.fileCreateFailed.d("目录 \"\(path)\" 已存在"))
                    }
                } else {
                    // 要创建的文件不存在，创建新文件
                    return self.newFileIndex(parent: parent, path: path).errCast(Errcase.fileCreateFailed, "创建文件 \"\(path)\" 失败")
                }
            }
        }.flatMapThrowing { fileIndex throws(BscError<Errcase>) in
            try required(throws: Errcase.fileGetFailed) {
                try .init(from: fileIndex, parent: path.parent, storage: self)
            }
        }
    }
    
    func getFile(at path: StoragePath) -> EventLoopResult<File, BscError<Errcase>> {
        get(at: path)
            .errCast(Errcase.fileGetFailed)
            .flatMapThrowing
        { fileIndex throws(BscError<Errcase>) in
            try required(throws: Errcase.fileGetFailed) {
                try .init(from: fileIndex, parent: path.parent, storage: self)
            }
        }
    }
}

extension FileStorage {
    
    func get(at path: StoragePath) -> EventLoopResult<FileIndex, BscError<FindEntryErrcase>> {
        findEntry(at: path) {
            guard let fileIndex = $0.index else {
                return self.eventLoop.makeFailedResult(FindEntryErrcase.entryNotExist)
            }
            return self.eventLoop.makeSucceededResult(fileIndex)
        }
    }
    
    typealias ActionContext = (index: FileIndex?, path: StoragePath, parent: FileIndex)
    
    public enum FindEntryErrcase: String, ErrList {
        case getChildFailed = "获取子实例时发生错误"
        case actionFailed = "自定义任务失败"
        case entryNotExist = "实体对象不存在"
        case directoryExisted = "目录已经存在"
        case directoryNotExist = "目录不存在"
        case databaseFailed = "数据库操作出现错误"
    }
    
    func findEntry<ErrorType>(
        at path: StoragePath,
        action: @escaping @Sendable (ActionContext) -> EventLoopResult<FileIndex, ErrorType>
    ) -> EventLoopResult<FileIndex, BscError<FindEntryErrcase>> {
        
        let curPath = StoragePath.root
        var r = self.eventLoop.makeSucceededResult((self.rootDirIndex, curPath), throws: BscError<FindEntryErrcase>.self)
        
        for component in path {
            r = r.flatMap { fileIndex, path in
                let curPath = path + component
                return self.getChild(at: fileIndex, name: component)
                    .errCast(FindEntryErrcase.getChildFailed)
                    .flatCast { action(($0, curPath, fileIndex)).errCast(FindEntryErrcase.actionFailed) }
                    .flatMap
                { fileIndex in
                    self.eventLoop.makeSucceededResult((fileIndex, curPath))
                }
            }
        }
        
        return r.map { $0.0 }
    }
    
    public enum DatabaseErrcase: String, ErrList {
        case saveFailed = "数据库保存动作失败"
        case queryFailed = "数据库查询失败"
        case fetchIdFailed = "获取实例 ID 失败"
    }
    
    func getChild(
        at index: FileIndex,
        name: String
    ) -> EventLoopResult<FileIndex?, BscError<DatabaseErrcase>> {
        let id: UUID?
        
        do {
            id = try index.getId()
        } catch {
            return eventLoop.makeFailedResult(DatabaseErrcase.fetchIdFailed.subErr(error))
        }
        
        return FileIndex.query(on: self.indexDatabase)
            .filter(\.$parent.$id == id)
            .filter(\.$name == name)
            .first()
            .withError(DatabaseErrcase.queryFailed)
    }
    
    func getParent(
        at path: StoragePath,
        withIntermediateDirectories createIfNeed: Bool = false
    ) -> EventLoopResult<FileIndex, BscError<FindEntryErrcase>> {
        guard !path.isRoot else { preconditionFailure("不允许创建系统根") }
        if path.parent.isRoot {
            // 在根目录下创建文件夹
            return self.eventLoop.makeSucceededResult(self.rootDirIndex)
        } else {
            // 非根目录下创建文件夹，需要找到要创建目录的父目录
            return findEntry(at: path.parent) { index, path, parent in
                if let fileIndex = index {
                    // 该级目录存在
                    guard fileIndex.type == .directory else {
                        return self.eventLoop.makeFailedResult(FindEntryErrcase.directoryExisted)
                    }
                    return self.eventLoop.makeSucceededResult(fileIndex)
                } else {
                    // 该级目录不存在
                    if !createIfNeed {
                        // 若用户指定 createIfNeed 为 false，直接抛出错误
                        return self.eventLoop.makeFailedResult(FindEntryErrcase.directoryNotExist)
                    }
                    // 为该级创建新目录，因为用户指定了 createIfNeed
                    return self.newDirIndex(parent: parent, path: path).errCast(FindEntryErrcase.databaseFailed)
                }
            }
        }
    }
    
    @Sendable func newDirIndex(
        parent: FileIndex?,
        path: StoragePath
    ) -> EventLoopResult<FileIndex, BscError<DatabaseErrcase>> {
        let new = FileIndex()
        new.id = .init()
        new.parent = parent
        new.type = .directory
        new.mimeType = nil
        new.name = path.last!
        return new.save(on: self.indexDatabase).map { new }.withError()
    }
    
    @Sendable func newFileIndex(
        parent: FileIndex?,
        path: StoragePath
    ) -> EventLoopResult<FileIndex, BscError<DatabaseErrcase>> {
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
        fileCrypto.chunks = []
        fileCrypto.chunkTags = []
        fileCrypto.encryptedSize = 0
        fileCrypto.salt = saltGenerate()
        fileCrypto.sharedData = sharedDataGenerate(file: file)
        fileCrypto.storageKey = storageKeyGenerate(file: file)
        
        return indexDatabase.transaction { db in
            file.save(on: db).flatMap {
                fileCrypto.save(on: db).map { file }
            }
        }.withError(DatabaseErrcase.saveFailed)
        
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
