import Fluent
import Foundation
import Crypto
import Cryptos
import DataConvertable
import ErrorHandle
import NIOCore
import NIOAdvanced
import NIOFileSystem

public extension FileStorage {
    /// FileStorage 所有可能抛出的错误类型枚举，按功能划分为数据库错误、目录操作错误、文件操作错误。
    enum Errcase: String, ErrList {
        case databaseInitFailed = "数据库连接失败"
        case fileSystemInitFailed = "文件系统初始化失败"
        case unknow = "未知错误"
        
        // 目录相关错误
        case createDirectoryFailed = "目录创建失败"
        case getDirectoryFailed = "目录获取失败"
        case fetchDirectorySubItemFailed = "获取子项目失败"
        case deleteDirectoryFailed = "删除目录失败"
        case renameDirectoryFailed = "重命名目录失败"
        case moveDirectoryFailed = "移动目录失败"
        case emptyDirectoryFailed = "清空目录失败"
        case fetchDirectorySizeFailed = "计算目录大小失败"
        
        // 文件相关错误
        case createFileFailed = "文件创建失败"
        case getFileFailed = "文件获取失败"
        case deleteFileFailed = "删除文件失败"
        case renameFileFailed = "重命名文件失败"
        case moveFileFailed = "移动文件失败"
        case readFileFailed = "文件读取失败"
        case writeFileFailed = "文件写入失败"
        case removeFileDataFailed = "文件数据抹除失败"
        case openFileFailed = "文件打开失败"
        case closeFileFailed = "文件关闭失败"
    }
}

public extension FileStorage {
    /// 创建一个目录，如果目录已存在则根据 `slience` 决定是否忽略。
    ///
    /// - Parameters:
    ///   - path: 要创建的目录路径。
    ///   - createIfNeed: 是否自动创建中间目录。
    ///   - slience: 如果目录已存在，是否忽略错误。
    ///
    /// - Returns: 创建完成或已存在的目录。
    func createDirectory(
        at path: StoragePath,
        withIntermediateDirectories createIfNeed: Bool = false,
        slience: Bool = false
    ) -> EventLoopRes<Directory, Errcase> {
        guard !path.isRoot else { preconditionFailure("不允许创建系统根") }
        
        return getParent(at: path, withIntermediateDirectories: createIfNeed)
            .errCast(Errcase.createDirectoryFailed, "获取父目录 \"\(path.parent)\" 失败")
            .flatMap
        { parent in
            // 检查要创建的目录是否已经存在
            self.getChild(at: parent, name: path.last!)
                .errCast(Errcase.createDirectoryFailed, "未知错误")
                .flatMap
            { fileIndex in
                if let existedIndex = fileIndex, existedIndex.type == .directory {
                    // 要创建的目录已经存在，若指定 slience 则不做任何事，否则抛出错误
                    if slience {
                        return self.eventLoop.makeSucceededResult(existedIndex)
                    } else {
                        return self.eventLoop.makeFailedResult(Errcase.createDirectoryFailed.d("目录 \"\(path)\" 已存在"))
                    }
                } else {
                    // 要创建的目录不存在，创建新目录
                    return self.newDirIndex(parent: parent, path: path).errCast(Errcase.createDirectoryFailed, "创建目录 \"\(path)\" 失败")
                }
            }
        }.flatMapThrowing { fileIndex throws(BscError<Errcase>) in
            try required(throws: Errcase.getDirectoryFailed, path.string) {
                try .init(from: fileIndex, parent: path.parent, storage: self)
            }
        }
    }
    
    /// 获取指定路径的目录对象。
    /// 
    /// - Parameter path: 目标目录路径。
    /// - Returns: 目录对象。
    func getDirectory(at path: StoragePath) -> EventLoopRes<Directory, Errcase> {
        get(at: path)
            .errCast(Errcase.getDirectoryFailed, path.string)
            .flatMapThrowing
        { fileIndex throws(BscError<Errcase>) in
            try required(throws: Errcase.getDirectoryFailed, path.string) {
                try .init(from: fileIndex, parent: path.parent, storage: self)
            }
        }
    }
}

