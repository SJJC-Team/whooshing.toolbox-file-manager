import Foundation
import NIOCore
import Fluent
import FluentSQL
import FluentKit
import ErrorHandle
import NIOAdvanced
import NIOFileSystem

/// 表示文件系统中的目录对象，支持异步查询、大小计算、子项列出与递归删除等操作。
///
/// 该目录类型并不储存任何真实数据，仅仅为目录句柄，因此非常轻量。
/// 你可以使用该实例对该文件进行诸如删除，重命名，移动等等操作。
///
/// #### 目录基本操作
///
/// 若你要创建一个目录，请参考 [FileStorage+Operations.swift](../FileStorage+Operations.swift) 文件中的 `createDirectory(...)` 函数
/// ``` swift
/// // 首先，提供各种参数创建一个 FileStorage 实例
/// let storage = FileStorage.new(...)
///
/// // 提供一个路径，目录将会创建在该路径下
/// // 注意，该路径为虚拟文件系统的路径，详情请见 StoragePath 类型
/// let path: StoragePath = "testing/example"
///
/// // 在指定的路径下创建目录
/// // 你可以指定 withIntermediateDirectories: 参数为 true 以自动创建中间目录
/// // 否则，若中间目录不存在，将会抛出错误
/// let dir = try await storage.createDirectory(at: path)
///
/// print(dir.name)                 // <-- print: example
/// print(dir.path)                 // <-- print: testing/example
/// print(dir.isExist())            // <-- print: true
/// ```
///
/// 得到目录实例后，你可以对其重新命名:
/// ``` swift
/// let renamedDir = try await dir.rename(as: "images")
///
/// print(renamedDir.name)          // <-- print: images
/// print(renamedDir.path)          // <-- print: testing/images
/// ```
///
/// 移动目录:
/// ``` swift
/// // 首先你需要有一个目标目录实例
/// let destination: Directory = ...
///
/// // 将目录移动到目标目录下
/// let movedDir = renamedDir.move(to: destination)
///
/// print(movedDir.path)            // <-- print: <目标目录的路径>/images
/// ```
///
/// 你可以获取该目录的所有第一层子项目:
/// ``` swift
/// let items = try await movedDir.subItems()
/// for item in items {
///     if let file = item as? File {
///         // 打印出该子文件的信息
///         print(file.name)
///         print(file.mimeType)
///         print(file.path)
///         print(file.size)
///         print(file.isExist())
///     } else if let dir = item as? Directory {
///         // 打印出该子目录的信息
///         print(dir.name)
///         print(dir.path)
///         print(dir.isExist())
///     }
/// }
/// ```
///
/// 获取目录大小:
/// ``` swift
/// let size = try await movedDir.getSize()
///
/// print(size)
/// ```
///
/// 清空目录:
/// ``` swift
/// // 软清空目录，默认，极其轻量化操作，不会真正删除文件，仅标记为已删除
/// try await movedDir.empty()
/// // 或者，硬清空(破坏性操作)，这将直接从数据库及文件系统中彻底删除所有的子项目，且无法撤销
/// try await movedDir.delete(force: true)
/// ```
///
/// 删除目录:
/// ``` swift
/// // 软删除目录，默认，极其轻量化操作，不会真正删除文件，仅标记为已删除
/// try await movedDir.delete()
/// // 或者，硬删除(破坏性操作)，这将直接从数据库及文件系统中彻底删除该目录数据，且无法撤销
/// // 需要注意的是，删除一个文件夹也会删除其所有的子项目，因此请谨慎操作
/// try await movedDir.delete(force: true)
/// ```
public struct Directory: StorageEntry, Sendable {
    
    /// 目录 ID，根目录为 nil。
    public let id: UUID?
    /// 目录名称。
    public let name: String
    /// 目录的完整路径。
    public let path: StoragePath
    /// 创建时间。
    public let createdAt: Date
    /// 最后更新时间。
    public let updatedAt: Date
    
    /// 文件存储系统引用。
    public unowned let storage: FileStorage
    
    let fileIndex: FileIndex
    
    public typealias Errcase = FileStorage.Errcase
    
    /// 使用索引数据初始化目录对象。
    /// - Parameters:
    ///   - index: 来自数据库的文件索引（应为目录类型）。
    ///   - parent: 父路径（可选）。
    ///   - storage: 文件存储上下文。
    /// - Throws: 如果类型不匹配或索引无效，抛出错误。
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
        self.path = parent == nil ? .root : (parent! + index.name)
        self.createdAt = index.createdAt
        self.updatedAt = index.updatedAt
        self.storage = storage
        self.fileIndex = index
    }
}

