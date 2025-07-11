import AsyncAlgorithms
import NIOCore
import Foundation
import Fluent
import FluentKit
import ErrorHandle
import Cryptos
import NIOFileSystem
import NIOAdvanced
import Crypto
import DataConvertable

public typealias FileReadWriter = FileReader & FileWriter

/// 表示一个加密存储系统中的文件对象，包含元数据与读写操作接口。
///
/// 该文件类型并不储存任何真实数据，仅仅为文件句柄，因此非常轻量。
/// 你可以使用该实例对该文件进行诸如删除，重命名，打开，读写，关闭，移动等等操作。
///
/// #### 文件基本操作
///
/// 若你要创建一个文件，请参考 [FileStorage+Operations.swift](../FileStorage+Operations.swift) 文件中的 `createFile(...)` 函数
/// ``` swift
/// // 首先，提供各种参数创建一个 FileStorage 实例
/// let storage = FileStorage.new(...)
///
/// // 提供一个路径，文件将会创建在该路径下
/// // 注意，该路径为虚拟文件系统的路径，详情请见 StoragePath 类型
/// let path: StoragePath = "testing/example.txt"
///
/// // 在指定的路径下创建文件
/// // 你可以指定 withIntermediateDirectories: 参数为 true 以自动创建中间目录
/// // 否则，若中间目录不存在，将会抛出错误
/// let file = try await storage.createFile(at: path)
///
/// print(file.name)                // <-- print: example.txt
/// print(file.mimeType)            // <-- print: MimeType.plain "text/plain"
/// print(file.path)                // <-- print: testing/example.txt
/// print(file.size)                // <-- print: 0
/// print(file.isExist())           // <-- print: true
/// ```
///
/// 得到文件实例后，你可以对其重新命名:
/// ``` swift
/// let renamedFile = try await file.rename(as: "image.png")
///
/// print(renamedFile.name)         // <-- print: image.png
/// print(renamedFile.mimeType)     // <-- print: MimeType.png "image/png"
/// print(renamedFile.path)         // <-- print: testing/image.png
/// ```
///
/// 移动文件:
/// ``` swift
/// // 首先你需要有一个目标目录实例
/// // 如何得到一个目录实例，请见 Directory 的详细类型说明
/// let destination: Directory = ...
///
/// // 将文件移动到目标目录下
/// let movedFile = renamedFile.move(to: destination)
///
/// print(movedFile.path)           // <-- print: <目标目录的路径>/image.png
/// ```
///
/// 删除文件:
/// ``` swift
/// // 软删除文件，默认，极其轻量化操作，不会真正删除文件，仅标记为已删除
/// try await movedFile.delete()
/// // 或者，硬删除(破坏性操作)，这将直接从数据库及文件系统中彻底删除该文件数据，且无法撤销
/// try await movedFile.delete(force: true)
/// ```
///
/// #### 文件读写
///
/// 要对文件进行读写，首先需要打开该文件，以此读取或写入其中的数据，本类型提供:
/// * 打开文件仅用于读取
/// * 打开文件仅用于写
/// * 打开文件可用于读写
///
/// 打开文件用于只读:
/// ``` swift
/// // 首先获取文件实例
/// let file: File = ...
///
/// // 打开文件并读取其所有的数据
/// // 关于 `reader`，请见 `FileReader` 的详细类型说明
/// let fileData = try await file.withReader { reader in
///     reader.readData(part: .all)
/// }.get()
/// ```
///
/// 打开文件用于写:
/// ``` swift
/// // 准备好要写入的数据
/// let dataToWrite: ByteBuffer = ...
///
/// // 打开文件并将数据写入
/// // 关于 `writer`，请见 `FileWriter` 的详细类型说明
/// try await file.withWriter { writer in
///     writer.write(at: .begin(), bytes: dataToWrite)
/// }.get()
/// ```
///
/// 打开文件用于读写:
/// ``` swift
/// // 准备好要写入的数据
/// let dataToWrite: ByteBuffer = ...
///
/// // 打开文件将数据写入，之后将所有内容读出
/// // 关于 `readWriter`，请见 `FileReader` 和 `FileWriter` 的详细类型说明
/// // `FileReadWriter` 即为 `FileReader & FileWriter`
/// let fileData = try await file.withReadWriter { readWriter in
///     readWriter.write(at: .begin(), bytes: dataToWrite).flatMap {
///         readWriter.readData(part: .all)
///     }
/// }.get()
///
/// // `dataToWrite` 以及 `fileData` 应当是一样的
/// print(dataToWrite.readableBytes)
/// print(fileData.readableBytes)
/// ```
/// 你也可以自己控制 Reader Writer 以及 ReadWriter 的生命周期，分别使用这些方法替代即可：
///
/// 打开一个文件或获取其读句柄
/// ``` swift
/// let reader = try await file.openForRead()
///
/// // 进行一些操作
///
/// // 关闭该文件，务必进行此操作，泄漏的文件句柄会引发程序崩溃!
/// try await reader.close()
/// ```
///
/// 或只写:
/// ``` swift
/// let writer = try await file.openForWrite()
///
/// // ...
///
/// try await writer.close()
/// ```
///
/// 或读写:
/// ``` swift
/// let readWriter = try await file.openForReadWrite()
///
/// // ...
///
/// try await readWriter.close()
/// ```
///
/// - Warning: 手动控制 Reader Writer 以及 ReadWriter 的生命周期时，您必须
/// 自己在每次完成动作后手动调用 `.close()` 函数，包括出错的时候。因此，你可能需要
/// 像以下如此处理读写，确保每次句柄都能正常关闭。
/// ``` swift
/// let readWriter = try await file.openForReadAndWrite()
/// do {
///     let res = try await action(readWriter)
///
///     // 进行你的读写操作
///
///     try await readWriter.close()
///     return res
/// } catch {
///     try? await readWriter.close()
///     throw error
/// }
/// ```
@frozen
public struct File: StorageEntry, Sendable {
    /// 文件唯一标识符。
    public let id: UUID
    /// 文件名。
    public let name: String
    /// 文件的 MIME 类型。
    public let mimeType: MimeType
    /// 文件大小（字节）。
    @inlinable public var size: Int64 { fileIndex.size! }
    /// 文件在存储系统中的路径。
    public let path: StoragePath
    /// 文件创建时间。
    public let createdAt: Date
    /// 文件最后更新时间。
    @inlinable public var updatedAt: Date { fileIndex.updatedAt }
    