public extension FileStorage {
    /// 创建一个新文件，支持设置分片大小与自动创建中间目录。
    ///
    /// - Parameters:
    ///   - path: 文件路径。
    ///   - chunkSize: 每个分片的大小（默认为 65535 字节）。
    ///   - createIfNeed: 是否自动创建中间目录。
    ///   - slience: 如果文件已存在，是否忽略错误。
    ///
    /// - Returns: 文件对象。
    func createFile(
        at path: StoragePath,
        chunkSize: Int64 = 65535,
        withIntermediateDirectories createIfNeed: Bool = false,
        slience: Bool = false
    ) -> EventLoopRes<File, Errcase> {
        guard !path.isEmpty else { preconditionFailure("不允许空文件路径") }
        
        return getParent(at: path, withIntermediateDirectories: createIfNeed)
            .errCast(Errcase.createFileFailed, "获取父目录 \"\(path.parent)\" 失败")
            .flatMap
        { parent in
            // 检查要创建的目录是否已经存在
            self.getChild(at: parent, name: path.last!)
                .errCast(Errcase.createFileFailed, "未知错误")
                .flatMap
            { fileIndex in
                if let existedIndex = fileIndex, existedIndex.type == .file {
                    // 要创建的文件已经存在，若指定 slience 则不做任何事，否则抛出错误
                    if slience {
                        return self.eventLoop.makeSucceededResult(existedIndex)
                    } else {
                        return self.eventLoop.makeFailedResult(Errcase.createFileFailed.d("文件 \"\(path)\" 已存在"))
                    }
                } else {
                    // 要创建的文件不存在，创建新文件
                    return self.newFileIndex(parent: parent, path: path, chunkSize: chunkSize).errCast(Errcase.createFileFailed, "创建文件 \"\(path)\" 失败")
                }
            }
        }.flatMapThrowing { fileIndex throws(BscError<Errcase>) in
            try required(throws: Errcase.getFileFailed) {
                try .init(from: fileIndex, parent: path.parent, storage: self)
            }
        }
    }
    
    /// 获取指定路径的文件对象。
    ///
    /// - Parameter path: 文件路径。
    /// - Returns: 文件对象。
    func getFile(at path: StoragePath) -> EventLoopRes<File, Errcase> {
        get(at: path)
            .errCast(Errcase.getFileFailed)
            .flatMapThrowing
        { fileIndex throws(BscError<Errcase>) in
            try required(throws: Errcase.getFileFailed) {
                try .init(from: fileIndex, parent: path.parent, storage: self)
            }
        }
    }
}

// MARK: - 内部实现

extension FileStorage {
    
    /// 获取指定路径的文件索引。
    func get(at path: StoragePath) -> EventLoopRes<FileIndex, FindEntryErrcase> {
        findEntry(at: path) {
            guard let fileIndex = $0.index else {
                return self.eventLoop.makeFailedResult(FindEntryErrcase.entryNotExist)
            }
            return self.eventLoop.makeSucceededResult(fileIndex)
        }
    }
    
    typealias ActionContext = (index: FileIndex?, path: StoragePath, parent: FileIndex)
    
