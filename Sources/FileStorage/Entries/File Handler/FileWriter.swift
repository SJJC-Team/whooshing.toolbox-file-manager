import NIOFileSystem
import NIOConcurrencyHelpers
import NIOCore
import NIOAdvanced
import ErrorHandle
import AsyncAlgorithms
import Cryptos
import FluentKit
import Foundation

/// 表示文件中的字节位置索引。
///
/// - `begin(of:)`：从文件开头开始的偏移量，默认从 0 开始。
/// - `end(of:)`：从文件结尾开始的偏移量，默认从 0 开始。
@frozen
public enum ByteIndex: Sendable {
    case begin(of: Int64 = 0)
    case end(of: Int64 = 0)
}

/// 文件写入方式。
///
/// - `insert`：在指定位置插入数据，后续内容顺移。
/// - `replace`：在指定位置替换数据，覆盖原有内容。
@frozen
public enum WriteMethod: Sendable {
    case insert
    case replace
}

/// 文件写入操作的协议，继承自 `FileContentHandler`，定义了写入、插入、替换和删除字节的方法。
public protocol FileWriter: FileContentHandler {
    /// 在指定位置以给定方式写入字节缓冲区数据。
    ///
    /// - Parameters:
    ///   - at: 字节索引位置。
    ///   - bytes: 要写入的字节缓冲区。
    ///   - method: 写入方式，插入或替换。
    ///
    /// - Returns: 表示写入结果的异步事件循环结果，成功或带错误信息。
    ///
    /// 该写入操作为原子操作，保证整体执行完成。若出错，则保证整体不执行，原数据不受任何影响
    func write(at: ByteIndex, bytes: Data, method: WriteMethod) async throws(File.Errcase.ErrType)
    
    /// 从异步字节流通道在指定位置以给定方式写入数据。
    ///
    /// - Parameters:
    ///   - at: 字节索引位置。
    ///   - from: 异步字节缓冲区通道。
    ///   - method: 写入方式，插入或替换。
    ///
    /// - Returns: 表示写入结果的异步事件循环结果。
    ///
    /// 该写入操作带有 BackPressure 功能，会自动阻塞提供者的数据流，防止内存堆砌
    ///
    /// 该写入操作为原子操作，保证整体执行完成。若出错，则保证整体不执行，原数据不受任何影响
    func write(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>, method: WriteMethod) async throws(File.Errcase.ErrType)
    
    /// 在指定位置插入字节缓冲区数据。
    ///
    /// - Parameters:
    ///   - at: 插入位置。
    ///   - bytes: 要插入的数据。
    ///
    /// - Returns: 异步事件循环结果。
    ///
    /// 该写入操作为原子操作，保证整体执行完成。若出错，则保证整体不执行，原数据不受任何影响
    func insert(at: ByteIndex, bytes: Data) async throws(File.Errcase.ErrType)
    
    /// 在指定位置替换字节缓冲区数据。
    ///
    /// - Parameters:
    ///   - at: 替换位置。
    ///   - bytes: 替换的新数据。
    ///
    /// - Returns: 异步事件循环结果。
    ///
    /// 该写入操作为原子操作，保证整体执行完成。若出错，则保证整体不执行，原数据不受任何影响
    func replace(at: ByteIndex, bytes: Data) async throws(File.Errcase.ErrType)
    
    /// 从异步字节流通道在指定位置插入数据。
    ///
    /// - Parameters:
    ///   - at: 插入位置。
    ///   - from: 异步字节缓冲区通道。
    ///
    /// - Returns: 异步事件循环结果。
    ///
    /// 该写入操作带有 BackPressure 功能，会自动阻塞提供者的数据流，防止内存堆砌
    ///
    /// 该写入操作为原子操作，保证整体执行完成。若出错，则保证整体不执行，原数据不受任何影响
    func insert(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>) async throws(File.Errcase.ErrType)
    
