import NIOFileSystem
import AsyncAlgorithms
import Cryptos
import NIOConcurrencyHelpers
import ErrorHandle
import NIOCore
import Foundation

/// 文件内容操作处理协议，表示文件操作时需要实现的基础行为。
///
/// 该协议继承自 `Sendable`，支持异步关闭文件资源。
public protocol FileContentHandler: Sendable {
    /// 该文件句柄所运行在其上的 EventLoop
    var eventLoop: any EventLoop { get }
    
    /// 异步关闭文件资源。
    ///
    /// - Throws: 关闭操作失败时抛出带有文件错误类型的错误。
    func close() async throws(BscError<File.Errcase>)
}

extension __FileContentHandler {
    @inlinable
    func getHandleLogger() -> Logger {
        self.logger.derive(metadata: ["handle-id": .stringConvertible(UUID())])
    }
}

protocol __FileContentHandler: FileContentHandler {
    var fileIndex: FileIndex { get }
    var fileCrypto: FileCrypto { get }
    var key: Crypto.Symm.Key { get }
    var lock: NIOLock { get }
    var storage: FileStorage { get }
    var filePath: StoragePath { get }
    var fileRealPath: FilePath { get }
    var fileHandler: FileHandleProtocol { get }
    var logger: Logger { get }
    var __fileHandler: FileHandleProtocol { get }
}

extension __FileContentHandler {
    @inlinable
    var fileHandler: FileHandleProtocol {
        lock.withLock {
            __fileHandler
        }
    }
    
    @inlinable
    var eventLoop: any EventLoop {
        self.storage.eventLoop
    }
    
    @inlinable
    func close() async throws(BscError<File.Errcase>) {
        do {
            logger.info("文件操作子关闭成功")
            try await fileHandler.close()
        } catch {
            throw File.Errcase.closeFileFailed.d("\(storage.storagePath)/\(fileCrypto.storageKey).\(storage.fileExtension)").subErr(error)
        }
    }
}
