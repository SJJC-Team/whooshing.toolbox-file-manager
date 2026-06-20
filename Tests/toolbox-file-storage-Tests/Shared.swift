import Testing
import NIOPosix
import Cryptos
import NIOFileSystem
import Foundation
@testable import FileStorage

enum TestingData {
    case string(String)
    case random(Int)
}

struct TestingShared {

    enum TestStage {
        case entryBasics
        case directory
        case fileAppending
        case fileInsertion
        case fileRemoving
        case fileReplacemeng
    }
     
    static let dbHost = ProcessInfo.processInfo.environment["GITHUB_PG_TESTING_HOST"] ?? "localhost"
    static let dbPort = 5432
    static let dbListening = try! isPortOpen(host: dbHost, port: dbPort)
    static let permission = FileStorage.UnixPermission(rwx: [.groupRead, .ownerReadWriteExecute])
    
    @MainActor static var fileStorage: FileStorage? = nil
    @MainActor static var testStage: TestStage = .entryBasics
    @MainActor static let loggingSystem: Void = {
        LoggingFactory(strategies: [.init(label: "Console", level: .trace)]).bootstrap()
    }()
    
    @MainActor
    static func getFileStorage() async throws -> FileStorage {
        if let storage = fileStorage {
            return storage
        }
        
        _ = loggingSystem
        
        let testingStorageDir = FileSystemTools.resolvePath(append: "~/file_storage_testing")
        
        let keyStr = "Mzn/h5zDnIdi4C3yHaRMG62DhC9qYt8q4SfOCV338hY="
        let key = Crypto.Symm.Key(data: Data(base64Encoded: keyStr)!)

        try await Task.detached {
            let dir: DirectoryFileHandle?
            do {
                dir = try await FileSystem.shared.openDirectory(atPath: .init(stringLiteral: testingStorageDir), options: .init())
            } catch {
                dir = nil
                try await FileSystem.shared.createDirectory(at: .init(stringLiteral: testingStorageDir), withIntermediateDirectories: true)
            }
            try await dir?.close()
        }.value
        
        var logger = Logger(label: "FileStorage-Testing")
        logger.logLevel = .debug
        
        let pool = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let eventLoop = pool.next()
        let s = try await FileStorage.new(
            eventLoop: eventLoop,
            storagePath: testingStorageDir,
            dbConfigure: .init(hostname: dbHost, port: dbPort, username: "postgres", password: "password", database: "postgres", tls: .disable),
            masterKey: key,
            logger: logger,
            filePermission: permission,
            debuging: .init(tdeEncrypt: false)
        ).get()
        self.fileStorage = s
        return s
    }
}

func randomBuffer(size: Int) -> ByteBuffer {
    var buffer = ByteBufferAllocator().buffer(capacity: size)
    var rng = SystemRandomNumberGenerator()
    let randomBytes = (0..<size).map { _ in UInt8.random(in: 0...255, using: &rng) }
    buffer.writeBytes(randomBytes)
    return buffer
}

func randomData(size: Int) -> Data {
    var buffer = ByteBufferAllocator().buffer(capacity: size)
    var rng = SystemRandomNumberGenerator()
    let randomBytes = (0..<size).map { _ in UInt8.random(in: 0...255, using: &rng) }
    buffer.writeBytes(randomBytes)
    return .init(buffer: buffer)
}

func isPortOpen(host: String, port: Int, timeout: TimeAmount = .seconds(3)) throws -> Bool {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
        try? group.syncShutdownGracefully()
    }

    let promise = group.next().makePromise(of: Bool.self)

    let bootstrap = ClientBootstrap(group: group)
        .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

    let futureChannel = bootstrap.connect(host: host, port: port)

    group.next().scheduleTask(in: timeout) {
        promise.fail(ChannelError.connectTimeout(timeout))
    }

    futureChannel.whenSuccess { channel in
        channel.close(mode: .all, promise: nil)
        promise.succeed(true)
    }

    futureChannel.whenFailure { error in
        promise.succeed(false)
    }

    return try promise.futureResult.wait()
}