    /// 从异步字节流通道在指定位置替换数据。
    ///
    /// - Parameters:
    ///   - at: 替换位置。
    ///   - from: 异步字节缓冲区通道。
    ///
    /// - Returns: 异步事件循环结果。
    ///
    /// 该写入操作为原子操作，保证整体执行完成。若出错，则保证整体不执行，原数据不受任何影响
    func replace(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>) async throws(File.Errcase.ErrType)
    
    /// 删除指定范围内的字节。
    /// 
    /// - Parameter in: 要删除的字节范围（开区间）。
    /// - Returns: 异步事件循环结果。
    ///
    /// 该写入操作为原子操作，保证整体执行完成。若出错，则保证整体不执行，原数据不受任何影响
    func remove(in: Range<Int64>) async throws(File.Errcase.ErrType)
    
    /// 删除指定范围内的字节。
    ///
    /// - Parameter in: 要删除的字节范围（闭区间）。
    /// - Returns: 异步事件循环结果。
    ///
    /// 该写入操作为原子操作，保证整体执行完成。若出错，则保证整体不执行，原数据不受任何影响
    func remove(in: ClosedRange<Int64>) async throws(File.Errcase.ErrType)
    
    func write(at: ByteIndex, bytes: Data, method: WriteMethod) -> EventLoopRes<Void, File.Errcase>
    func write(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>, method: WriteMethod) -> EventLoopRes<Void, File.Errcase>
    func insert(at: ByteIndex, bytes: Data) -> EventLoopRes<Void, File.Errcase>
    func replace(at: ByteIndex, bytes: Data) -> EventLoopRes<Void, File.Errcase>
    func insert(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>) -> EventLoopRes<Void, File.Errcase>
    func replace(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>) -> EventLoopRes<Void, File.Errcase>
    func remove(in range: Range<Int64>) -> EventLoopRes<Void, File.Errcase>
    func remove(in range: ClosedRange<Int64>) -> EventLoopRes<Void, File.Errcase>
}

public extension FileWriter {
    @inlinable
    func write(at: ByteIndex, bytes: Data, method: WriteMethod = .replace) async throws(File.Errcase.ErrType) {
        switch method {
        case .insert: return try await insert(at: at, bytes: bytes)
        case .replace: return try await replace(at: at, bytes: bytes)
        }
    }
    
    @inlinable
    func write(at: ByteIndex, from: AsyncThrowingChannel<Data, Error>, method: WriteMethod = .replace) async throws(File.Errcase.ErrType) {
        switch method {
        case .insert: return try await insert(at: at, from: from)
        case .replace: return try await replace(at: at, from: from)
        }
    }
    
    @inlinable
    func insert(at: ByteIndex, bytes: Data) async throws(File.Errcase.ErrType) {
        try await insert(at: at, from: makeChannel(with: bytes))
    }
    
    @inlinable
    func replace(at: ByteIndex, bytes: Data) async throws(File.Errcase.ErrType) {
        try await replace(at: at, from: makeChannel(with: bytes))
    }
    
    @inlinable
    internal func makeChannel(with bytes: Data) -> AsyncThrowingChannel<Data, Error> {
        let res = AsyncThrowingChannel<Data, Error>()
        Task {
            await res.send(bytes)
            res.finish()
        }
        return res
    }
}

extension ByteIndex {
    @inlinable
    internal func index(fileSize: Int64) -> Int64 {
        switch self {
        case .begin(of: let i):
            return i
        case .end(of: let i):
            return fileSize - i
        }
    }
}

protocol __FileWriter: FileWriter, __FileContentHandler {
    associatedtype WritableFileHandle: WritableFileHandleProtocol
    var fileWriteHandler: WritableFileHandle { get }
}

extension __FileWriter {
    @inlinable
    var fileWriteHandler: WritableFileHandle {
        guard let handler = self.fileHandler as? WritableFileHandle else {
            fatalError("FileHandler 配置不正确")
        }
        return handler
    }
    
