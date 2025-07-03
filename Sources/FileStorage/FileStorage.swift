import FluentPostgresDriver
import ErrorHandle
import Cryptos
import Foundation
import NIOAdvanced

/// 提供文件加密存储，支持流式解密 Backpressure 读取以及加密写入。
///
/// 该系统使用 PostgreSQL 存取文件索引以及加密信息，使用分块算法使得许多数据操作无需真正干预磁盘，
/// 而只需要修改数据库索引，显著提高效率。
/// 且同时使用密钥派生的方式对每个文件分别加密，因此不在数据库中存储机密信息也可做到安全加密。
///
/// 数据库以及文件操作实现了原子性操作，保证动作成原子完成即便遇到不可抗事件
///
/// 使用时需要指定用于加密的加密密钥，数据库连接参数，存储目录，权限设置等等参数。
/// 一旦初始化完成即可进行各种文件系统操作
///
/// 初始化操作，详见 `FileStorage.new(eventLoop: storagePath: dbConfig: masterkey: ...)` 工厂函数
public final class FileStorage: @unchecked Sendable {
    
    /// 默认的加密文件扩展名。
    ///
    /// 具体另见 `FileStorage.new(eventLoop: storagePath: dbConfig: masterkey: ...)` 工厂函数
    public static let DefaultCryptoFileExtension = "wooclassified"
    
    /// 控制调试功能的配置结构体，为 FileStorage 运行指定调试参数
    ///
    /// 只有调试该文件存储系统时使用，可以设定数据库是否进行 TDE 加密。
    /// 具体另见 `FileStorage.new(eventLoop: storagePath: dbConfig: masterkey: ...)` 工厂函数
    ///
    /// - Warning: 仅在测试和开发环境中适用，否则将会面临数据库明文存储的风险
    public struct Debuging: Sendable {
        /// 是否启用 PostgreSQL tde 加密功能
        ///
        /// 一般的数据库中并未配置 tde 加密扩展，这通常需要修改数据库服务器配置文件
        /// 因此，为了方便测试，可暂时取消其加密机制
        public let tdeEncrypt: Bool
        
        /// 初始化该调试参数
        public init(tdeEncrypt: Bool = true) {
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
    public var rootDir: Directory { self.__rootDir! }
    /// 当前文件系统使用的权限设置（如果有）。
    public let filePermission: UnixPermission?
    /// 加密文件所使用的后缀名，默认为 `FileStorage.DefaultCryptoFileExtension`
    public let fileExtension: String
    
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
    ///   - fileExtension: 加密文件的后缀名，默认为 `FileStorage.DefaultCryptoFileExtension`
    ///   - filePermission: 可选的文件权限配置。
    ///   - debuging: 可选的调试参数。
    ///
    /// - Returns: 包含初始化完成的 FileStorage 实例或错误。
    ///
    /// - Warning: 该初始化函数并不会自主根据 `storagePath` 创建文件夹，请保证该文件夹存在于
    /// 文件系统中，且拥有足够的权限。若无法打开该文件夹，将抛出相关错误
    public static func new(
        eventLoop: EventLoop,
        storagePath: String,
        dbConfigure: SQLPostgresConfiguration,
        masterKey: Crypto.Symm.Key,
        logger: Logger,
        fileExtension: String = DefaultCryptoFileExtension,
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
                fileExtension: fileExtension,
                filePermission: filePermission,
                debuging: debuging
            )
        }
    }

    init(
        eventLoop: EventLoop,
        storagePath: String,
        dbConfigure: SQLPostgresConfiguration,
        masterKey: Crypto.Symm.Key,
        logger: Logger,
        fileExtension: String,
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
        self.fileExtension = fileExtension
        
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
