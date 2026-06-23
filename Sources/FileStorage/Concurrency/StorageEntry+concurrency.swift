import NIOAdvanced

public extension StorageEntry {
    @inlinable
    func getSize() async throws(FileStorage.Errcase.ErrType) -> Int64 {
        try await self.getSize().get()
    }
    
    @inlinable
    func delete(force: Bool) async throws(FileStorage.Errcase.ErrType) {
        try await self.delete(force: force).get()
    }
    
    @inlinable
    func rename(as name: String) async throws(FileStorage.Errcase.ErrType) -> Self {
        try await self.rename(as: name).get()
    }
    
    @inlinable
    func move(to path: StoragePath, as name: String? = nil) async throws(FileStorage.Errcase.ErrType) -> Self {
        try await self.move(to: path, as: name).get()
    }
    
    @inlinable
    func move(to dir: Directory, as name: String? = nil) async throws(FileStorage.Errcase.ErrType) -> Self {
        try await self.move(to: dir, as: name).get()
    }
}