    /// 文件存储系统引用。
    public unowned let storage: FileStorage
    
    public typealias Errcase = FileStorage.Errcase
    
    @usableFromInline
    let fileIndex: FileIndex
    
    /// 通过 FileIndex 创建 File 实例。
    /// - Parameters:
    ///   - index: 索引数据库中的文件记录。
    ///   - parent: 父目录路径。
    ///   - storage: 文件存储系统。
    /// - Throws: 如果索引类型不为文件或缺少必要信息，抛出错误。
    @inlinable
    init(
        from index: FileIndex,
        parent: StoragePath,
        storage: FileStorage
    ) throws(BscError<Errcase>) {
        guard index.type == .file else { throw Errcase.getFileFailed.d("目标并非是一个文件，而是 \(index.type)") }
        guard let mimeType = index.mimeType else { throw Errcase.getFileFailed.d("文件 mime-type 未找到") }
        
        self.id = try required(throws: Errcase.getFileFailed, "获取文件 ID 失败") {
            try index.requireID()
        }
        
        self.name = index.name
        self.mimeType = mimeType
        self.path = parent + index.name
        self.createdAt = index.createdAt
        self.storage = storage
        self.fileIndex = index
    }
}

public extension File {
    /// 打开文件并传入只读句柄执行异步操作。
    ///
    /// - Parameters:
    ///     - action: 传入只读句柄，执行自定义动作
    /// - Returns: 本次自定义动作的结果，或抛出错误
    @inlinable
    func withReader<T, G>(_ action: @escaping @Sendable (FileReader) -> EventLoopResult<T, G>) -> EventLoopRes<T, Errcase> where T: Sendable {
        __withReader(action)
    }
    
    /// 打开文件并传入只写句柄执行异步操作。
    ///
    /// - Parameters:
    ///     - action: 传入只写句柄，执行自定义动作
    /// - Returns: 本次自定义动作的结果，或抛出错误
    @inlinable
    func withWriter<T, G>(_ action: @escaping @Sendable (FileWriter) -> EventLoopResult<T, G>) -> EventLoopRes<T, Errcase> where T: Sendable {
        __withWriter(action)
    }
    
    /// 打开文件并传入读写句柄执行异步操作。
    ///
    /// - Parameters:
    ///     - action: 传入只写句柄，执行自定义动作
    /// - Returns: 本次自定义动作的结果，或抛出错误
    @inlinable
    func withReadWriter<T, G>(_ action: @escaping @Sendable (FileReadWriter) -> EventLoopResult<T, G>) -> EventLoopRes<T, Errcase> where T: Sendable {
        __withReadWriter(action)
    }
}

