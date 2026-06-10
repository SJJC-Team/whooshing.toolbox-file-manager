import ErrorHandle
import NIOCore
import NIOAdvanced
import AsyncAlgorithms
import Foundation

extension __FileWriter {
    @inlinable
    func write(at: ByteIndex, bytes: Data, method: WriteMethod = .replace) -> EventLoopRes<Void, File.Errcase> {
        let action: @Sendable () async throws(File.Errcase.ErrType) -> Void = {
            try await self.write(at: at, bytes: bytes, method: method)
        }
        return storage.db.eventLoop.bridge(action)
    }
    
    @inlinable
    func write(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>, method: WriteMethod = .replace) -> EventLoopRes<Void, File.Errcase> {
        let action: @Sendable () async throws(File.Errcase.ErrType) -> Void = {
            try await self.write(at: at, from: from)
        }
        return storage.db.eventLoop.bridge(action)
    }
    
    @inlinable
    func insert(at: ByteIndex, bytes: Data) -> EventLoopRes<Void, File.Errcase> {
        let action: @Sendable () async throws(File.Errcase.ErrType) -> Void = {
            try await self.insert(at: at, bytes: bytes)
        }
        return storage.db.eventLoop.bridge(action)
    }
    
    @inlinable
    func replace(at: ByteIndex, bytes: Data) -> EventLoopRes<Void, File.Errcase> {
        let action: @Sendable () async throws(File.Errcase.ErrType) -> Void = {
            try await self.replace(at: at, bytes: bytes)
        }
        return storage.db.eventLoop.bridge(action)
    }
    
    @inlinable
    func insert(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>) -> EventLoopRes<Void, File.Errcase> {
        let action: @Sendable () async throws(File.Errcase.ErrType) -> Void = {
            try await self.insert(at: at, from: from)
        }
        return storage.db.eventLoop.bridge(action)
    }
    
    @inlinable
    func replace(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>) -> EventLoopRes<Void, File.Errcase> {
        let action: @Sendable () async throws(File.Errcase.ErrType) -> Void = {
            try await self.replace(at: at, from: from)
        }
        return storage.db.eventLoop.bridge(action)
    }
    
    @inlinable
    func remove(in range: Range<Int64>) -> EventLoopRes<Void, File.Errcase> {
        let action: @Sendable () async throws(File.Errcase.ErrType) -> Void = {
            try await self.remove(in: range)
        }
        return storage.db.eventLoop.bridge(action)
    }
    
    @inlinable
    func remove(in range: ClosedRange<Int64>) -> EventLoopRes<Void, File.Errcase> {
        let action: @Sendable () async throws(File.Errcase.ErrType) -> Void = {
            try await self.remove(in: range)
        }
        return storage.db.eventLoop.bridge(action)
    }
}