    /// 用于路径查找过程中可能出现的错误类型。
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
    ) -> EventLoopRes<FileIndex, FindEntryErrcase> {
        
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
    
    /// 用于数据库读写过程中可能出现的错误类型。
    public enum DatabaseErrcase: String, ErrList {
        case saveFailed = "数据库保存动作失败"
        case queryFailed = "数据库查询失败"
        case fileCreateFailed = "文件创建失败"
        case fetchIdFailed = "获取实例 ID 失败"
    }
    
    /// 获取指定目录下的子文件或子目录。
    func getChild(
        at index: FileIndex,
        name: String
    ) -> EventLoopRes<FileIndex?, DatabaseErrcase> {
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
    
    /// 获取指定路径的父目录索引，可递归创建。
    func getParent(
        at path: StoragePath,
        withIntermediateDirectories createIfNeed: Bool = false
    ) -> EventLoopRes<FileIndex, FindEntryErrcase> {
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
                        return self.eventLoop.makeFailedResult(FindEntryErrcase.directoryExisted, path.parent.string)
                    }
                    return self.eventLoop.makeSucceededResult(fileIndex)
                } else {
                    // 该级目录不存在
                    guard createIfNeed else {
                        // 若用户指定 createIfNeed 为 false，直接抛出错误
                        return self.eventLoop.makeFailedResult(FindEntryErrcase.directoryNotExist, path.parent.string)
                    }
                    // 为该级创建新目录，因为用户指定了 createIfNeed
                    return self.newDirIndex(parent: parent, path: path).errCast(FindEntryErrcase.databaseFailed, path.string)
                }
            }
        }
    }
    
    /// 创建新的目录索引项。
    @Sendable func newDirIndex(
        parent: FileIndex?,
        path: StoragePath
    ) -> EventLoopRes<FileIndex, DatabaseErrcase> {
        let new = FileIndex()
        new.id = .init()
        new.$parent.id = try! parent?.getId()
        new.type = .directory
        new.mimeType = nil
        new.name = path.last!
        return new.save(on: self.indexDatabase).map { new }.withError(DatabaseErrcase.saveFailed)
    }
    
    /// 创建新的文件索引项，并写入实际文件。
    @Sendable func newFileIndex(
        parent: FileIndex?,
        path: StoragePath,
        chunkSize: Int64
    ) -> EventLoopRes<FileIndex, DatabaseErrcase> {
        let file = FileIndex()
        file.id = .init()
        file.name = path.last!
        if let extensionName = file.name.fileExtension {
            file.mimeType = .init(fileExtension: extensionName)
        } else {
            file.mimeType = .unknow
        }
        file.type = .file
        file.size = 0
        file.$parent.id = parent?.id
        
        let fileCrypto = FileCrypto()
        fileCrypto.id = try! file.requireID()
        fileCrypto.salt = saltGenerate()
        fileCrypto.encryptedSize = 0
        fileCrypto.lastTag = 0
        fileCrypto.chunkSize = chunkSize
        fileCrypto.sharedData = sharedDataGenerate(file: file)
        fileCrypto.storageKey = storageKeyGenerate(file: file)
        
        return db.eventLoop.submitResult { () throws(BscError<DatabaseErrcase>) in
            let permissionAttributes = try required(throws: DatabaseErrcase.fileCreateFailed, "权限信息无效") {
                try self.filePermission?.attributes.get()
            } ?? [:]
            
            guard
                FileManager.default.createFile(
                    atPath: "\(self.storagePath)/\(fileCrypto.storageKey).\(self.fileExtension)",
                    contents: nil,
                    attributes: permissionAttributes
                )
            else {
                throw DatabaseErrcase.fileCreateFailed.d("未知原因")
            }
        }.flatMap {
            self.db.transaction { db in
                file.save(on: db).flatMap {
                    fileCrypto.save(on: db).map { file }
                }
            }.withError(DatabaseErrcase.saveFailed)
        }
        
        func saltGenerate() -> Base64String {
            var salt = Data()
            let timestamp = UInt64(Date().timeIntervalSince1970)
            // 时间戳
            salt += timestamp.data
            // 加一段 16 字节的随机数
            salt += Crypto.randomDataGenerate(length: 16)
            return .new(data: salt)
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
            key += timestamp.data
            // 加一段 32 字节的随机数
            key += Crypto.randomDataGenerate(length: 32)
            let hash = SHA256.hash(data: key)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        }
    }
}