public extension File {
    /// 打开只读文件句柄。
    ///
    /// - Returns: 文件的只读句柄，请见 `FileReader` 的详细类型说明
    ///
    /// - Warning: 手动控制 Reader 的生命周期时，您必须
    /// 自己在每次完成动作后手动调用 `.close()` 函数，包括出错的时候。因此，你可能需要
    /// 像以下如此处理读写，确保每次句柄都能正常关闭。
    /// ``` swift
    /// let reader = try await file.openForRead().get()
    /// do {
    ///     let res = try await action(reader).get()
    ///
    ///     // 进行你的读操作
    ///
    ///     try await reader.close()
    ///     return res
    /// } catch {
    ///     try? await reader.close()
    ///     throw error
    /// }
    /// ```
    @inlinable
    func openForRead() async -> Res<FileReader, Errcase> {
        await __openForRead()
    }
    
    /// 打开只写文件句柄。
    ///
    /// - Returns: 文件的只写句柄，请见 `FileWriter` 的详细类型说明
    ///
    /// - Warning: 手动控制 Writer 的生命周期时，您必须
    /// 自己在每次完成动作后手动调用 `.close()` 函数，包括出错的时候。因此，你可能需要
    /// 像以下如此处理读写，确保每次句柄都能正常关闭。
    /// ``` swift
    /// let writer = try await file.openForWrite().get()
    /// do {
    ///     let res = try await action(writer).get()
    ///
    ///     // 进行你的写操作
    ///
    ///     try await writer.close()
    ///     return res
    /// } catch {
    ///     try? await writer.close()
    ///     throw error
    /// }
    /// ```
    @inlinable
    func openForWrite() async -> Res<FileWriter, Errcase> {
        await __openForWrite()
    }
    
    /// 打开读写文件句柄。
    ///
    /// - Returns: 文件的读写句柄，请见 `FileReadWriter`(`FileReader & FileWriter`) 的详细类型说明
    ///
    /// - Warning: 手动控制 ReadWriter 的生命周期时，您必须
    /// 自己在每次完成动作后手动调用 `.close()` 函数，包括出错的时候。因此，你可能需要
    /// 像以下如此处理读写，确保每次句柄都能正常关闭。
    /// ``` swift
    /// let readWriter = try await file.openForReadAndWrite().get()
    /// do {
    ///     let res = try await action(readWriter).get()
    ///
    ///     // 进行你的读写操作
    ///
    ///     try await readWriter.close()
    ///     return res
    /// } catch {
    ///     try? await readWriter.close()
    ///     throw error
    /// }
    /// ```
    @inlinable
    func openForReadAndWrite() async -> Res<FileReadWriter, Errcase> {
        await __openForReadAndWrite()
    }
}

public extension File {
    /// 同步判断文件是否存在。
    func isExist() -> Bool {
        (try? FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first().wait()) != nil
    }
    
    /// 异步判断文件是否存在。
    func isExist() async -> Bool {
        (try? await FileIndex.query(on: storage.indexDatabase).filter(\.$id == id).first()) != nil
    }
    
    /// 获取文件大小。
    @inlinable
    func getSize() -> EventLoopRes<Int64, FileStorage.Errcase> {
        storage.eventLoop.makeSucceededResult(size)
    }
    
    /// 删除该文件，可选择软删除或硬删除。
    ///
    /// - Parameter force: 若为 true，则从数据库和文件系统中物理删除文件及文件数据。
    ///
    /// 进行软删除，则数据被标记为被删除，但并未实际删除，可进行再恢复(并不提供该 API)。
    /// 软删除是零拷贝轻量操作，不会进行任何文件系统操作
    ///
    /// - Warning: 若指定 force，则连同文件数据及文件索引都会一并从硬盘中删除，该操作无法撤销，
    /// 您需要自己承担该风险。
    @inlinable
    func delete(force: Bool = false) -> EventLoopRes<Void, Errcase> {
        __delete(force: force)
    }
    
    /// 重命名该文件。
    ///
    /// 零拷贝轻量操作，不会进行任何文件系统操作
    ///
    /// - Parameter name: 新名称。
    ///
    /// - Returns: 更新后的文件对象。
    @inlinable
    func rename(as name: String) -> EventLoopRes<File, Errcase> {
        fileIndex.name = name
        fileIndex.mimeType = name.fileExtension == nil ? .unknow : .init(fileExtension: name.fileExtension!)
        return fileIndex.update(on: storage.indexDatabase)
            .withError(Errcase.renameFileFailed, "数据库更新失败")
            .flatMapThrowing
        { () throws(BscError<Errcase>) in
            try required(throws: Errcase.renameFileFailed, "未知错误") {
                try .init(from: fileIndex, parent: self.path.parent, storage: storage)
            }
        }
    }
    
