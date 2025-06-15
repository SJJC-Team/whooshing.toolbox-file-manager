import Foundation
import FluentKit
import NIOAdvanced
import ErrorHandle

public protocol StorageEntry: Sendable {
    var name: String { get }
    var storage: FileStorage { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    
    func delete(force: Bool) -> EventLoopResult<Void, BscError<FileStorage.Errcase>>
    func rename(as name: String) -> EventLoopResult<Self, BscError<FileStorage.Errcase>>
    func move(to path: StoragePath, as name: String?) -> EventLoopResult<Self, BscError<FileStorage.Errcase>>
    func move(to dir: Directory, as name: String?) -> EventLoopResult<Self, BscError<FileStorage.Errcase>>
}

public extension StorageEntry {
    func move(to path: StoragePath, as name: String?) -> EventLoopResult<Self,  BscError<FileStorage.Errcase>> {
        storage.getDirectory(at: path).flatMap { dir in
            move(to: dir, as: name)
        }
    }
}