    @inlinable
    func insert(at index: ByteIndex, from channel: AsyncThrowingChannel<Data, Error>) async throws(File.Errcase.ErrType) {
        let insertIndex = index.index(fileSize: fileIndex.size!)
        let (_, dbOperation) = try await backPressureInsert(at: insertIndex, from: channel, removeLater: false)
        
        try await storage.db.atrans { db throws(File.Errcase.ErrType) in
            try await dbOperation(db)
        }
    }
    
    @inlinable
    func replace(at index: ByteIndex, from channel: AsyncThrowingChannel<Data, Error>) async throws(File.Errcase.ErrType) {
        let insertIndex = index.index(fileSize: fileIndex.size!)
        
        let op1 = try await backPressureInsert(at: insertIndex, from: channel, removeLater: true)
        let op2 = try await removeBytes(in: insertIndex..<(min(insertIndex + op1.appendRes.readBytes, fileIndex.size!)), willInsertNext: true)
        
        try await storage.db.atrans { db throws(File.Errcase.ErrType) in
            try await op2(db)
            try await op1.dbOperation(db)
        }
    }
    
    @inlinable
    func remove(in range: Range<Int64>) async throws(File.Errcase.ErrType) {
        let dbOperation = try await removeBytes(in: range, willInsertNext: false)
        try await storage.db.atrans { db throws(File.Errcase.ErrType) in
            try await dbOperation(db)
        }
    }
    
    @inlinable
    func remove(in range: ClosedRange<Int64>) async throws(File.Errcase.ErrType) {
        try await remove(in: .init(range))
    }
}

@frozen
public enum FileWriterError: String, ErrList {
    case separateFilePartFailed = "文件数据片分割失败"
    case appendDataFailed = "向文件追加数据时失败"
}

enum FileWriterSeparationResult {
    case noNeed(part: FilePart)
    case separated(left: FilePart, right: FilePart)
}

enum RemoveBytesSeparationResult {
    case eof
    case notEof(FileWriterSeparationResult)
}