public extension Directory {
    /// 是否为根目录。
    var isRoot: Bool { self.id == nil }
    
    /// 检查该目录是否存在（同步）。
    func isExist() -> Bool {
        if let id = self.id {
            return (try? FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first().wait()) != nil
        } else {
            return true
        }
    }
    
    /// 检查该目录是否存在（异步）。
    func isExist() async -> Bool {
        if let id = self.id {
            return (try? await FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first()) != nil
        } else {
            return true
        }
    }
    
    /// 获取目录下所有子项（文件和目录）的总大小。
    ///
    /// 该操作需要进行迭代遍历子项目大小进行计算，因此较为耗时。
    func getSize() -> EventLoopRes<Int64, FileStorage.Errcase> {
        subitems().wrapped
            .flatMapEach(on: storage.eventLoop) {
                $0.getSize().wrapped
            }
            .withError(Errcase.fetchDirectorySizeFailed)
            .map { sizes in
                sizes.reduce(0, +)
            }
    }
    
    /// 获取当前目录下的所有子项（文件与目录）
    ///
    /// - Returns: 第一层子项数组。
    func subitems() -> EventLoopRes<[any StorageEntry], Errcase> {
        __subitems(withDeleted: false)
    }
    
    /// 清空目录内容。
    ///
    /// - Parameter force: 是否强制删除，否则为软删除
    ///
    /// 进行软删除，则数据被标记为被删除，但并未实际删除，可进行再恢复(并不提供该 API)。
    /// 软删除是零拷贝轻量操作，不会进行任何文件系统操作
    ///
    /// - Warning: 若指定 force，则连同文件数据及文件索引都会一并从硬盘中删除，该操作无法撤销。
    /// 另外，删除一个目录，则连同其下的所有子目录和子文件都会一并删除，若指定了 force，该操作无法撤销，
    /// 您需要自己承担该风险。
    func empty(force: Bool = false) -> EventLoopRes<Void, Errcase> {
        __subitems(withDeleted: force).wrapped
            .flatMapEach(on: storage.eventLoop) {
                $0.delete(force: force).wrapped
            }
            .withError(Errcase.emptyDirectoryFailed)
    }
    
    /// 删除目录，可选择软删除或硬删除。
    ///
    /// - Parameter force: 若为 true，则从数据库和文件系统中物理删除 **所有子项**。
    ///
    /// 进行软删除，则数据被标记为被删除，但并未实际删除，可进行再恢复(并不提供该 API)。
    /// 软删除是零拷贝轻量操作，不会进行任何文件系统操作
    ///
    /// - Warning: 若指定 force，则连同文件数据及文件索引都会一并从硬盘中删除，该操作无法撤销。
    /// 另外，删除一个目录，则连同其下的所有子目录和子文件都会一并删除，若指定了 force，该操作无法撤销，
    /// 您需要自己承担该风险。
    func delete(force: Bool = false) -> EventLoopRes<Void, Errcase> {
        __delete(force: force)
    }
    
    /// 重命名该目录。
    ///
    /// 零拷贝轻量操作，不会进行任何文件系统操作
    ///
    /// - Parameter name: 新名称。
    ///
    /// - Returns: 更新后的目录对象。
    func rename(as name: String) -> EventLoopRes<Directory, Errcase> {
        __rename(as: name)
    }
    
    /// 将目录移动到指定目录下，支持改名。
    ///
    /// 零拷贝轻量操作，不会进行任何文件系统操作
    ///
    /// - Parameters:
    ///   - dir: 目标目录。
    ///   - name: 可选的新名称。
    ///
    /// - Returns: 更新后的目录对象。
    func move(to dir: Directory, as name: String? = nil) -> EventLoopRes<Directory, Errcase> {
        __move(to: dir, as: name)
    }
}

// MARK: - 内部实现

extension Directory {
    func __subitems(withDeleted: Bool = false) -> EventLoopRes<[any StorageEntry], Errcase> {
        
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
    
    func __delete(force: Bool = false) -> EventLoopRes<Void, Errcase> {
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
                                let path = FilePath("\(storage.storagePath)/\(try row.decode(String.self)).\(storage.fileExtension)")
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
    
    func __rename(as name: String) -> EventLoopRes<Directory, Errcase> {
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
    
    func __move(to dir: Directory, as name: String? = nil) -> EventLoopRes<Directory, Errcase> {
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
    /// 目录的调试描述信息。
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
