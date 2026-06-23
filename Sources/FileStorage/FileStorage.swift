import FluentPostgresDriver
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
/// 初始化一个 `FileStorage` 实例:
/// ``` swift
/// import NIO
/// import Cryptos
/// import Foundation
/// import FileStorage
/// import FluentPostgresDriver
///
/// // 准备线程，该实例将运行在其上
/// let pool = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
/// let eventLoop = pool.next()
///
/// // 准备主目录，该文件系统将会将所有的加密文件存于该位置
/// // 支持相对路径，以及路径修饰符
/// let storageDir: String = "~/data"
///
/// // 准备 PostgreSQL 服务连接参数
/// // 请修改这些参数以符合你的情况
/// let postgresConfigure = SQLPostgresConfiguration(
///     hostname: "localhost",
///     port: 5432,
///     username: "postgres",
///     password: "password",
///     database: "postgres",
///     tls: .disable
/// )
///
/// // 准备一个密钥，作为该文件系统的加密主密钥
/// // 该密钥不会被用于直接加密，而只会使用其派生版本
/// let keyStr = "Mzn/h5zDnIdi4C3yHaRMG62DhC9qYt8q4SfOCV338hY="
/// let key = Crypto.Symm.Key(data: Data(base64Encoded: keyStr)!)
///
/// // 设置加密文件的 Unix 权限，这一步可忽略，传为 nil 则表示使用默认设置
/// // 另见 FileStorage.UnixPermission 的详细类型介绍
/// let permission = FileStorage.UnixPermission(rwx: [.groupRead, .ownerReadWriteExecute])
///
/// // 初始化 FileStorage
/// let storage = try await FileStorage.new(
///     eventLoop: eventLoop,
///     storagePath: storageDir,
///     dbConfigure: postgresConfigure,
///     masterKey: key,
///     logger: .init(label: "FileStorage-Testing"),
///     filePermission: permission,
///     debuging: .init(tdeEncrypt: false)  // 仅仅用在调试阶段，生产环境应当移除
/// ).get()
/// ```
///
/// 得到该实例后，便可创建目录:
/// ``` swift
/// // 提供一个路径，目录将会创建在该路径下
/// // 注意，该路径为虚拟文件系统的路径，详情请见 StoragePath 类型
/// let path: StoragePath = "testing/example"
///
/// // 在指定的路径下创建目录
/// // 你可以指定 withIntermediateDirectories: 参数为 true 以自动创建中间目录
/// // 否则，若中间目录不存在，将会抛出错误
/// let dir = try await storage.createDirectory(at: path)
///
/// print(dir.name)                 // <-- print: example
/// print(dir.path)                 // <-- print: testing/example
/// print(dir.isExist())            // <-- print: true
/// ```
///
/// 创建文件:
/// ``` swift
/// // 提供一个路径，文件将会创建在该路径下
/// // 注意，该路径为虚拟文件系统的路径，详情请见 StoragePath 类型
/// let path: StoragePath = "testing/example.txt"
///
/// // 在指定的路径下创建文件
/// // 你可以指定 withIntermediateDirectories: 参数为 true 以自动创建中间目录
/// // 否则，若中间目录不存在，将会抛出错误
/// let file = try await storage.createFile(at: path)
///
/// print(file.name)                // <-- print: example.txt
/// print(file.mimeType)            // <-- print: MimeType.plain "text/plain"
/// print(file.path)                // <-- print: testing/example.txt
/// print(file.size)                // <-- print: 0
/// print(file.isExist())           // <-- print: true
/// ```
///
/// 取得目录:
/// ``` swift
/// // 提供一个路径，获取该路径下的目录
/// let path: StoragePath = "testing/example"
///
/// // 获取目录
/// let dir = try await storage.getDirectory(at: path)
///
/// print(dir.name)                 // <-- print: example
/// print(dir.path)                 // <-- print: testing/example
/// print(dir.isExist())            // <-- print: true
/// ```
///
/// 取得文件:
/// ``` swift
/// // 提供一个路径，获取该路径下的文件
/// let path: StoragePath = "testing/example.txt"
///
/// // 获取文件
/// let file = try await storage.getFile(at: path)
///
/// print(file.name)                // <-- print: example.txt
/// print(file.mimeType)            // <-- print: MimeType.plain "text/plain"
/// print(file.path)                // <-- print: testing/example.txt
/// print(file.size)                // <-- print: 0
/// print(file.isExist())           // <-- print: true
/// ```
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
    @frozen
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
    @inlinable public var rootDir: Directory { self.__rootDir! }
    /// 当前文件系统使用的权限设置（如果有）。
    public let filePermission: UnixPermission?
    /// 加密文件所使用的后缀名，默认为 `FileStorage.DefaultCryptoFileExtension`
    public let fileExtension: String
    
    @usableFromInline let storagePath: String
    @usableFromInline let indexDatabase: PGDatabase
    @usableFromInline let masterKey: Crypto.Symm.Key
    @usableFromInline let rootDirIndex: FileIndex
    @usableFromInline var db: PGDatabase { indexDatabase }
    @usableFromInline private(set) var __rootDir: Directory?
    @usableFromInline let dbs: Databases
    
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
    @inlinable
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
        await .async { () throws(Errcase.ErrType) in
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

    @usableFromInline
    init(
        eventLoop: EventLoop,
        storagePath: String,
        dbConfigure: SQLPostgresConfiguration,
        masterKey: Crypto.Symm.Key,
        logger: Logger,
        fileExtension: String,
        filePermission: UnixPermission?,
        debuging: Debuging? = nil
    ) async throws(Errcase.ErrType) {
        let storagePath = FileSystemTools.resolvePath(append: storagePath)
        
        self.eventLoop = eventLoop
        self.storagePath = storagePath
        self.masterKey = masterKey
        self.logger = logger
        self.filePermission = filePermission
        self.fileExtension = fileExtension
        let initLogger = logger.derive(subId: "sysinit", metadata: ["eventLoop": .id(eventLoop)])
        
        initLogger.info("正在初始化加密文件存储系统", metadata: [
            "path": .string(storagePath),
            "db_config": .summaryData(dbConfigure),
            "file_extension": .string(fileExtension),
            "file_permission": .summaryData(filePermission)
        ])
        initLogger.debug("初始化参数", metadata: [
            "db_config": .data(dbConfigure),
            "file_permission": .data(filePermission)
        ])
        
        initLogger.info("正在准备文件存储区")
        
        let fileAttributes = try initLogger.required(throws: Errcase.fileSystemInitFailed, "文件存储区属性读取失败", metadata: ["path": .string(storagePath)], category: .internal) {
            try FileManager.default.attributesOfItem(atPath: storagePath)
        }
        
        let permissionAttributes = try initLogger.required(throws: Errcase.fileSystemInitFailed, "提供的文件权限值无效", metadata: ["file_permission": .data(filePermission)], category: .external()) {
            try filePermission?.attributes.get()
        } ?? [:]
        
        try initLogger.required(throws: Errcase.fileSystemInitFailed, "修改主存储目录权限失败", metadata: ["path": .string(storagePath), "file_permission": .data(filePermission)], category: .internal) {
            try FileManager.default.setAttributes(permissionAttributes, ofItemAtPath: storagePath)
        }
        
        guard
            let createDate = fileAttributes[.creationDate] as? Date,
            let modifyDate = fileAttributes[.modificationDate]  as? Date,
            let type = fileAttributes[.type] as? FileAttributeType,
            type == .typeDirectory
        else {
            throw initLogger.errThrow(Errcase.fileSystemInitFailed.d("文件存储区属性获取失败", category: .internal).metadata(["path": .string(storagePath)]))
        }
        
        initLogger.info("文件存储区准备完成")
        initLogger.info("正在准备数据库")
        
        self.dbs = Databases(threadPool: .singleton, on: eventLoop)
        
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
            initLogger.info("数据库准备成功")
        } catch {
            await self.dbs.shutdownAsync()
            try? await eventLoop.shutdownGracefully()
            throw Errcase.databaseInitFailed.d("数据库迁移失败", category: .internal).subErr(error)
        }
        
        guard let db = self.dbs.database(logger: logger, on: eventLoop) else {
            throw Errcase.databaseInitFailed.d("数据库获取失败", category: .internal)
        }
        
        guard let db = db as? PGDatabase else {
            throw Errcase.databaseInitFailed.d("数据库并非 PostgreSQL 数据库", category: .external(suggestions: ["请检查数据库服务类型，目前仅支持 PostgreSQL 数据库"]))
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
        
        initLogger.info("加密文件存储系统初始化完成")
    }
    
    @inlinable
    func getOperationLogger() -> Logger {
        self.logger.derive(metadata: ["op-id": .stringConvertible(UUID())])
    }
}
