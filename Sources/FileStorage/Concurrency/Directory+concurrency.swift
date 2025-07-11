import ErrorHandle
import NIOAdvanced

public extension Directory {
    @inlinable
    func subitems() async throws(BscError<Errcase>) -> [any StorageEntry] {
        try await self.subitems().get()
    }
    
    @inlinable
    func empty(force: Bool = false) async throws(BscError<Errcase>) {
        try await self.empty(force: force).get()
    }
}
