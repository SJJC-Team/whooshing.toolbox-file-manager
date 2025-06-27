import Fluent
import FluentSQL
import FluentPostgresDriver
import ErrorHandle
import Cryptos
import Foundation

public final class FileStorage: @unchecked Sendable {
    
    public static let CryptoFileExtension = "wooclassified"
    
    public struct Debuging: Sendable {
        let tdeEncrypt: Bool
        init(tdeEncrypt: Bool = true) {
            self.tdeEncrypt = tdeEncrypt
        }
    }
    
    public let eventLoop: EventLoop
    public let logger: Logger
    public let chunkSize: Int64
    
    public typealias PGDatabase = Database & PostgresDatabase
    
    let storagePath: String
    let walPath: String
    let indexDatabase: PGDatabase
    let masterKey: Crypto.Symm.Key
    let rootInfo: RootInfo
    var db: PGDatabase { indexDatabase }
    
    public lazy private(set) var rootDir: Directory = {
        try! .init(from: rootDirIndex, parent: nil, storage: self)
    }()
    
    lazy private(set) var rootDirIndex: FileIndex = {
        let index = FileIndex(isRoot: true)
        index.name = ""
        index.id = nil
        index.type = .directory
        index.parent = nil
        index.size = nil
        index.mimeType = nil
        return index
    }()
    
    private let dbs: Databases
    
    public static func new(
        eventLoop: EventLoop,
        storagePath: String,
        indexDatabaseConfigure: SQLPostgresConfiguration,
        chunkSize: Int64,
        masterKey: Crypto.Symm.Key,
        logger: Logger,
        debuging: Debuging? = nil
    ) async -> Res<FileStorage, Errcase> {
        await .async {
            try await FileStorage(
                eventLoop: eventLoop,
                storagePath: storagePath,
                indexDatabaseConfigure: indexDatabaseConfigure,
                chunkSize: chunkSize,
                masterKey: masterKey,
                logger: logger
            )
        }
    }
    
    init(
        eventLoop: EventLoop,
        storagePath: String,
        indexDatabaseConfigure: SQLPostgresConfiguration,
        chunkSize: Int64,
        masterKey: Crypto.Symm.Key,
        logger: Logger,
        debuging: Debuging? = nil
    ) async throws(BscError<Errcase>) {
        
        let fileAttributes = try required(throws: Errcase.fileSystemInitFailed, "文件信息参数读取失败") {
            try FileManager.default.attributesOfItem(atPath: storagePath)
        }
        guard
            let createDate = fileAttributes[.creationDate] as? Date,
            let modifyDate = fileAttributes[.modificationDate]  as? Date,
            let type = fileAttributes[.type] as? FileAttributeType,
            type == .typeDirectory
        else {
            throw Errcase.fileSystemInitFailed.d("根目录参数读取失败")
        }
        
        let walPath = "\(storagePath)/wal"
        try required(throws: Errcase.fileSystemInitFailed, "wal 目录创建失败") {
            try FileManager.default.createDirectory(at: .init(filePath: walPath), withIntermediateDirectories: true)
        }
        
        self.rootInfo = .init(createDate: createDate, modifyDate: modifyDate)
        self.eventLoop = eventLoop
        self.storagePath = storagePath
        self.walPath = walPath
        self.masterKey = masterKey
        self.chunkSize = chunkSize
        self.logger = logger
        self.dbs = Databases(threadPool: .singleton, on: eventLoop)
        
        do {
            self.dbs.use(.postgres(configuration: indexDatabaseConfigure), as: .psql)
            
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
        
        guard let db = db as? Database & PostgresDatabase else {
            throw Errcase.databaseInitFailed.d("数据库并非 PostgreSQL 数据库")
        }

        self.indexDatabase = db
    }
}

extension FileStorage {
    struct RootInfo: Sendable {
        let createDate: Date
        let modifyDate: Date
    }
}

extension PostgresDatabase where Self: Database {
    func trans<T>(_ closure: @escaping @Sendable (Self) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        self.transaction { db in
            closure(db as! Self)
        }
    }
    
    func trans<T: Sendable>(_ closure: @escaping @Sendable (Self) async throws -> T) async throws -> T {
        try await self.transaction { db in
            try await closure(db as! Self)
        }
    }
}
