import Fluent
import FluentSQL
import FluentPostgresDriver
import ErrorHandle
import Cryptos
import Foundation
import NIOAdvanced
import NIOFileSystem

/// 一个用于管理加密文件存储的类，使用 PostgreSQL 数据库存储索引。
/// 支持事务性索引更新与可选的透明数据加密（TDE）。
public final class FileStorage: @unchecked Sendable {
    
    /// 用于加密文件的默认扩展名。
    public static let CryptoFileExtension = "wooclassified"
    
    /// 用于控制调试行为的配置结构体。
    /// - 参数 tdeEncrypt: 是否启用透明数据加密（TDE）。
    public struct Debuging: Sendable {
        let tdeEncrypt: Bool
        init(tdeEncrypt: Bool = true) {
            self.tdeEncrypt = tdeEncrypt
        }
    }
    
    /// 表示一个既符合 Fluent 的 Database 协议，也支持 PostgreSQL 和 SQL 的数据库类型。
    public typealias PGDatabase = Database & PostgresDatabase & SQLDatabase
    
    /// 当前使用的事件循环。
    public let eventLoop: EventLoop
    /// 用于记录日志的 Logger。
    public let logger: Logger
    /// 文件存储的根目录，实际来源于 `rootDirIndex`。
    public var rootDir: Directory {
        self.__rootDir!
    }
    public let filePermission: UnixPermission?
    
    let storagePath: String
    let indexDatabase: PGDatabase
    let masterKey: Crypto.Symm.Key
    let rootDirIndex: FileIndex
    var db: PGDatabase { indexDatabase }
    private var __rootDir: Directory?
    private let dbs: Databases
    
    /// 异步创建一个 FileStorage 实例。
    /// - 参数 eventLoop: 用于异步操作的事件循环。
    /// - 参数 storagePath: 文件存储的根目录路径。
    /// - 参数 indexDatabaseConfigure: 用于初始化 PostgreSQL 数据库的配置。
    /// - 参数 masterKey: 主加密密钥。
    /// - 参数 logger: 日志记录器。
    /// - 参数 debuging: 调试配置。
    /// - 返回: 初始化成功的 FileStorage 或错误。
    public static func new(
        eventLoop: EventLoop,
        storagePath: String,
        dbConfigure: SQLPostgresConfiguration,
        masterKey: Crypto.Symm.Key,
        logger: Logger,
        filePermission: UnixPermission? = nil,
        debuging: Debuging? = nil
    ) async -> Res<FileStorage, Errcase> {
        await .async {
            try await FileStorage(
                eventLoop: eventLoop,
                storagePath: storagePath,
                dbConfigure: dbConfigure,
                masterKey: masterKey,
                logger: logger,
                filePermission: filePermission,
                debuging: debuging
            )
        }
    }
    
    /// 初始化 FileStorage 实例并进行数据库迁移与验证。
    /// - 参数 eventLoop: 当前事件循环。
    /// - 参数 storagePath: 存储路径。
    /// - 参数 indexDatabaseConfigure: PostgreSQL 配置。
    /// - 参数 masterKey: 加密用主密钥。
    /// - 参数 logger: 日志记录器。
    /// - 参数 debuging: 调试选项。
    /// - throws: 初始化失败时抛出对应错误。
    init(
        eventLoop: EventLoop,
        storagePath: String,
        dbConfigure: SQLPostgresConfiguration,
        masterKey: Crypto.Symm.Key,
        logger: Logger,
        filePermission: UnixPermission?,
        debuging: Debuging? = nil
    ) async throws(BscError<Errcase>) {
        
        let storagePath = FileSystemTools.resolvePath(append: storagePath)
        
        let fileAttributes = try required(throws: Errcase.fileSystemInitFailed, "文件信息参数读取失败") {
            try FileManager.default.attributesOfItem(atPath: storagePath)
        }
        
        let permissionAttributes = try required(throws: Errcase.fileSystemInitFailed, "提供的权限信息无效") {
            try filePermission?.attributes.get()
        } ?? [:]
        
        try required(throws: Errcase.fileSystemInitFailed, "修改主存储目录权限失败") {
            try FileManager.default.setAttributes(permissionAttributes, ofItemAtPath: storagePath)
        }
        
        guard
            let createDate = fileAttributes[.creationDate] as? Date,
            let modifyDate = fileAttributes[.modificationDate]  as? Date,
            let type = fileAttributes[.type] as? FileAttributeType,
            type == .typeDirectory
        else {
            throw Errcase.fileSystemInitFailed.d("根目录参数读取失败")
        }
        
        self.eventLoop = eventLoop
        self.storagePath = storagePath
        self.masterKey = masterKey
        self.logger = logger
        self.dbs = Databases(threadPool: .singleton, on: eventLoop)
        self.filePermission = filePermission
        
        do {
            self.dbs.use(.postgres(configuration: dbConfigure), as: .psql)
            
            let migs = Migrations()
            migs.add(FileIndex.MIG(tdeEncrypt: debuging?.tdeEncrypt ?? true))
            migs.add(FileCrypto.MIG(tdeEncrypt: debuging?.tdeEncrypt ?? true))
            migs.add(FilePart.MIG(tdeEncrypt: debuging?.tdeEncrypt ?? true))
            let mig = Migrator(
                databases: self.dbs,
                migrations: migs,
                logger: logger,
                on: eventLoop,
                migrationLogLevel: logger.logLevel
            )
            try await mig.setupIfNeeded().get()
            try await mig.prepareBatch().get()
        } catch {
            await self.dbs.shutdownAsync()
            try? await eventLoop.shutdownGracefully()
            throw Errcase.databaseInitFailed.d("数据库迁移失败").subErr(error)
        }
        
        guard let db = self.dbs.database(logger: logger, on: eventLoop) else {
            throw Errcase.databaseInitFailed.d("数据库获取失败")
        }
        
        guard let db = db as? PGDatabase else {
            throw Errcase.databaseInitFailed.d("数据库并非 PostgreSQL 数据库")
        }

        self.indexDatabase = db
        
        let index = FileIndex(isRoot: true)
        index.name = ""
        index.id = nil
        index.type = .directory
        index.$parent.id = nil
        index.size = nil
        index.mimeType = nil
        index.createdAt = createDate
        index.updatedAt = modifyDate
        
        self.rootDirIndex = index
        
        self.__rootDir = try .init(from: rootDirIndex, parent: nil, storage: self)
    }
}

extension Database {
    /// 使用自定义错误类型包装事务操作。
    /// - 参数 closure: 要执行的事务闭包。
    /// - 返回: 使用自定义错误封装的结果。
    func trans<T, G>(_ closure: @escaping @Sendable (Self) -> EventLoopResult<T, G>) -> EventLoopResult<T, G> {
        self.trans { db in
            closure(db).wrapped
        }.withError()
    }
    
    /// 在数据库中以事务方式执行闭包。
    /// - 参数 closure: 执行逻辑。
    /// - 返回: 闭包执行结果的 Future。
    func trans<T>(_ closure: @escaping @Sendable (Self) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        self.transaction { db in
            closure(db as! Self)
        }
    }
    
    /// 使用 async/await 在事务中执行异步闭包。
    /// - 参数 closure: 要执行的异步事务逻辑。
    /// - throws: 闭包执行中的错误。
    /// - 返回: 闭包返回的结果。
    func trans<T: Sendable>(_ closure: @escaping @Sendable (Self) async throws -> T) async throws -> T {
        try await self.transaction { db in
            try await closure(db as! Self)
        }
    }
}