extension __FileWriter {
    /// 将提供的数据插入到某个位置。
    /// 该函数会进行数据写入，但不会更新数据库中的指针位置，数据库操作将会作为返回值返回，需要调用者自行执行数据库操作
    @usableFromInline
    func backPressureInsert(
        at byteStartIndex: Int64,
        from channel: AsyncThrowingChannel<Data, Error>,
        removeLater: Bool
    ) async throws(BscError<File.Errcase>) -> (
        appendRes: DataAppendingResult,
        dbOperation: @Sendable (FileStorage.PGDatabase) async throws(File.Errcase.ErrType) -> Void
    ) {
        guard byteStartIndex <= fileCrypto.encryptedSize, byteStartIndex >= 0 else {
            throw File.Errcase.writeFileFailed.d("插入索引不正确，预期最大为 \(fileCrypto.encryptedSize) 且 >= 0，却得到 \(byteStartIndex)")
        }
        
        // 将数据直接写入到加密文件中
        let appendRes = try await required(throws: File.Errcase.writeFileFailed, "将数据写入到文件中时失败，\(fileRealPath)") {
            try await appendChannelDataAndEncryptToFile(fileWriteHandler, tagStart: fileCrypto.lastTag, channel: channel)
        }
        
        guard appendRes.readBytes > 0 else {
            return (appendRes, { _ in })
        }
        
        let fileId = try required(throws: File.Errcase.writeFileFailed, "获取文件 ID 失败") {
            try fileIndex.requireID()
        }
        
        let separateTask: @Sendable (FileStorage.PGDatabase) async throws -> Void
        
        if byteStartIndex == fileIndex.size! {
            // 追加到文件最后
            // 查询最后一个 filePart 记录，以用于追加
            // 若 last 不存在，则表示该文件是空的
            let last = try await required(throws: File.Errcase.writeFileFailed, "数据库检索失败，\(filePath)") {
                try await FilePart.query(on: storage.db)
                    .filter(\.$fileIndex.$id == fileIndex.requireID())
                    .sort(\.$byteEnd, .descending)
                    .sort(\.$byteStart, .descending)
                    .first()
            }
            
            // 创建新的 Part 记录，并填入相应的参数
            let newPart = FilePart(
                fileIndexId: fileId,
                tagStart: fileCrypto.lastTag,
                byteStart: last?.byteEnd ?? 0,
                byteEnd: (last?.byteEnd ?? 0) + appendRes.readBytes,
                byteHeadIgnore: 0,
                byteTailIgnore: 0,
                encryptedStart: appendRes.lastEncryptedSize,
                encryptedEnd: appendRes.lastEncryptedSize + appendRes.writtenBytes
            )
            
            separateTask = { db in
                try await newPart.save(on: db)
            }
        } else {
            // 进行数据插入，而非追加
            // 先对影响块进行分割
            let separateResult = try await required(throws: File.Errcase.writeFileFailed, "文件块分割失败，\(filePath)") {
                try await separateFilePart(from: byteStartIndex)
            }
            
            // 判断分割结果，并应用分割
            let markPart: FilePart
            let __task: @Sendable (FileStorage.PGDatabase) async throws -> Void
            
            switch separateResult {
            case .noNeed(part: let part):
                markPart = part
                // 无需分割
                __task = { db in
                    if removeLater {
                        return ()
                    }
                    // 更新该插入点之后的所有数据库记录，使其均向后偏移该插入的字节量
                    return try await appendRemainingPart(
                        with: appendRes.readBytes,
                        greaterEqualThan: markPart.byteStart,
                        in: db,
                        fileId: fileId
                    )
                }
            case .separated(left: let left, right: let right):
                markPart = right
                // 需要分割，将新割出的插入到数据库中，并更新被割出的原 Part
                __task = { db in
                    if removeLater {
                        return ()
                    }
                    try await left.save(on: db)
                    try await right.update(on: db)
                    // 更新该插入点之后的所有数据库记录，使其均向后偏移该插入的字节量
                    return try await appendRemainingPart(
                        with: appendRes.readBytes,
                        greaterEqualThan: markPart.byteStart,
                        in: db,
                        fileId: fileId
                    )
                }
            }
            
            let fileId = try required(throws: File.Errcase.writeFileFailed, "获取文件 ID 失败，\(filePath)") {
                try fileIndex.requireID()
            }
            
            // 将数据库查询任务记录在一个闭包中，目前不执行，在最后使用 transaction 执行确保原子性
            separateTask = { db in
                try await __task(db)
                // 插入新的 FilePart 到数据库中
                try await FilePart(
                    fileIndexId: fileId,
                    tagStart: fileCrypto.lastTag,
                    byteStart: markPart.byteStart,
                    byteEnd: markPart.byteStart + appendRes.readBytes,
                    byteHeadIgnore: 0,
                    byteTailIgnore: 0,
                    encryptedStart: appendRes.lastEncryptedSize,
                    encryptedEnd: appendRes.lastEncryptedSize + appendRes.writtenBytes
                ).save(on: db)
            }
        }
        
        return (
            appendRes,
            { db throws(File.Errcase.ErrType) in
                try await required(throws: File.Errcase.writeFileFailed, "数据库操作失败，\(filePath)") {
                    try await separateTask(db)
                    // 更新加密数据的信息
                    fileCrypto.lastTag = appendRes.lastTag
                    fileCrypto.encryptedSize += appendRes.writtenBytes
                    try await fileCrypto.update(on: db)
                    fileIndex.size = fileIndex.size! + appendRes.readBytes
                    return try await fileIndex.update(on: db)
                }
            }
        )
    }
    
