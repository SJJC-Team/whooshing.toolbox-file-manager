import Fluent
import FluentSQL
import FluentPostgresDriver
import ErrorHandle
import Cryptos
import Foundation
import NIOAdvanced
import NIOFileSystem

/// 管理加密文件存储的核心类，支持使用 PostgreSQL 作为索引数据库。
/// 提供事务性索引记录、透明加密（TDE）控制，并允许设置存储权限。
public final class FileStorage: @unchecked Sendable {
    
    /// 默认的加密文件扩展名。
    public static let CryptoFileExtension = "wooclassified"
    
    /// 控制调试功能的配置结构体。
    /// - 参数 tdeEncrypt: 是否启用透明加密。
    public struct Debuging: Sendable {
        let tdeEncrypt: Bool
        init(tdeEncrypt: Bool = true) {
            self.tdeEncrypt = tdeEncrypt
        }
    }
    
    /// Fluent 中 PostgreSQL 数据库的统一别名类型。
    public typealias PGDatabase = Database & PostgresDatabase & SQLDatabase
    
    /// 当前使用的事件循环。
    public let eventLoop: EventLoop
    /// 日志记录器。
    public let logger: Logger
    /// 文件存储的根目录。
    public var rootDir: Directory {
        self.__rootDir!
    }
    /// 当前文件系统使用的权限设置（如果有）。
    public let filePermission: UnixPermission?
    
    let storagePath: String
    let indexDatabase: PGDatabase
    let masterKey: Crypto.Symm.Key
    let rootDirIndex: FileIndex
    var db: PGDatabase { indexDatabase }
    private var __rootDir: Directory?
    private let dbs: Databases
    
    /// 创建并初始化一个新的 FileStorage 实例（异步）。
    ///
    /// - Parameters:
    ///   - eventLoop: 用于异步操作的事件循环。
    ///   - storagePath: 文件存储的根目录路径。
    ///   - dbConfigure: PostgreSQL 数据库配置。
    ///   - masterKey: 主加密密钥。
    ///   - logger: 日志记录器。
    ///   - filePermission: 可选的文件权限配置。
    ///   - debuging: 可选的调试参数。
    ///
    /// - Returns: 包含初始化完成的 FileStorage 实例或错误。
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
    
    /// 初始化 FileStorage 实例并执行数据库配置与目录权限设置。
    ///
    /// - Parameters:
    ///   - eventLoop: 当前使用的事件循环。
    ///   - storagePath: 文件存储路径。
    ///   - dbConfigure: PostgreSQL 数据库配置。
    ///   - masterKey: 主加密密钥。
    ///   - logger: 日志输出器。
    ///   - filePermission: 可选的 POSIX 权限设置。
    ///   - debuging: 调试配置。
    ///
    /// - Throws: 如果初始化失败，将抛出相关错误。
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
    /// 使用自定义错误类型封装的事务执行器。
    func trans<T, G>(_ closure: @escaping @Sendable (Self) -> EventLoopResult<T, G>) -> EventLoopResult<T, G> {
        self.trans { db in
            closure(db).wrapped
        }.withError()
    }
    
    /// 使用 Fluent 的事务封装异步回调。
    func trans<T>(_ closure: @escaping @Sendable (Self) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        self.transaction { db in
            closure(db as! Self)
        }
    }
    
    /// 在 async/await 环境中执行数据库事务。
    func trans<T: Sendable>(_ closure: @escaping @Sendable (Self) async throws -> T) async throws -> T {
        try await self.transaction { db in
            try await closure(db as! Self)
        }
    }
}
