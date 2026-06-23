import NIOAdvanced

public extension Directory {
    @inlinable
    func subitems() async throws(Errcase.ErrType) -> [any StorageEntry] {
        try await self.subitems().get()
    }
    
    @inlinable
    func empty(force: Bool = false) async throws(Errcase.ErrType) {
        try await self.empty(force: force).get()
    }
}
