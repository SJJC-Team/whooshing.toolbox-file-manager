import ErrorHandle
import NIOAdvanced
import NIOCore

public extension File {
    @inlinable
    func withReader<T>(
        _ action: @escaping @Sendable (FileReader) async throws -> T
    ) async throws(BscError<Errcase>) -> T where T: Sendable {
        try await __withReader { reader in
            storage.eventLoop.makeFutureWithTask {
                try await action(reader)
            }.withError(Errcase.openFileFailed)
        }.get()
    }
    
    @inlinable
    func withWriter<T>(
        _ action: @escaping @Sendable (FileWriter) async throws -> T
    ) async throws(BscError<Errcase>) -> T where T: Sendable {
        try await __withWriter { writer in
            storage.eventLoop.makeFutureWithTask {
                try await action(writer)
            }.withError(Errcase.openFileFailed)
        }.get()
    }
    
    @inlinable
    func withReadWriter<T>(
        _ action: @escaping @Sendable (FileReadWriter) async throws -> T
    ) async throws(BscError<Errcase>) -> T where T: Sendable {
        try await __withReadWriter { readWriter in
            storage.eventLoop.makeFutureWithTask {
                try await action(readWriter)
            }.withError(Errcase.openFileFailed)
        }.get()
    }
}

public extension File {
    @inlinable
    func openForRead() async throws(BscError<Errcase>) -> FileReader {
        try await self.openForRead().get()
    }
    
    @inlinable
    func openForWrite() async throws(BscError<Errcase>) -> FileWriter {
        try await self.openForWrite().get()
    }
    
    @inlinable
    func openForReadAndWrite() async throws(BscError<Errcase>) -> FileReadWriter {
        try await self.openForReadAndWrite().get()
    }
}
