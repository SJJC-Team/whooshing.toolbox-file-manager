import Fluent
import ErrorHandle
import NIOCore
import NIOFileSystem

public extension FileStorage {
    enum Err: String, ErrList {
        public var domain: String { "woo.sys.file.storage.err" }
        case databaseInitFailed = "数据库连接失败"
        case fileSystemInitFailed = "文件系统初始化失败"
        case fileOpenFailed = "文件打开失败"
        case directoryCreateFailed = "文件夹创建失败"
        case unknow = "未知错误"
    }
}

public extension FileStorage {
    
    func newDirectory(
        at path: StoragePath,
        withIntermediateDirectories createIfNeed: Bool = false,
        slience: Bool = false
    ) -> EventLoopFuture<Directory> {
        getParent(at: path, withIntermediateDirectories: createIfNeed, slience: slience).flatMap { parent in
            // 检查要创建的目录是否已经存在
            self.getChild(at: parent, name: path.last!).flatMap { fileIndex in
                if let existedIndex = fileIndex {
                    // 要创建的目录已经存在，若指定 slience 则不做任何事，否则抛出错误
                    if slience {
                        return self.eventLoop.makeSucceededFuture(existedIndex)
                    } else {
                        return self.eventLoop.makeFailedFuture(Err.directoryCreateFailed.d("目录 \"\(path)\" 已存在", 16026))
                    }
                } else {
                    // 要创建的目录不存在，创建新目录
                    return self.newDirIndex(parent: parent, path: path)
                }
            }
        }.flatMapThrowing { fileIndex in
            try Directory(from: fileIndex, parent: path.parent, storage: self)
        }
    }
    
    func getDirectory(at path: StoragePath) -> EventLoopFuture<Directory> {
        get(at: path)
    }
    
}


extension FileStorage {
    
    func get<T>(at path: StoragePath) -> EventLoopFuture<T> where T: StorageEntry {
        findEntry(at: path) {
            guard let fileIndex = $0.index else {
                return self.eventLoop.makeFailedFuture(Err.fileOpenFailed.d("\"\(path)\" 文件或目录不存在", 16021))
            }
            return self.eventLoop.makeSucceededFuture(fileIndex)
        }.flatMapThrowing { fileIndex in
            try T.factory(from: fileIndex, parent: path.parent, storage: self)
        }
    }
    
    typealias ActionContext = (index: FileIndex?, path: StoragePath, parent: FileIndex)
    
    func findEntry(
        at path: StoragePath,
        action: @escaping @Sendable (ActionContext) -> EventLoopFuture<FileIndex>
    ) -> EventLoopFuture<FileIndex> {
        
        let curPath = StoragePath.root
        var r = self.eventLoop.makeSucceededFuture((self.rootDirIndex, curPath))
        
        for component in path {
            r = r.flatMap { fileIndex, path in
                let curPath = path + component
                return self.getChild(at: fileIndex, name: component)
                    .flatMap { action(($0, curPath, fileIndex)) }
                    .flatMap
                { fileIndex in
                    self.eventLoop.makeSucceededFuture((fileIndex, curPath))
                }
            }
        }
        
        return r.map { $0.0 }
    }
    
    func getChild(
        at index: FileIndex,
        name: String
    ) -> EventLoopFuture<FileIndex?> {
        FileIndex.query(on: self.indexDatabase)
            .filter(\.$parent.$id == index.id)
            .filter(\.$name == name)
            .first()
    }
    
    func getParent(
        at path: StoragePath,
        withIntermediateDirectories createIfNeed: Bool = false,
        slience: Bool = false
    ) -> EventLoopFuture<FileIndex> {
        guard !path.isRoot else { preconditionFailure("不允许创建系统根") }
        let r: EventLoopFuture<FileIndex>
        if path.parent.isRoot {
            // 在根目录下创建文件夹
            r = self.eventLoop.makeSucceededFuture(self.rootDirIndex)
        } else {
            // 非根目录下创建文件夹，需要找到要创建目录的父目录
            r = findEntry(at: path.parent) { index, path, parent in
                if let fileIndex = index {
                    // 该级目录存在
                    return self.eventLoop.makeSucceededFuture(fileIndex)
                } else {
                    // 该级目录不存在
                    if !createIfNeed {
                        // 若用户指定 createIfNeed 为 false，直接抛出错误
                        return self.eventLoop.makeFailedFuture(Err.fileOpenFailed.d("\"\(path)\" 文件或目录不存在", 16021))
                    }
                    // 为该级创建新目录，因为用户指定了 createIfNeed
                    return self.newDirIndex(parent: parent, path: path)
                }
            }
        }
        
        return r
    }
    
    @Sendable func newDirIndex(parent: FileIndex?, path: StoragePath) -> EventLoopFuture<FileIndex> {
        let new = FileIndex()
        new.id = .init()
        new.parent = parent
        new.type = .directory
        new.mimeType = nil
        new.name = path.last!
        return new.save(on: self.indexDatabase).map { new }
    }
}
