import ErrorHandle

public extension StorageEntry {
    func getSize() async throws(BscError<FileStorage.Errcase>) -> Int64 {
        try await self.getSize().get()
    }
    
    func delete(force: Bool) async throws(BscError<FileStorage.Errcase>) {
        try await self.delete(force: force).get()
    }
    
    func rename(as name: String) async throws(BscError<FileStorage.Errcase>) -> Self {
        try await self.rename(as: name).get()
    }
    
    func move(to path: StoragePath, as name: String? = nil) async throws(BscError<FileStorage.Errcase>) -> Self {
        try await self.move(to: path, as: name).get()
    }
    
    func move(to dir: Directory, as name: String? = nil) async throws(BscError<FileStorage.Errcase>) -> Self {
        try await self.move(to: dir, as: name).get()
    }
}
