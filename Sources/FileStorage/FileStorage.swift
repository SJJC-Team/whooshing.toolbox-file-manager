import Fluent
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
    
    let storagePath: String
    let indexDatabase: Database
    let masterKey: Crypto.Symm.Key
    let rootInfo: RootInfo
    
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
    
    var db: Database { indexDatabase }
    private let dbs: Databases
    
    public init(
        eventLoop: EventLoop,
        storagePath: String,
        indexDatabaseConfigure: SQLPostgresConfiguration,
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
        
        self.rootInfo = .init(createDate: createDate, modifyDate: modifyDate)
        self.eventLoop = eventLoop
        self.storagePath = storagePath
        self.masterKey = masterKey
        self.logger = logger
        self.dbs = Databases(threadPool: .singleton, on: eventLoop)
        
        do {
            self.dbs.use(.postgres(configuration: indexDatabaseConfigure), as: .psql)
            
            let migs = Migrations()
            migs.add(FileCrypto.MIG(tdeEncrypt: debuging?.tdeEncrypt ?? true))
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
            throw Errcase.databaseInitFailed.d()
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
