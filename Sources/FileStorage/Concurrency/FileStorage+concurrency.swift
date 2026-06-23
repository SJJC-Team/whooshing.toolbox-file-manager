import NIOAdvanced

public extension FileStorage {
    @inlinable
    func createDirectory(
        at path: StoragePath,
        withIntermediateDirectories createIfNeed: Bool = false,
        slience: Bool = false
    ) async throws(Errcase.ErrType) -> Directory {
        try await self.createDirectory(
            at: path,
            withIntermediateDirectories: createIfNeed,
            slience: slience
        ).get()
    }
    
    @inlinable
    func getDirectory(
        at path: StoragePath
    ) async throws(Errcase.ErrType) -> Directory {
        try await self.getDirectory(at: path).get()
    }
    
    @inlinable
    func createFile(
        at path: StoragePath,
        chunkSize: Int64 = 65535,
        withIntermediateDirectories createIfNeed: Bool = false,
        slience: Bool = false
    ) async throws(Errcase.ErrType) -> File {
        try await self.createFile(
            at: path,
            chunkSize: chunkSize,
            withIntermediateDirectories: createIfNeed,
            slience: slience
        ).get()
    }
    
    @inlinable
    func getFile(
        at path: StoragePath
    ) async throws(Errcase.ErrType) -> File {
        try await self.getFile(at: path).get()
    }
}
