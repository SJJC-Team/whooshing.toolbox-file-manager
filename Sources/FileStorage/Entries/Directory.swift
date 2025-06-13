import Foundation
import NIOCore
import FluentKit
import ErrorHandle

public struct Directory: StorageEntry, Sendable {
    
    public let id: UUID?
    public let name: String
    public let path: StoragePath
    public let createdAt: Date
    public let updatedAt: Date
    
    public unowned let storage: FileStorage
    
    init(
        id: UUID?,
        name: String,
        path: StoragePath,
        createdAt: Date,
        updatedAt: Date,
        storage: FileStorage
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.storage = storage
    }
    
    init(
        from index: FileIndex,
        parent: StoragePath,
        storage: FileStorage
    ) throws {
        guard index.type == .directory else { throw Err.indexTypeIsNotDirectory.d(16023) }
        self.id = index.id
        self.name = index.name
        self.path = parent + index.name
        self.createdAt = index.createdAt
        self.updatedAt = index.updatedAt
        self.storage = storage
    }
}

public extension Directory {
    enum Err: String, ErrList {
        public var domain: String { "woo.sys.file.storage.file.err" }
        case indexTypeIsNotDirectory = "目标并非是一个目录"
        case deleteFailed = "目录删除失败"
    }
    
    var isRoot: Bool { self.id == nil }
    
    func isExist() -> Bool {
        if let id = self.id {
            return (try? FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first().wait()) != nil
        } else {
            return true
        }
    }
    
    func isExist() async -> Bool {
        if let id = self.id {
            return (try? await FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first()) != nil
        } else {
            return true
        }
    }
    
    func subitems() -> EventLoopFuture<[StorageEntry]> {
        FileIndex.query(on: storage.indexDatabase).filter(\.$parent.$id == id).all().flatMapThrowing { fileIndex in
            try fileIndex.map { index in
                switch index.type {
                case .file: return try File(from: index, parent: self.path, storage: storage)
                case .directory: return try Directory(from: index, parent: self.path, storage: storage)
                }
            }
        }
    }
    
    func empty(force: Bool = false) -> EventLoopFuture<Void> {
        subitems().flatMapEach(on: storage.eventLoop) { $0.delete(force: force) }
    }
    
    func delete(force: Bool = false) -> EventLoopFuture<Void> {
        guard let id = self.id else { return storage.eventLoop.makeFailedFuture(Err.deleteFailed.d("不能删除根目录", 16021)) }
        return FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).delete(force: force)
    }
}
