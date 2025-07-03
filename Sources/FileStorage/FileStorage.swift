import Fluent
import FluentSQL
import FluentPostgresDriver
import ErrorHandle
import Cryptos
import Foundation
import NIOAdvanced

public final class FileStorage: @unchecked Sendable {
    
    public static let CryptoFileExtension = "wooclassified"
    
    public struct Debuging: Sendable {
        let tdeEncrypt: Bool
        init(tdeEncrypt: Bool = true) {
            self.tdeEncrypt = tdeEncrypt
        }
    }
    
    public typealias PGDatabase = Database & PostgresDatabase & SQLDatabase
    
    public let eventLoop: EventLoop
    public let logger: Logger
    public var rootDir: Directory {
        self.__rootDir!
    }
    
    let storagePath: String
    let indexDatabase: PGDatabase
    let masterKey: Crypto.Symm.Key
    let rootDirIndex: FileIndex
    var db: PGDatabase { indexDatabase }
    private var __rootDir: Directory?
    private let dbs: Databases
    
    public static func new(
        eventLoop: EventLoop,
        storagePath: String,
        indexDatabaseConfigure: SQLPostgresConfiguration,
        masterKey: Crypto.Symm.Key,
        logger: Logger,
        debuging: Debuging? = nil
    ) async -> Res<FileStorage, Errcase> {
        await .async {
            try await FileStorage(
                eventLoop: eventLoop,
                storagePath: storagePath,
                indexDatabaseConfigure: indexDatabaseConfigure,
                masterKey: masterKey,
                logger: logger,
                debuging: debuging
            )
        }
    }
    
    init(
        eventLoop: EventLoop,
        storagePath: String,
        indexDatabaseConfigure: SQLPostgresConfiguration,
        masterKey: Crypto.Symm.Key,
        logger: Logger,
        debuging: Debuging? = nil
    ) async throws(BscError<Errcase>) {
        
        let storagePath = Self.resolvePath(append: storagePath)
        
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
        
        self.eventLoop = eventLoop
        self.storagePath = storagePath
        self.masterKey = masterKey
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
    
    /// 拼接路径的实用函数
    static func resolvePath(basePath: String = FileManager.default.currentDirectoryPath, append pathToAppend: String) -> String {
        let base = (basePath as NSString).expandingTildeInPath
        let baseURL = URL(fileURLWithPath: base).deletingLastPathComponent()
        let appended = (pathToAppend as NSString).expandingTildeInPath
        let finalURL: URL
        if appended.hasPrefix("/") {
            finalURL = URL(fileURLWithPath: appended)
        } else {
            finalURL = baseURL.appendingPathComponent(appended)
        }
        return finalURL.standardized.path
    }
}

extension Database {
    func trans<T, G>(_ closure: @escaping @Sendable (Self) -> EventLoopResult<T, G>) -> EventLoopResult<T, G> {
        self.trans { db in
            closure(db).wrapped
        }.withError()
    }
    
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