    /// 将目文件动到指定目录下，支持改名。
    ///
    /// 零拷贝轻量操作，不会进行任何文件系统操作
    ///
    /// - Parameters:
    ///   - dir: 目标目录。
    ///   - name: 可选的新名称。
    ///
    /// - Returns: 更新后的文件对象。
    func move(to dir: Directory, as name: String? = nil) -> EventLoopRes<File, Errcase> {
        fileIndex.$parent.id = dir.fileIndex.isRoot ? nil : dir.id
        if let name = name {
            fileIndex.name = name
        }
        return fileIndex.update(on: storage.indexDatabase)
            .withError(Errcase.moveFileFailed, "数据库更新失败")
            .flatMapThrowing
        { () throws(BscError<Errcase>) in
            try required(throws: Errcase.moveFileFailed, "未知错误") {
                try .init(from: fileIndex, parent: self.path.parent, storage: storage)
            }
        }
    }
}

// MARK: - 内部实现

extension File {
    @inlinable
    func __withReader<T, G>(_ action: @escaping @Sendable (FileReader) -> EventLoopResult<T, G>) -> EventLoopRes<T, Errcase> where T: Sendable {
        storage.eventLoop.makeFutureWithTask {
            let reader = try await openForRead().get()
            do {
                let res = try await action(reader).get()
                try await reader.close()
                return res
            } catch {
                try? await reader.close()
                throw error
            }
        }.withError(Errcase.openFileFailed)
    }
    
    /// 打开文件并传入只写句柄执行异步操作。
    @inlinable
    func __withWriter<T, G>(_ action: @escaping @Sendable (FileWriter) -> EventLoopResult<T, G>) -> EventLoopRes<T, Errcase> where T: Sendable {
        storage.eventLoop.makeFutureWithTask {
            let writer = try await openForWrite().get()
            do {
                let res = try await action(writer).get()
                try await writer.close()
                return res
            } catch {
                try? await writer.close()
                throw error
            }
        }.withError(Errcase.openFileFailed)
    }
    
    /// 打开文件并传入读写句柄执行异步操作。
    @inlinable
    func __withReadWriter<T, G>(_ action: @escaping @Sendable (FileReadWriter) -> EventLoopResult<T, G>) -> EventLoopRes<T, Errcase> where T: Sendable {
        storage.eventLoop.makeFutureWithTask {
            let readWriter = try await openForReadAndWrite().get()
            do {
                let res = try await action(readWriter).get()
                try await readWriter.close()
                return res
            } catch {
                try? await readWriter.close()
                throw error
            }
        }.withError(Errcase.openFileFailed)
    }
    
    @usableFromInline
    func __openForRead() async -> Res<FileReader, Errcase> {
        await .async { () throws(BscError<Errcase>) in
            let (fileCrypto, key, filePath) = try await required(throws: Errcase.openFileFailed, "获取文件信息失败") {
                try await makeFileHandleParas()
            }
            let fileHandler = try await required(throws: File.Errcase.openFileFailed) {
                try await FileSystem.shared.openFile(forReadingAt: filePath, options: .init())
            }
            return Reader(
                fileIndex: fileIndex,
                fileCrypto: fileCrypto,
                key: key,
                filePath: path,
                fileRealPath: filePath,
                fileHandler: fileHandler,
                storage: storage
            )
        }
    }
    
    @usableFromInline
    func __openForWrite() async -> Res<FileWriter, Errcase> {
        await .async { () throws(BscError<Errcase>) in
            let (fileCrypto, key, filePath) = try await required(throws: Errcase.openFileFailed, "获取文件信息失败") {
                try await makeFileHandleParas()
            }
            let fileHandler = try await required(throws: File.Errcase.openFileFailed) {
                try await FileSystem.shared.openFile(forWritingAt: filePath, options: .modifyFile(createIfNecessary: false))
            }
            return Writer(
                fileIndex: fileIndex,
                fileCrypto: fileCrypto,
                key: key,
                filePath: path,
                fileRealPath: filePath,
                fileHandler: fileHandler,
                storage: storage
            )
        }
    }
    
