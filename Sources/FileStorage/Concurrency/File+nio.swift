import ErrorHandle
import NIOAdvanced
import NIOCore

public extension File {
    func withReader<T, G>(
        _ action: @escaping @Sendable (FileReader) -> EventLoopResult<T, G>
    ) -> EventLoopRes<T, Errcase> where T: Sendable {
        storage.eventLoop.bridge { () throws(Errcase.ErrType) in
            try await withReader {
                try await action($0).get()
            }
        }
    }
    
    func withWriter<T, G>(
        _ action: @escaping @Sendable (FileWriter) -> EventLoopResult<T, G>
    ) -> EventLoopRes<T, Errcase> where T: Sendable {
        storage.eventLoop.bridge { () throws(Errcase.ErrType) in
            try await withWriter {
                try await action($0).get()
            }
        }
    }
    
    func withReadWriter<T, G>(
        _ action: @escaping @Sendable (FileReadWriter) -> EventLoopResult<T, G>
    ) -> EventLoopRes<T, Errcase> where T: Sendable {
        storage.eventLoop.bridge { () throws(Errcase.ErrType) in
            try await withReadWriter {
                try await action($0).get()
            }
        }
    }
}

public extension File {
    @inlinable
    func openForRead() async -> Res<FileReader, Errcase> {
        await .async { () throws(BscError<Errcase>) in
            try await openForRead()
        }
    }
    
    @inlinable
    func openForWrite() async -> Res<FileWriter, Errcase> {
        await .async { () throws(BscError<Errcase>) in
            try await openForWrite()
        }
    }
    
    @inlinable
    func openForReadAndWrite() async -> Res<FileReadWriter, Errcase> {
        await .async { () throws(BscError<Errcase>) in
            try await openForReadAndWrite()
        }
    }
}
