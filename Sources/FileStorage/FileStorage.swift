import Fluent
import FluentPostgresDriver
import ErrorHandle

public struct FileStorage: Sendable {
    
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.file.storage.err" }
        case databaseInitFailed = "数据库连接失败"
        case unknow = "未知错误"
    }
    
    private let eventLoop: EventLoop
    private let storagePath: String
    private let indexDatabase: Database
    private let dbs: Databases
    private let logger: Logger
    
    public init(
        eventLoop: EventLoop,
        storagePath: String,
        indexDatabaseConfigure: SQLPostgresConfiguration,
        logger: Logger
    ) throws {
        self.eventLoop = eventLoop
        self.storagePath = storagePath
        self.logger = logger
        self.dbs = Databases(threadPool: .singleton, on: eventLoop)
        do {
            guard let db = self.dbs.database(logger: logger, on: eventLoop) else {
                throw Err.databaseInitFailed.d(16001)
            }
            self.indexDatabase = db
        } catch {
            self.dbs.shutdown()
            try? eventLoop.syncShutdownGracefully()
            throw error
        }
    }
}
