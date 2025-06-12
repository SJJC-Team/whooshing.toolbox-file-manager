import Fluent
import FluentPostgresDriver
import ErrorHandle

public struct FileStorage: Sendable {
    
    public struct Debuging: Sendable {
        let tdeEncrypt: Bool
        init(tdeEncrypt: Bool = true) {
            self.tdeEncrypt = tdeEncrypt
        }
    }
    
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.file.storage.err" }
        case databaseInitFailed = "数据库连接失败"
        case unknow = "未知错误"
    }
    
    let eventLoop: EventLoop
    let storagePath: String
    let indexDatabase: Database
    let logger: Logger
    
    var db: Database { indexDatabase }
    private let dbs: Databases
    
    public init(
        eventLoop: EventLoop,
        storagePath: String,
        indexDatabaseConfigure: SQLPostgresConfiguration,
        logger: Logger,
        debuging: Debuging? = nil
    ) async throws {
        self.eventLoop = eventLoop
        self.storagePath = storagePath
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
            
            guard let db = self.dbs.database(logger: logger, on: eventLoop) else {
                throw Err.databaseInitFailed.d(16001)
            }
            self.indexDatabase = db
        } catch {
            await self.dbs.shutdownAsync()
            try? await eventLoop.shutdownGracefully()
            throw error
        }
    }
}
