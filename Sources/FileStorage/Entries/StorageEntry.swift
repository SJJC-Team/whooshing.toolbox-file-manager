import Foundation
import FluentKit
import NIOCore

public protocol StorageEntry: Sendable {
    var name: String { get }
    var storage: FileStorage { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    
    func delete(force: Bool) -> EventLoopFuture<Void>
    func rename(as name: String) -> EventLoopFuture<Self>
    func move(to path: StoragePath, as name: String?) -> EventLoopFuture<Self>
    func move(to dir: Directory, as name: String?) -> EventLoopFuture<Self>
}

public extension StorageEntry {
    func move(to path: StoragePath, as name: String?) -> EventLoopFuture<Self> {
        storage.getDirectory(at: path).flatMap { dir in
            move(to: dir, as: name)
        }
    }
}
