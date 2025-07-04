import ErrorHandle
import NIOCore
import NIOAdvanced
import AsyncAlgorithms

public extension FileReader {
    func readData(part: ReadPart = .all) async throws(BscError<File.Errcase>) -> ByteBuffer {
        try await self.readData(part: part).get()
    }
    
    func readChunks(
        part: ReadPart = .all,
        _ callback: @escaping @Sendable (ByteBuffer) async throws -> ()
    ) async throws(BscError<File.Errcase>) {
        try await self.readChunks(part: part, callback).get()
    }
    
    func readChunks(
        part: ReadPart = .all,
        _ callback: @escaping @Sendable (ByteBuffer) -> EventLoopResult<Void, Error>
    ) async throws(BscError<File.Errcase>) {
        try await self.readChunks(part: part, callback).get()
    }
}