    /// 从文件中移除某个区间的字节数据。
    /// 该函数不会进行任何文件系统操作，也不会更新数据库中的指针位置，数据库操作将会作为返回值返回，需要调用者自行执行数据库操作
    @usableFromInline
    func removeBytes(
        in range: Range<Int64>,
        willInsertNext: Bool
    ) async throws(BscError<File.Errcase>) -> (@Sendable (FileStorage.PGDatabase) async throws(File.Errcase.ErrType) -> Void) {
        guard
            range.lowerBound <= fileCrypto.encryptedSize,
            range.lowerBound >= 0,
            range.upperBound <= fileCrypto.encryptedSize,
            range.upperBound >= 0
        else {
            throw File.Errcase.removeFileDataFailed.d("提供的索引不正确，文件数据范围为 \"0..<\(fileCrypto.encryptedSize)\"，却得到 \"\(range)\"，\(filePath)")
        }
        
        guard !range.isEmpty else { return { _ in () } }
        
        let removingBytes = range.upperBound - range.lowerBound
        
        let task = try await __removeBytes(in: range, willInsertNext: willInsertNext)
        
        return { db in
            try await required(throws: File.Errcase.removeFileDataFailed, "数据库操作失败，\(filePath)") {
                try await task(db)
                // 更新加密数据的信息
                fileCrypto.encryptedSize -= removingBytes
                try await fileCrypto.update(on: db)
                fileIndex.size! -= range.upperBound - range.lowerBound
                return try await fileIndex.update(on: db)
            }
        }
    }
    
}
 
