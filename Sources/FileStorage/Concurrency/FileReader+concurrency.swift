import ErrorHandle
import NIOCore
import NIOAdvanced
import AsyncAlgorithms
import Foundation

public extension FileReader {
    @inlinable
    func readData(part: ReadPart = .all) async throws(BscError<File.Errcase>) -> Data {
        try await self.readData(part: part).get()
    }
    
    @inlinable
    func readChunks(
        part: ReadPart = .all,
        _ callback: @escaping @Sendable (Data) async throws -> ()
    ) async throws(BscError<File.Errcase>) {
        try await self.readChunks(part: part, callback).get()
    }
    
    @inlinable
    func readChunks(
        part: ReadPart = .all,
        _ callback: @escaping @Sendable (Data) -> EventLoopResult<Void, Error>
    ) async throws(BscError<File.Errcase>) {
        try await self.readChunks(part: part, callback).get()
    }
}