    @usableFromInline
    func __openForReadAndWrite() async -> Res<FileReadWriter, Errcase> {
        await .async { () throws(BscError<Errcase>) in
            let (fileCrypto, key, filePath) = try await required(throws: Errcase.openFileFailed, "获取文件信息失败") {
                try await makeFileHandleParas()
            }
            let fileHandler = try await required(throws: File.Errcase.openFileFailed) {
                try await FileSystem.shared.openFile(forReadingAndWritingAt: filePath, options: .modifyFile(createIfNecessary: false))
            }
            return ReaderAndWriter(
                fileIndex: fileIndex,
                fileCrypto: fileCrypto,
                key: key,
                filePath: path,
                fileRealPath: filePath,
                fileHandler: fileHandler,
                storage: storage
            )
        }
    }
    
    @usableFromInline
    func __delete(force: Bool = false) -> EventLoopRes<Void, Errcase> {
        if force {
            return storage.db.eventLoop.makeFutureWithTask {
                try await getRealFilePath(withDeleted: true).0
            }.withError(Errcase.deleteFileFailed, "获取文件路径失败")
            .flatMap { filePath in
                fileIndex.delete(force: true, on: storage.db)
                    .map { filePath }
                    .withError(Errcase.deleteFileFailed, "数据库删除记录失败")
            }.flatMap { filePath in
                storage.db.eventLoop.makeFutureWithTask {
                    try await FileSystem.shared.removeItem(at: filePath)
                }.withError(Errcase.deleteFileFailed, "从文件系统删除加密文件失败")
            }
        } else {
            
            let fileId: UUID
            
            do {
                fileId = try fileIndex.requireID()
            } catch {
                return storage.db.eventLoop.makeFailedResult(Errcase.deleteFileFailed.d("获取文件 ID 失败").subErr(error))
            }
            
            return FileCrypto.query(on: storage.db)
                .filter(\.$id == fileId)
                .delete(force: false)
                .withError(Errcase.deleteFileFailed, "数据库 \(FileCrypto.name) 软删除失败")
                .flatMap {
                    fileIndex.delete(force: false, on: storage.db)
                        .withError(Errcase.deleteFileFailed, "数据库 \(FileIndex.name) 软删除记录失败")
                }
        }
    }
}

extension File {
    
    @frozen
    public enum FileParaFetchErrcase: String, ErrList {
        /// 数据库查询失败。
        case databaseFailed = "数据库查询失败"
        /// 文件不存在。
        case fileNotExist = "文件不存在"
        /// 派生密钥生成失败。
        case keyDeriveFailed = "派生密钥生成失败"
    }
    
    /// 获取加密文件的实际路径与关联的 FileCrypto 对象。
    /// - Parameter withDeleted: 是否允许从软删除记录中读取。
    @usableFromInline
    func getRealFilePath(withDeleted: Bool = false) async throws(BscError<FileParaFetchErrcase>) -> (FilePath, FileCrypto) {
        
        let qc: QueryBuilder<FileCrypto>
        
        if withDeleted {
            qc = FileCrypto.query(on: storage.indexDatabase)
                .filter(\.$id == id)
                .withDeleted()
        } else {
            qc = FileCrypto.query(on: storage.indexDatabase)
                .filter(\.$id == id)
        }
        
        guard
            let fileCrypto = try await qc.first()
                .withError(FileParaFetchErrcase.databaseFailed)
                .get()
        else {
            throw FileParaFetchErrcase.fileNotExist.d(self.path.string)
        }
         
        return (
            .init("\(self.storage.storagePath)/\(fileCrypto.storageKey).\(storage.fileExtension)"),
            fileCrypto
        )
    }
    
    /// 构造打开加密文件所需的参数：文件路径、FileCrypto 和派生密钥。
    @inlinable
    func makeFileHandleParas() async throws(BscError<FileParaFetchErrcase>) -> (
        FileCrypto, Crypto.Symm.Key, FilePath
    ) {
        let (filePath, fileCrypto) = try await getRealFilePath()
        
        // 创建派生密钥
        let key = try required(throws: FileParaFetchErrcase.keyDeriveFailed) {
            try self.storage.masterKey.derive(salt: fileCrypto.salt, info: fileCrypto.sharedData).get()
        }
        
        return (fileCrypto, key, filePath)
    }
}

extension File: CustomStringConvertible {
    /// 返回文件的简要描述信息。
    @inlinable
    public var description: String {
        """
        File (
            id: \(id.uuidString)
            name: \(name)
            mimeType: \(mimeType.rawValue)
            size: \(size)
            path: \(path.string)
            createdAt: \(createdAt)
            updatedAt: \(updatedAt)
        )
        """
    }
}
