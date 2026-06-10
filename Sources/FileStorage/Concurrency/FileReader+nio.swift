import ErrorHandle
import NIOCore
import NIOAdvanced
import AsyncAlgorithms
import Foundation

extension __FileReader {
    @inlinable
    func readData(part: ReadPart = .all) -> EventLoopRes<Data, File.Errcase> {
        let action: @Sendable () async throws(File.Errcase.ErrType) -> Data = {
            try await self.readData(part: part)
        }
        return storage.db.eventLoop.bridge(action)
    }
    
    @inlinable
    func readChunks(
        part: ReadPart = .all,
        _ callback: @escaping @Sendable (Data) async throws -> ()
    ) -> EventLoopRes<Void, File.Errcase> {
        let action: @Sendable () async throws(File.Errcase.ErrType) -> Void = {
            try await self.readChunks(part: part, callback)
        }
        return storage.db.eventLoop.bridge(action)
    }
    
    @inlinable
    func readChunks(
        part: ReadPart = .all,
        _ callback: @escaping @Sendable (Data) -> EventLoopResult<Void, Error>
    ) -> EventLoopRes<Void, File.Errcase> {
        let action: @Sendable () async throws(File.Errcase.ErrType) -> Void = {
            try await self.readChunks(part: part, callback)
        }
        return storage.db.eventLoop.bridge(action)
    }
}
