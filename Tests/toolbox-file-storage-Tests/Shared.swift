import Testing
import ErrorHandle
import NIOCore
import NIOPosix
import NIO
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
    
    @MainActor static var fileStorage: FileStorage? = nil
    @MainActor static var testStage: TestStage = .entryBasics
    
    @MainActor
    static func getFileStorage() async throws -> FileStorage {
        
        let testingStorageDir = FileStorage.resolvePath(append: "~/file_storage_testing")
        
        let KeyStr = "Mzn/h5zDnIdi4C3yHaRMG62DhC9qYt8q4SfOCV338hY="
        let Key = Crypto.Symm.Key(data: Data(base64Encoded: KeyStr)!)

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
        
        guard let storage = fileStorage else {
            let pool = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            let eventLoop = pool.next()
            let s = try await FileStorage.new(
                eventLoop: eventLoop,
                storagePath: testingStorageDir,
                indexDatabaseConfigure: .init(hostname: dbHost, port: dbPort, username: "postgres", password: "password", database: "postgres", tls: .disable),
                masterKey: Key,
                logger: .init(label: "FileStorage-Testing"),
                debuging: .init(tdeEncrypt: false)
            ).get()
            self.fileStorage = s
            return s
        }
        return storage
    }
}

func randomData(size: Int) -> ByteBuffer {
    var buffer = ByteBufferAllocator().buffer(capacity: size)
    var rng = SystemRandomNumberGenerator()
    let randomBytes = (0..<size).map { _ in UInt8.random(in: 0...255, using: &rng) }
    buffer.writeBytes(randomBytes)
    return buffer
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