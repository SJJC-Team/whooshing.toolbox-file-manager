import Foundation
import FluentKit

public protocol StorageEntry: Sendable {
    var name: String { get }
    var storage: FileStorage { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    
    func delete(force: Bool) -> EventLoopFuture<Void>
}

extension StorageEntry {
    static func factory(
        from index: FileIndex,
        parent: StoragePath,
        storage: FileStorage
    ) throws -> Self {
        if self.self == File.self {
            return (try File(from: index, parent: parent, storage: storage)) as! Self
        } else if self.self == Directory.self {
            return (try Directory(from: index, parent: parent, storage: storage)) as! Self
        }
        fatalError("不应执行至此")
    }
}
