import NIOFileSystem
import AsyncAlgorithms
import Cryptos
import NIOConcurrencyHelpers

public protocol FileContentHandler: Sendable {
    func close() async throws
}

protocol __FileContentHandler: FileContentHandler {
    var fileIndex: FileIndex { get }
    var fileCrypto: FileCrypto { get }
    var key: Crypto.Symm.Key { get }
    var lock: NIOLock { get }
    var storage: FileStorage { get }
    var fileHandler: FileHandleProtocol { get }
    var __fileHandler: FileHandleProtocol { get }
}

extension __FileContentHandler {
    var fileHandler: FileHandleProtocol {
        lock.withLock {
            __fileHandler
        }
    }
    
    func close() async throws {
        try await fileHandler.close()
    }
}

extension AsyncThrowingChannel where Failure == Error {
    func castError<NewError: Error>(to _: NewError.Type) -> AsyncThrowingChannel<Element, NewError> {
        unsafeBitCast(self, to: AsyncThrowingChannel<Element, NewError>.self)
    }
}
