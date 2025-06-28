import Foundation
import NIOCore
import FluentKit
import ErrorHandle
import NIOAdvanced

public struct Directory: StorageEntry, Sendable {
    
    public let id: UUID?
    public let name: String
    public let path: StoragePath
    public let createdAt: Date
    public let updatedAt: Date
    
    public unowned let storage: FileStorage
    
    let fileIndex: FileIndex
    
    public typealias Errcase = FileStorage.Errcase
    
    init(
        from index: FileIndex,
        parent: StoragePath?,
        storage: FileStorage
    ) throws(BscError<Errcase>) {
        guard index.type == .directory else { throw .init(.indexTypeIsNotDirectory) }
        self.id = try required(throws: Errcase.fetchDirectoryIdFailed) {
            try index.getId()
        }
        self.name = index.name
        self.path = parent == nil ? "<<ROOT>>" : (parent! + index.name)
        self.createdAt = index.createdAt
        self.updatedAt = index.updatedAt
        self.storage = storage
        self.fileIndex = index
    }
}

public extension Directory {
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
    
    func subitems() -> EventLoopRes<[any StorageEntry], Errcase> {
        FileIndex.query(on: storage.indexDatabase)
            .filter(\.$parent.$id == id)
            .all()
            .withError(Errcase.fetchSubItemFailed, "数据库查询失败")
            .flatMapThrowing
        { fileIndex throws(BscError<Errcase>) in
            try fileIndex.map { index throws(BscError<Errcase>) in
                switch index.type {
                case .file:
                    return try required(throws: Errcase.fetchSubItemFailed, "文件获取失败") {
                        try File(from: index, parent: self.path, storage: storage)
                    }
                case .directory:
                    return try required(throws: Errcase.fetchSubItemFailed, "目录获取失败") {
                        try Directory(from: index, parent: self.path, storage: storage)
                    }
                }
            }
        }
    }
    
    func empty(force: Bool = false) -> EventLoopRes<Void, Errcase> {
        subitems().wrapped.flatMapEach(on: storage.eventLoop) { $0.delete(force: force).wrapped }.withError()
    }
    
    func delete(force: Bool = false) -> EventLoopRes<Void, Errcase> {
        guard
            !self.isRoot,
            let id = self.id
        else {
            return storage.eventLoop.makeFailedResult(Errcase.deleteDirectoryFailed, "不可删除根目录")
        }
        return FileIndex.query(on: storage.indexDatabase)
            .filter(\.$id == id)
            .delete(force: force)
            .withError(Errcase.deleteDirectoryFailed, "数据库删除记录失败")
    }
    
    func rename(as name: String) -> EventLoopRes<Directory, Errcase> {
        guard !self.isRoot else {
            return storage.eventLoop.makeFailedResult(Errcase.renameDirectoryFailed, "不可重命名根目录")
        }
        fileIndex.name = name
        return fileIndex.update(on: storage.indexDatabase)
            .withError(Errcase.renameDirectoryFailed, "数据库更新失败")
            .flatMapThrowing
        { () throws(BscError<Errcase>) in
            try required(throws: Errcase.renameDirectoryFailed, "未知错误") {
                try .init(from: fileIndex, parent: self.path.isRoot ? nil : self.path.parent, storage: storage)
            }
        }
    }
    
    func move(to dir: Directory, as name: String? = nil) -> EventLoopRes<Directory, Errcase> {
        guard !self.isRoot else {
            return storage.eventLoop.makeFailedResult(Errcase.moveDirectoryFailed, "不可操作根目录")
        }
        fileIndex.parent = dir.fileIndex.isRoot ? nil : dir.fileIndex
        if let name = name {
            fileIndex.name = name
        }
        return fileIndex.update(on: storage.indexDatabase)
            .withError(Errcase.moveDirectoryFailed, "数据库更新失败")
            .flatMapThrowing
        { () throws(BscError<Errcase>) in
            try required(throws: Errcase.moveDirectoryFailed, "未知错误") {
                try .init(from: fileIndex, parent: self.path.isRoot ? nil : self.path.parent, storage: storage)
            }
        }
    }
}
