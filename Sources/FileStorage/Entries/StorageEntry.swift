import Foundation
import FluentKit
import NIOAdvanced
import ErrorHandle

public protocol StorageEntry: Sendable {
    var name: String { get }
    var storage: FileStorage { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    
    func getSize() -> EventLoopRes<Int64, FileStorage.Errcase>
    func delete(force: Bool) -> EventLoopRes<Void, FileStorage.Errcase>
    func rename(as name: String) -> EventLoopRes<Self, FileStorage.Errcase>
    func move(to path: StoragePath, as name: String?) -> EventLoopRes<Self, FileStorage.Errcase>
    func move(to dir: Directory, as name: String?) -> EventLoopRes<Self, FileStorage.Errcase>
}

public extension StorageEntry {
    func move(to path: StoragePath, as name: String?) -> EventLoopRes<Self, FileStorage.Errcase> {
        storage.getDirectory(at: path).flatMap { dir in
            move(to: dir, as: name)
        }
    }
}
