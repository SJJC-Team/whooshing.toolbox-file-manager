import ErrorHandle

public extension Directory {
    func subitems() async throws(BscError<Errcase>) -> [any StorageEntry] {
        try await self.subitems().get()
    }
    
    func empty(force: Bool = false) async throws(BscError<Errcase>) {
        try await self.empty(force: force).get()
    }
}