extension __FileWriter {
    func __removeBytes(
        in range: Range<Int64>,
        willInsertNext: Bool
    ) async throws(BscError<File.Errcase>) -> @Sendable (FileStorage.PGDatabase) async throws -> Void {
        let removingBytes = range.upperBound - range.lowerBound
        let (lowerBoundSepResult, upperBoundSepResult) = try await required(throws: File.Errcase.removeFileDataFailed, "文件块分割失败，\(filePath)") {
            (
                // 以 lowerBound 对影响块进行分割
                try await separateFilePart(from: range.lowerBound),
                // 以 upperBound 对影响块进行分割，注意如果指定的 removeBound 在文件最后，则不进行分割计算，直接将删除指针设为 eof
                range.upperBound == fileIndex.size! ? RemoveBytesSeparationResult.eof : .notEof(try await separateFilePart(from: range.upperBound))
            )
        }
        
        let task: @Sendable (FileStorage.PGDatabase) async throws -> Void
        
        let fileId = try required(throws: File.Errcase.removeFileDataFailed, "获取文件 ID 失败，\(filePath)") {
            try fileIndex.requireID()
        }
        
        switch (lowerBoundSepResult, upperBoundSepResult) {
        case (.noNeed(part: let lowerPart), .eof):
            
            //              |- - - - - - - - - - - - - - - - - - - - -|     : will remove
            //              v                                         v
            // |------------|-------------|-------------|-------------|     : origin data chunks
            //              |             |
            //              <------------->                                 : lowerPart
            
            task = { db in
                try await FilePart.query(on: db)
                    .filter(\.$fileIndex.$id == fileId)
                    .filter(\.$byteStart >= lowerPart.byteStart)
                    .delete()
            }
            
        case (.separated(left: let lowerLeft, right: let lowerRight), .eof):
            
            //        |- - - - - - - - - - - - - - - - - - - - - - - -|     : will remove
            //        v                                               v
            // |------------|-------------|-------------|-------------|     : origin data chunks
            // |      |     |
            // <------>     |                                               : lowerLeft
            //        <----->                                               : lowerRight
         
            task = { db in
                try await FilePart.query(on: db)
                    .filter(\.$fileIndex.$id == fileId)
                    .filter(\.$byteStart >= lowerRight.byteStart)
                    .delete()
                try await lowerRight.delete(on: db)
                try await lowerLeft.save(on: db)
            }
            
        case (.noNeed(part: let lowerPart), .notEof(.noNeed(part: let upperPart))):
            
            //              |- - - - - - - - - - - - - -|                   : will remove
            //              v                           v
            // |------------|-------------|-------------|-------------|     : origin data chunks
            //              |             |             |             |
            //              <------------->             |             |     : lowerPart
            //                                          <------------->     : upperPart
            
            task = { db in
                try await FilePart.query(on: db)
                    .filter(\.$fileIndex.$id == fileId)
                    .filter(\.$byteStart >= lowerPart.byteStart)
                    .filter(\.$byteStart < upperPart.byteStart)
                    .delete()
                if willInsertNext { return }
                try await appendRemainingPart(
                    with: -removingBytes,
                    greaterEqualThan: upperPart.byteStart,
                    in: db,
                    fileId: fileId
                )
            }
            
        case (.noNeed(part: let lowerPart), .notEof(.separated(left: let upperLeft, right: let upperRight))):
            
            let (lowerId, upperId) = try required(throws: File.Errcase.removeFileDataFailed, "获取 Part id 失败") {
                try (lowerPart.requireID(), upperRight.requireID())
            }
            
            if lowerId == upperId {
                
                //              |- - - -|                                       : will remove
                //              v       v
                // |------------|-------------|-------------|-------------|     : origin data chunks
                //              |             |
                //              <------------->                                 : lowerPart
                //              |       <----->                                 : upperRight
                //              <------->                                       : upperLeft
                
                task = { db in
                    try await upperRight.update(on: db)
                    if willInsertNext { return }
                    return try await appendRemainingPart(
                        with: -removingBytes,
                        greaterEqualThan: upperRight.byteStart,
                        in: db,
                        fileId: fileId
                    )
                }
                
            } else {
                
                //              |- - - - - - - - - - - - - - - - -|             : will remove
                //              v                                 v
                // |------------|-------------|-------------|-------------|     : origin data chunks
                //              |             |             |     |       |
                //              <------------->             |     |       |     : lowerPart
                //                                          |     <------->     : upperRight
                //                                          <----->             : upperLeft
                
                task = { db in
                    try await FilePart.query(on: db)
                        .filter(\.$fileIndex.$id == fileId)
                        .filter(\.$byteStart >= lowerPart.byteStart)
                        .filter(\.$byteStart < upperLeft.byteStart)
                        .delete()
                    try await upperRight.update(on: db)
                    if willInsertNext { return }
                    try await appendRemainingPart(
                        with: -removingBytes,
                        greaterEqualThan: upperRight.byteStart,
                        in: db,
                        fileId: fileId
                    )
                }
            }
            
        case (.separated(left: let lowerLeft, right: let lowerRight), .notEof(.noNeed(part: let upperPart))):
            
            //        |- - - - - - - - - - - - - - - - -|                   : will remove
            //        v                                 v
            // |------------|-------------|-------------|-------------|     : origin data chunks
            // |      |     |                           |             |
            // |      |     |                           <------------->     : upperPart
            // <------>     |                                               : lowerLeft
            //        <----->                                               : lowerRight
         
            task = { db in
                try await FilePart.query(on: db)
                    .filter(\.$fileIndex.$id == fileId)
                    .filter(\.$byteStart >= lowerRight.byteStart)
                    .filter(\.$byteStart < upperPart.byteStart)
                    .delete()
                try await lowerRight.delete(on: db)
                try await lowerLeft.save(on: db)
                if willInsertNext { return }
                try await appendRemainingPart(
                    with: -removingBytes,
                    greaterEqualThan: upperPart.byteStart,
                    in: db,
                    fileId: fileId
                )
            }
            
        case (.separated(left: let lowerLeft, right: let lowerRight), .notEof(.separated(left: let upperLeft, right: let upperRight))):
            
            let (lowerId, upperId) = try required(throws: File.Errcase.removeFileDataFailed, "获取 Part id 失败") {
                try (lowerRight.requireID(), upperRight.requireID())
            }
            
            if lowerId == upperId {
                
                //                 |- - -|                                      : will remove
                //                 v     v
                // |------------|-------------|-------------|-------------|     : origin data chunks
                //              |  |     |    |
                //              <-------->    |                                 : upperLeft
                //              |  |     <---->                                 : upperRight
                //              <-->          |                                 : lowerLeft
                //                 <---------->                                 : lowerRight
                
                task = { db in
                    try await lowerLeft.save(on: db)
                    try await upperRight.update(on: db)
                    if willInsertNext { return }
                    try await appendRemainingPart(
                        with: -removingBytes,
                        greaterEqualThan: upperRight.byteStart,
                        in: db,
                        fileId: fileId
                    )
                }
                
            } else {
                
                //        |- - - - - - - - - - - - - - - - - - - -|             : will remove
                //        v                                       v
                // |------------|-------------|-------------|-------------|     : origin data chunks
                // |      |     |                           |     |       |
                // |      |     |                           <----->       |     : upperLeft
                // |      |     |                                 <------->     : upperRight
                // <------>     |                                               : lowerLeft
                //        <----->                                               : lowerRight
             
                task = { db in
                    try await FilePart.query(on: db)
                        .filter(\.$fileIndex.$id == fileId)
                        .filter(\.$byteStart >= lowerRight.byteStart)
                        .filter(\.$byteStart < upperLeft.byteStart)
                        .delete()
                    try await lowerRight.delete(on: db)
                    try await lowerLeft.save(on: db)
                    try await upperRight.update(on: db)
                    if willInsertNext { return }
                    try await appendRemainingPart(
                        with: -removingBytes,
                        greaterEqualThan: upperRight.byteStart,
                        in: db,
                        fileId: fileId
                    )
                }
            }
        }
        
        return task
    }
}

