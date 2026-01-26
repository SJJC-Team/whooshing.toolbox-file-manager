import ErrorHandle
import NIOAdvanced
import NIOCore

public extension File {
    @inlinable
    func withReader<T>(
        _ action: @escaping @Sendable (FileReader) async throws -> T
    ) async throws(BscError<Errcase>) -> T where T: Sendable {
        let reader = try await self.openForRead().get()
        do {
            let res = try await action(reader)
            try await reader.close()
            return res
        } catch {
            try? await reader.close()
            throw Errcase.openFileFailed.subErr(error)
        }
    }
    
    @inlinable
    func withWriter<T>(
        _ action: @escaping @Sendable (FileWriter) async throws -> T
    ) async throws(BscError<Errcase>) -> T where T: Sendable {
        let writer = try await self.openForWrite().get()
        do {
            let res = try await action(writer)
            try await writer.close()
            return res
        } catch {
            try? await writer.close()
            throw Errcase.openFileFailed.subErr(error)
        }
    }
    
    @inlinable
    func withReadWriter<T>(
        _ action: @escaping @Sendable (FileReadWriter) async throws -> T
    ) async throws(BscError<Errcase>) -> T where T: Sendable {
        let readWriter = try await self.openForReadAndWrite().get()
        do {
            let res = try await action(readWriter)
            try await readWriter.close()
            return res
        } catch {
            try? await readWriter.close()
            throw Errcase.openFileFailed.subErr(error)
        }
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
