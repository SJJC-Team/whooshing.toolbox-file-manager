import Testing
import ErrorHandle
import NIOCore
import NIOPosix
import NIO
import Cryptos
import Foundation
@testable import FileStorage

struct TestingShared {

    enum TestStage {
        case entryBasics
        case directory
        case file
    }
    
    static let Key = Crypto.Symm.Key(data: Data(base64Encoded: KeyStr)!)
    static let KeyStr = "Mzn/h5zDnIdi4C3yHaRMG62DhC9qYt8q4SfOCV338hY="
    
    static let chunkSize: Int64 = 65535
    
    @MainActor static var fileStorage: FileStorage? = nil
    
    @MainActor static var testStage: TestStage = .entryBasics
    
    @MainActor
    static func getFileStorage() async throws -> FileStorage {
        guard let storage = fileStorage else {
            let pool = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            let eventLoop = pool.next()
            let s = try await FileStorage.new(
                eventLoop: eventLoop,
                storagePath: "/Users/clwang/Downloads/file_storage_testing",
                indexDatabaseConfigure: .init(hostname: "localhost", port: 5432, username: "clwang", database: "postgres", tls: .disable),
                chunkSize: chunkSize,
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
