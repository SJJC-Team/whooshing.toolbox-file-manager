import Foundation
import NIOCore
import Fluent
import FluentSQL
import FluentKit
import ErrorHandle
import NIOAdvanced
import NIOFileSystem

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
        guard index.type == .directory else { throw Errcase.getDirectoryFailed.d("目标并非是一个目录，而是 \(index.type)") }
        self.id = try required(throws: Errcase.getDirectoryFailed, "获取目录 ID 失败") {
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
    
    func subitems(withDeleted: Bool = false) -> EventLoopRes<[any StorageEntry], Errcase> {
        
        let r: QueryBuilder<FileIndex>
        
        if withDeleted {
            r = FileIndex.query(on: storage.indexDatabase)
                .filter(\.$parent.$id == id)
                .withDeleted()
        } else {
            r = FileIndex.query(on: storage.indexDatabase)
                .filter(\.$parent.$id == id)
        }
        
        return r.all()
            .withError(Errcase.fetchDirectorySubItemFailed, "数据库查询失败")
            .flatMapThrowing
        { fileIndex throws(BscError<Errcase>) in
            try fileIndex.map { index throws(BscError<Errcase>) in
                switch index.type {
                case .file:
                    return try required(throws: Errcase.fetchDirectorySubItemFailed, "文件获取失败") {
                        try File(from: index, parent: self.path, storage: storage)
                    }
                case .directory:
                    return try required(throws: Errcase.fetchDirectorySubItemFailed, "目录获取失败") {
                        try Directory(from: index, parent: self.path, storage: storage)
                    }
                }
            }
        }
    }
    
    func empty(force: Bool = false) -> EventLoopRes<Void, Errcase> {
        subitems(withDeleted: force).wrapped
            .flatMapEach(on: storage.eventLoop) {
                $0.delete(force: force).wrapped
            }
            .withError(Errcase.emptyDirectoryFailed)
    }
    
    func delete(force: Bool = false) -> EventLoopRes<Void, Errcase> {
        guard
            !self.isRoot,
            let id = self.id
        else {
            return storage.eventLoop.makeFailedResult(Errcase.deleteDirectoryFailed, "不可删除根目录")
        }
        
        if force {
            let query = """
            SELECT fc."\(FileCrypto.fields.storageKey.name)"
            FROM (
                WITH RECURSIVE descendants AS (
                    SELECT "\(FileIndex.fields.id.name)" FROM "\(FileIndex.name)" WHERE "\(FileIndex.fields.id.name)" = '\(id.uuidString)'
                    UNION ALL
                    SELECT f."\(FileIndex.fields.id.name)" FROM "\(FileIndex.name)" f
                    INNER JOIN descendants d ON f."\(FileIndex.fields.parent.name)" = d."\(FileIndex.fields.id.name)"
                )
                SELECT "\(FileIndex.fields.id.name)" FROM descendants
            ) d
            LEFT JOIN "\(FileCrypto.name)" fc ON fc."\(FileCrypto.fields.id.name)" = d.id where fc."\(FileCrypto.fields.storageKey.name)" is not null;
            """
            
            // 强制删除，删除数据库文件索引的同时，还需要删除硬盘上的所有关联的真实文件
            return storage.db.query(query)
                .withError(Errcase.deleteDirectoryFailed, "数据库递归查询子项目失败")
                .flatMap
            { fileList in
                FileIndex.query(on: storage.indexDatabase)
                    .filter(\.$id == id)
                    .delete(force: true)
                    .map { fileList }
                    .withError(Errcase.deleteDirectoryFailed, "数据库递归删除记录失败")
            }.flatMap { fileList in
                storage.db.eventLoop.makeFutureWithTask {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for row in fileList {
                            group.addTask {
                                let path = FilePath("\(storage.storagePath)/\(try row.decode(String.self)).\(FileStorage.CryptoFileExtension)")
                                try await FileSystem.shared.removeItem(at: path)
                            }
                        }
                        try await group.waitForAll()
                    }
                }.withError(Errcase.deleteDirectoryFailed, "从文件系统删除加密文件失败")
            }
        } else {
            // 软删除，仅递归软删除数据库文件索引
            
            let query = """
                WITH RECURSIVE descendants AS (
                    SELECT "\(FileIndex.fields.id.name)" AS id FROM "\(FileIndex.name)" WHERE "\(FileIndex.fields.id.name)" = '\(id.uuidString)'
                    UNION ALL
                    SELECT f."\(FileIndex.fields.id.name)" FROM "\(FileIndex.name)" f
                    INNER JOIN descendants d ON f."\(FileIndex.fields.parent.name)" = d."\(FileIndex.fields.id.name)"
                )
                SELECT id FROM descendants;
            """
            
            return storage.db.trans { db in
                db.query(query)
                .flatMapThrowing { res in
                    try res.map { try $0.decode(String.self) }
                }
                .withError(Errcase.deleteDirectoryFailed, "数据库递归检索失败")
                .map { ids in
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                    let timestamp = formatter.string(from: Date())
                    return (ids, timestamp)
                }
                .flatMap
                { ids, ts in
                    let indexQuery = SQLQueryString("""
                        UPDATE \(ident: FileIndex.name)
                        SET \(ident: FileIndex.fields.deleteAt.name) = \(literal: ts)
                        WHERE \(ident: FileIndex.fields.id.name) IN (\(literals: ids, joinedBy: ", "))
                    """)
                    
                    let cryptoQuery = SQLQueryString("""
                        UPDATE \(ident: FileCrypto.name)
                        SET \(ident: FileCrypto.fields.deleteAt.name) = \(literal: ts)
                        WHERE \(ident: FileCrypto.fields.id.name) IN (\(literals: ids, joinedBy: ", "))
                    """)
                    
                    let partQuery = SQLQueryString("""
                        UPDATE \(ident: FilePart.name)
                        SET \(ident: FilePart.fields.deleteAt.name) = \(literal: ts)
                        WHERE \(ident: FilePart.fields.fileId.name) IN (\(literals: ids, joinedBy: ", "))
                    """)
                    
                    return db.raw(indexQuery)
                        .run()
                        .withError(Errcase.deleteDirectoryFailed, "数据库 \(FileIndex.name) 递归软删除失败")
                        .flatMap { _ in
                            db.raw(cryptoQuery)
                                .run()
                                .withError(Errcase.deleteDirectoryFailed, "数据库 \(FileCrypto.name) 递归软删除失败")
                        }.flatMap { _ in
                            db.raw(partQuery)
                                .run()
                                .withError(Errcase.deleteDirectoryFailed, "数据库 \(FilePart.name) 递归软删除失败")
                        }
                }
            }
        }
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
        
        let superId: UUID
        do {
            superId = try dir.fileIndex.requireID()
        } catch {
            return storage.eventLoop.makeFailedResult(Errcase.moveDirectoryFailed, "获取目标目录的 id 失败")
        }
        
        fileIndex.$parent.id = dir.fileIndex.isRoot ? nil : superId
        if let name = name {
            fileIndex.name = name
        }
        return fileIndex.update(on: storage.indexDatabase)
            .withError(Errcase.moveDirectoryFailed, "数据库更新失败")
            .flatMapThrowing
        { () throws(BscError<Errcase>) in
            try required(throws: Errcase.moveDirectoryFailed, "未知错误") {
                try .init(from: fileIndex, parent: dir.path, storage: storage)
            }
        }
    }
}

extension Directory: CustomStringConvertible {
    public var description: String {
        """
        Directory (
            id: \(id?.uuidString ?? "nil")
            name: \(name)
            path: \(path.string)
            createdAt: \(createdAt)
            updatedAt: \(updatedAt)
        )
        """
    }
}