struct DataAppendingResult {
    let readBytes: Int64
    let writtenBytes: Int64
    let lastEncryptedSize: Int64
    let lastTag: Int
    
    init(_ readBytes: Int64, _ writtenBytes: Int64, _ lastEncryptedSize: Int64, _ lastTag: Int) {
        self.readBytes = readBytes
        self.writtenBytes = writtenBytes
        self.lastTag = lastTag
        self.lastEncryptedSize = lastEncryptedSize
    }
}

extension __FileWriter {
    
    func appendRemainingPart(
        with byteOffset: Int64,
        greaterEqualThan bound: Int64,
        in db: FileStorage.PGDatabase,
        fileId: UUID
    ) async throws {
        _ = try await db.query("""
            UPDATE "\(FilePart.schema)"
            SET 
                "\(FilePart.fields.byteStart.name)" = "\(FilePart.fields.byteStart.name)" + \(byteOffset),
                "\(FilePart.fields.byteEnd.name)" = "\(FilePart.fields.byteEnd.name)" + \(byteOffset)
            WHERE
                "\(FilePart.fields.fileId.name)" = '\(fileId.uuidString)' AND
                "\(FilePart.fields.byteStart.name)" >= \(bound)
            """).get()
    }
    
    /// 将 channel 中的数据进行加密并追加到文件 fileHandler 的末尾
    func appendChannelDataAndEncryptToFile(
        _ fileHandler: WritableFileHandle,
        tagStart: Int,
        channel: AsyncThrowingChannel<Data, Error>
    ) async throws(BscError<FileWriterError>) -> DataAppendingResult {
        // 取得该文件的大小，用于追加数据
        let size = try await required(throws: FileWriterError.appendDataFailed, "获取文件大小信息时失败") {
            try await fileHandler.info().size
        }
        var writer = fileHandler.bufferedWriter(startingAtAbsoluteOffset: size)
        var writtenBytes: Int64 = 0
        var readBytes: Int64 = 0
        var curTag = tagStart
        try await required(throws: FileWriterError.appendDataFailed, "将数据写入文件中时失败") {
            // 按照 fileCrypto.chunkSize 大小读取每一块数据
            for try await chunk in channel.chunkedChannel(fileCrypto.chunkSize) {
                // 自动将 channel 中的数据流加密写入
                let cipher = try Crypto.Symm.Stream.encrypt(chunk, key: key, chunkTag: curTag).get()
                let buffer = ByteBuffer(data: cipher)
                try await writer.write(contentsOf: buffer)
                try await writer.flush()
                curTag += 1
                writtenBytes += Int64(cipher.count)
                readBytes += Int64(chunk.count)
            }
        }
        return .init(readBytes, writtenBytes, size, curTag)
    }
    
