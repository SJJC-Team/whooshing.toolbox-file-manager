import ErrorHandle
import NIOCore
import NIOAdvanced
import AsyncAlgorithms
import Foundation

public extension FileWriter {
    @inlinable
    func write(at: ByteIndex, bytes: Data, method: WriteMethod = .replace) async throws(BscError<File.Errcase>) {
        try await self.write(at: at, bytes: bytes, method: method).get()
    }
    
    @inlinable
    func write(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>, method: WriteMethod = .replace) async throws(BscError<File.Errcase>) {
        try await self.write(at: at, from: from).get()
    }
    
    @inlinable
    func insert(at: ByteIndex, bytes: Data) async throws(BscError<File.Errcase>) {
        try await self.insert(at: at, bytes: bytes).get()
    }
    
    @inlinable
    func replace(at: ByteIndex, bytes: Data) async throws(BscError<File.Errcase>) {
        try await self.replace(at: at, bytes: bytes).get()
    }
    
    @inlinable
    func insert(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>) async throws(BscError<File.Errcase>) {
        try await self.insert(at: at, from: from).get()
    }
    
    @inlinable
    func replace(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>) async throws(BscError<File.Errcase>) {
        try await self.replace(at: at, from: from).get()
    }
    
    @inlinable
    func remove(in range: Range<Int64>) async throws(BscError<File.Errcase>) {
        try await self.remove(in: range).get()
    }
    
    @inlinable
    func remove(in range: ClosedRange<Int64>) async throws(BscError<File.Errcase>) {
        try await self.remove(in: range).get()
    }
    
}