    /// 从数据库的层面上分割文件块，对文件系统 0 操作，且仅对数据库进行读操作，不负责更新操作
    ///
    /// - Parameters:
    ///     - index: 要分割的索引位置
    /// - Returns: 分割的结果，需要调用者自己将数据更新入数据库中
    func separateFilePart(
        from index: Int64
    ) async throws(BscError<FileWriterError>) -> FileWriterSeparationResult {
        // 从数据库中取得包括该插入位置的范围块
        let p = try await required(throws: FileWriterError.separateFilePartFailed, "数据库查询失败") {
            try await FilePart.query(on: storage.db)
                .filter(\.$fileIndex.$id == fileIndex.requireID())
                .filter(\.$byteStart <= index)
                .filter(\.$byteEnd > index)
                .first()
        }
        
        guard let part = p else {
            // 查找要进行分割的索引位置时，未命中任何 FilePart
            // 1. 可能该文件是空的
            // 2. 可能索引分割位置 == 总大小
            // 3. 可能是索引大小超限
            throw FileWriterError.separateFilePartFailed.d("索引超限")
        }
        
        if part.byteStart - part.byteHeadIgnore == index {
            return .noNeed(part: part)
        }
        
        let indexResult = try required(throws: FileWriterError.separateFilePartFailed, "落点判断失败") {
            try ChunkHelpers.index(
                index - part.byteStart + part.byteHeadIgnore,
                in: .init(.chunk(fileCrypto.chunkSize, total: part.byteEnd - part.byteStart + part.byteHeadIgnore + part.byteTailIgnore)),
                offset: Crypto.Symm.Stream.cipherExtraLength
            )
        }
        
        let separationRes = try required(throws: FileWriterError.separateFilePartFailed, "数据片段分割失败") {
            try ChunkHelpers.filePartSeparate(in: part, fileCrypto: fileCrypto, indexResult: indexResult)
        }
        
        guard let newPart = separationRes else {
            return .noNeed(part: part)
        }
        
        return .separated(left: newPart, right: part)
    }
}

extension File {
    struct Writer: __FileWriter, @unchecked Sendable {
        typealias WritableFileHandle = WriteFileHandle
        
        let fileIndex: FileIndex
        let fileCrypto: FileCrypto
        let key: Crypto.Symm.Key
        let filePath: StoragePath
        let fileRealPath: FilePath
        
        let lock = NIOLock()
        let __fileHandler: FileHandleProtocol
        unowned let storage: FileStorage
        
        init(
            fileIndex: FileIndex,
            fileCrypto: FileCrypto,
            key: Crypto.Symm.Key,
            filePath: StoragePath,
            fileRealPath: FilePath,
            fileHandler: WritableFileHandle,
            storage: FileStorage
        ) {
            self.fileIndex = fileIndex
            self.fileCrypto = fileCrypto
            self.key = key
            self.storage = storage
            self.filePath = filePath
            self.fileRealPath = fileRealPath
            self.__fileHandler = fileHandler
        }
    }
}
