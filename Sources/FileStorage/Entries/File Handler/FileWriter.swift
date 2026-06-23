import NIOFileSystem
import NIOConcurrencyHelpers
import NIOAdvanced
import AsyncAlgorithms
import Cryptos
import FluentKit
import Foundation

/// 表示文件中的字节位置索引。
///
/// - `begin(of:)`：从文件开头开始的偏移量，默认从 0 开始。
/// - `end(of:)`：从文件结尾开始的偏移量，默认从 0 开始。
@frozen
public enum ByteIndex: Sendable, CustomStringConvertible, Loggerable {
    case begin(of: Int64 = 0)
    case end(of: Int64 = 0)
    
    public var description: String {
        switch self {
        case .begin(let of): "begin(of: \(of))"
        case .end(let of): "end(of: \(of))"
        }
    }
}

/// 文件写入方式。
///
/// - `insert`：在指定位置插入数据，后续内容顺移。
/// - `replace`：在指定位置替换数据，覆盖原有内容。
@frozen
public enum WriteMethod: String, Sendable, CustomStringConvertible, Loggerable  {
    case insert
    case replace
    
    public var description: String {
        self.rawValue
    }
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
        case .begin(of: let i): i
        case .end(of: let i): fileSize - i
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
        let logger = getHandleLogger()
        logger.info("执行 流式插入数据 操作", metadata: ["index": .data(index)])
        
        let insertIndex = index.index(fileSize: fileIndex.size!)
        let (_, dbOperation) = try await backPressureInsert(at: insertIndex, from: channel, removeLater: false, logger: logger)
        
        try await storage.db.atrans { db throws(File.Errcase.ErrType) in
            try await dbOperation(db)
        }
        
        logger.info("流式插入数据操作完成")
    }
    
    @inlinable
    func replace(at index: ByteIndex, from channel: AsyncThrowingChannel<Data, Error>) async throws(File.Errcase.ErrType) {
        let logger = getHandleLogger()
        logger.info("执行 流式替换数据 操作", metadata: ["index": .data(index)])
        
        let insertIndex = index.index(fileSize: fileIndex.size!)
        
        let op1 = try await backPressureInsert(at: insertIndex, from: channel, removeLater: true, logger: logger)
        let op2 = try await removeBytes(in: insertIndex..<(min(insertIndex + op1.appendRes.readBytes, fileIndex.size!)), willInsertNext: true, logger: logger)
        
        try await storage.db.atrans { db throws(File.Errcase.ErrType) in
            try await op2(db)
            try await op1.dbOperation(db)
        }
        
        logger.info("流式替换数据操作完成")
    }
    
    @inlinable
    func remove(in range: Range<Int64>) async throws(File.Errcase.ErrType) {
        let logger = getHandleLogger()
        logger.info("执行 删除数据 操作", metadata: ["range": .stringConvertible(range)])
        
        let dbOperation = try await removeBytes(in: range, willInsertNext: false, logger: logger)
        try await storage.db.atrans { db throws(File.Errcase.ErrType) in
            try await dbOperation(db)
        }
        
        logger.info("删除数据操作完成")
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

enum FileWriterSeparationResult: CustomStringConvertible, Loggerable {
    case noNeed(part: FilePart)
    case separated(left: FilePart, right: FilePart)
    
    var json: [String: AnyCodable] {
        switch self {
        case .noNeed(let part): [
            "need_separation": AnyCodable("no"),
            "part": AnyCodable(part.json)
        ]
        case .separated(let left, let right): [
            "need_separation": AnyCodable("yes"),
            "left_part": AnyCodable(left.json),
            "right_part": AnyCodable(right.json)
        ]
        }
    }
    
    var description: String {
        formatJson(json)
    }
}

enum RemoveBytesSeparationResult: CustomStringConvertible, Loggerable {
    case eof
    case notEof(FileWriterSeparationResult)
    
    var json: [String: AnyCodable] {
        switch self {
        case .eof: [
            "at_eof": "no"
        ]
        case .notEof(let fileWriterSeparationResult): [
            "at_eof": "no",
            "file_writer_sep_result": AnyCodable(fileWriterSeparationResult.json)
        ]
        }
    }
    
    var description: String {
        formatJson(json)
    }
}

extension __FileWriter {
    /// 将提供的数据插入到某个位置。
    /// 该函数会进行数据写入，但不会更新数据库中的指针位置，数据库操作将会作为返回值返回，需要调用者自行执行数据库操作
    @usableFromInline
    func backPressureInsert(
        at byteStartIndex: Int64,
        from channel: AsyncThrowingChannel<Data, Error>,
        removeLater: Bool,
        logger: Logger
    ) async throws(File.Errcase.ErrType) -> (
        appendRes: DataAppendingResult,
        dbOperation: @Sendable (FileStorage.PGDatabase) async throws(File.Errcase.ErrType) -> Void
    ) {
        logger.debug("文件索引范围", metadata: [
            "range": .stringConvertible(0...fileIndex.size!)
        ])
        
        guard byteStartIndex <= fileIndex.size!, byteStartIndex >= 0 else {
            throw File.Errcase.writeFileFailed.d("插入索引有误", category: .external()).metadata([
                "range": .stringConvertible(0...fileIndex.size!),
                "index": .stringConvertible(byteStartIndex)
            ])
        }
        
        // 将数据直接写入到加密文件中
        let appendRes = try await required(throws: File.Errcase.writeFileFailed, "将数据写入到文件中时失败，\(fileRealPath)", category: .internal) {
            try await appendChannelDataAndEncryptToFile(fileWriteHandler, tagStart: fileCrypto.lastTag, channel: channel, logger: logger)
        }
        
        logger.debug("将数据写入真实文件完成", metadata: ["result": .data(appendRes)])
        
        guard appendRes.readBytes > 0 else {
            logger.info("本次操作未写入任何数据")
            return (appendRes, { _ in })
        }
        
        let fileId = try required(throws: File.Errcase.writeFileFailed, "获取文件 ID 失败", category: .internal) {
            try fileIndex.requireID()
        }
        
        // 准备进行数据库索引块分割任务
        let separateTask: @Sendable (FileStorage.PGDatabase) async throws -> Void
        
        if byteStartIndex == fileIndex.size! {
            logger.debug("本次操作为文件内容追加")
            // 追加到文件最后
            // 查询最后一个 filePart 记录，以用于追加
            // 若 last 不存在，则表示该文件是空的
            let last = try await required(throws: File.Errcase.writeFileFailed, "数据库检索失败，\(filePath)", category: .internal) {
                try await FilePart.query(on: storage.db)
                    .filter(\.$fileIndex.$id == fileIndex.requireID())
                    .sort(\.$byteEnd, .descending)
                    .sort(\.$byteStart, .descending)
                    .first()
            }
            
            logger.debug("文件内容追加，则索引追加", metadata: ["last_part": .data(last)])
            
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
            
            logger.debug("文件内容追加，则无需任何块分割操作", metadata: ["new_part": .data(newPart)])
            
            separateTask = { db in
                try await newPart.save(on: db)
                logger.debug("文件内容追加索引处理成功")
            }
        } else {
            logger.debug("本次操作为文件内容插入")
            // 进行数据插入，而非追加
            // 先对影响块进行分割
            let separateResult = try await required(throws: File.Errcase.writeFileFailed, "文件块分割失败，\(filePath)", category: .inherit) {
                try await separateFilePart(from: byteStartIndex)
            }
            
            logger.debug("切分策略计算完成，准备应用分割", metadata: ["result": .data(separateResult)])
            
            // 判断分割结果，并应用分割
            let markPart: FilePart
            // 对不同的分割方案执行不同的任务
            let __task: @Sendable (FileStorage.PGDatabase) async throws -> Void
            
            switch separateResult {
            case .noNeed(part: let part):
                logger.debug("准备执行 无分割 方案")
                markPart = part
                __task = { db in
                    
                    if removeLater {
                        logger.debug("滞后 remove")
                        return
                    }
                    // 更新该插入点之后的所有数据库记录，使其均向后偏移该插入的字节量
                    try await appendRemainingPart(
                        with: appendRes.readBytes,
                        greaterEqualThan: markPart.byteStart,
                        in: db,
                        fileId: fileId,
                        logger: logger
                    )
                    
                    logger.debug("无分割方案执行完成")
                }
            case .separated(left: let left, right: let right):
                logger.debug("准备执行 将新割出的插入到数据库中，并更新被割出的原 Part 方案")
                markPart = right
                // 需要分割，将新割出的插入到数据库中，并更新被割出的原 Part
                __task = { db in
                    if removeLater {
                        logger.debug("滞后 remove")
                        return
                    }
                    try await left.save(on: db)
                    try await right.update(on: db)
                    // 更新该插入点之后的所有数据库记录，使其均向后偏移该插入的字节量
                    try await appendRemainingPart(
                        with: appendRes.readBytes,
                        greaterEqualThan: markPart.byteStart,
                        in: db,
                        fileId: fileId,
                        logger: logger
                    )
                    
                    logger.debug("分割方案执行完成")
                }
            }
            
            let fileId = try required(throws: File.Errcase.writeFileFailed, "获取文件 ID 失败，\(filePath)", category: .internal) {
                try fileIndex.requireID()
            }
            
            // 将数据库查询任务记录在一个闭包中，目前不执行，在最后使用 transaction 执行确保原子性
            separateTask = { db in
                try await __task(db)
                // 插入新的 FilePart 到数据库中
                let filePart = FilePart(
                    fileIndexId: fileId,
                    tagStart: fileCrypto.lastTag,
                    byteStart: markPart.byteStart,
                    byteEnd: markPart.byteStart + appendRes.readBytes,
                    byteHeadIgnore: 0,
                    byteTailIgnore: 0,
                    encryptedStart: appendRes.lastEncryptedSize,
                    encryptedEnd: appendRes.lastEncryptedSize + appendRes.writtenBytes
                )
                try await filePart.save(on: db)
                
                logger.debug("新插入数据块索引保存成功", metadata: ["part": .data(filePart)])
            }
        }
        
        return (
            appendRes,
            { db throws(File.Errcase.ErrType) in
                try await required(throws: File.Errcase.writeFileFailed, "数据库操作失败，\(filePath)", category: .internal) {
                    try await separateTask(db)
                    // 更新加密数据的信息
                    fileCrypto.lastTag = appendRes.lastTag
                    fileCrypto.encryptedSize += appendRes.writtenBytes
                    try await fileCrypto.update(on: db)
                    fileIndex.size = fileIndex.size! + appendRes.readBytes
                    try await fileIndex.update(on: db)
                    logger.debug("索引更新成功", metadata: ["crypto": .data(fileCrypto)])
                }
            }
        )
    }
    
    /// 从文件中移除某个区间的字节数据。
    /// 该函数不会进行任何文件系统操作，也不会更新数据库中的指针位置，数据库操作将会作为返回值返回，需要调用者自行执行数据库操作
    @usableFromInline
    func removeBytes(
        in range: Range<Int64>,
        willInsertNext: Bool,
        logger: Logger
    ) async throws(File.Errcase.ErrType) -> (@Sendable (FileStorage.PGDatabase) async throws(File.Errcase.ErrType) -> Void) {
        logger.debug("文件数据范围", metadata: ["range": .stringConvertible(0..<fileIndex.size!)])
        
        guard
            range.lowerBound <= fileIndex.size!,
            range.lowerBound >= 0,
            range.upperBound <= fileIndex.size!,
            range.upperBound >= 0
        else {
            throw File.Errcase.removeFileDataFailed.d("提供的索引大小有误", category: .external()).metadata([
                "range": .stringConvertible(range),
                "file_range": .stringConvertible(0..<fileIndex.size!)
            ])
        }
        
        guard !range.isEmpty else {
            logger.info("要删除的范围大小为 0，未执行任何操作")
            return { _ in () }
        }
        
        let removingBytes = range.upperBound - range.lowerBound
        
        let task = try await __removeBytes(in: range, willInsertNext: willInsertNext, logger: logger)
        
        return { db in
            try await required(throws: File.Errcase.removeFileDataFailed, "数据库操作失败，\(filePath)", category: .internal) {
                try await task(db)
                // 更新加密数据的信息
                fileCrypto.encryptedSize -= removingBytes
                try await fileCrypto.update(on: db)
                fileIndex.size! -= range.upperBound - range.lowerBound
                try await fileIndex.update(on: db)
                logger.info("数据库索引更新成功-删除操作", metadata: [
                    "crypto": .data(fileCrypto),
                    "index": .data(fileIndex)
                ])
            }
        }
    }
}
 
extension __FileWriter {
    func __removeBytes(
        in range: Range<Int64>,
        willInsertNext: Bool,
        logger: Logger
    ) async throws(File.Errcase.ErrType) -> @Sendable (FileStorage.PGDatabase) async throws -> Void {
        let removingBytes = range.upperBound - range.lowerBound
        let (lowerBoundSepResult, upperBoundSepResult) = try await required(throws: File.Errcase.removeFileDataFailed, "文件块分割失败，\(filePath)", category: .inherit) {
            (
                // 以 lowerBound 对影响块进行分割
                try await separateFilePart(from: range.lowerBound),
                // 以 upperBound 对影响块进行分割，注意如果指定的 removeBound 在文件最后，则不进行分割计算，直接将删除指针设为 eof
                range.upperBound == fileIndex.size! ? RemoveBytesSeparationResult.eof : .notEof(try await separateFilePart(from: range.upperBound))
            )
        }
        
        logger.debug("准备应用分割策略", metadata: [
            "lower_bound_sep_result": .data(lowerBoundSepResult),
            "upper_bound_sep_result": .data(upperBoundSepResult)
        ])
        
        let task: @Sendable (FileStorage.PGDatabase) async throws -> Void
        
        let fileId = try required(throws: File.Errcase.removeFileDataFailed, "获取文件 ID 失败，\(filePath)", category: .internal) {
            try fileIndex.requireID()
        }
        
        switch (lowerBoundSepResult, upperBoundSepResult) {
        case (.noNeed(part: let lowerPart), .eof):
            logger.debug("执行 策略 1")
            
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
                logger.debug("索引更新完成 - 策略 1")
            }
            
        case (.separated(left: let lowerLeft, right: let lowerRight), .eof):
            logger.debug("执行 策略 2")
            
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
                logger.debug("索引更新完成 - 策略 2")
            }
            
        case (.noNeed(part: let lowerPart), .notEof(.noNeed(part: let upperPart))):
            logger.debug("执行 策略 3")
            
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
                if willInsertNext {
                    logger.debug("will_insert_next")
                    return
                }
                try await appendRemainingPart(
                    with: -removingBytes,
                    greaterEqualThan: upperPart.byteStart,
                    in: db,
                    fileId: fileId,
                    logger: logger
                )
                logger.debug("索引更新完成 - 策略 3")
            }
            
        case (.noNeed(part: let lowerPart), .notEof(.separated(left: let upperLeft, right: let upperRight))):
            
            let (lowerId, upperId) = try required(throws: File.Errcase.removeFileDataFailed, "获取 Part id 失败", category: .internal) {
                try (lowerPart.requireID(), upperRight.requireID())
            }
            
            if lowerId == upperId {
                logger.debug("执行 策略 4")
                
                //              |- - - -|                                       : will remove
                //              v       v
                // |------------|-------------|-------------|-------------|     : origin data chunks
                //              |             |
                //              <------------->                                 : lowerPart
                //              |       <----->                                 : upperRight
                //              <------->                                       : upperLeft
                
                task = { db in
                    try await upperRight.update(on: db)
                    if willInsertNext {
                        logger.debug("will_insert_next")
                        return
                    }
                    try await appendRemainingPart(
                        with: -removingBytes,
                        greaterEqualThan: upperRight.byteStart,
                        in: db,
                        fileId: fileId,
                        logger: logger
                    )
                    logger.debug("索引更新完成 - 策略 4")
                }
                
            } else {
                logger.debug("执行 策略 5")
                
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
                    if willInsertNext {
                        logger.debug("will_insert_next")
                        return
                    }
                    try await appendRemainingPart(
                        with: -removingBytes,
                        greaterEqualThan: upperRight.byteStart,
                        in: db,
                        fileId: fileId,
                        logger: logger
                    )
                    logger.debug("索引更新完成 - 策略 5")
                }
            }
            
        case (.separated(left: let lowerLeft, right: let lowerRight), .notEof(.noNeed(part: let upperPart))):
            logger.debug("执行 策略 6")
            
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
                if willInsertNext {
                    logger.debug("will_insert_next")
                    return
                }
                try await appendRemainingPart(
                    with: -removingBytes,
                    greaterEqualThan: upperPart.byteStart,
                    in: db,
                    fileId: fileId,
                    logger: logger
                )
                logger.debug("索引更新完成 - 策略 6")
            }
            
        case (.separated(left: let lowerLeft, right: let lowerRight), .notEof(.separated(left: let upperLeft, right: let upperRight))):
            
            let (lowerId, upperId) = try required(throws: File.Errcase.removeFileDataFailed, "获取 Part id 失败", category: .internal) {
                try (lowerRight.requireID(), upperRight.requireID())
            }
            
            if lowerId == upperId {
                logger.debug("执行 策略 7")
                
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
                    if willInsertNext {
                        logger.debug("will_insert_next")
                        return
                    }
                    try await appendRemainingPart(
                        with: -removingBytes,
                        greaterEqualThan: upperRight.byteStart,
                        in: db,
                        fileId: fileId,
                        logger: logger
                    )
                    logger.debug("索引更新完成 - 策略 7")
                }
                
            } else {
                logger.debug("执行 策略 8")
                
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
                    if willInsertNext {
                        logger.debug("will_insert_next")
                        return
                    }
                    try await appendRemainingPart(
                        with: -removingBytes,
                        greaterEqualThan: upperRight.byteStart,
                        in: db,
                        fileId: fileId,
                        logger: logger
                    )
                    logger.debug("索引更新完成 - 策略 8")
                }
            }
        }
        
        return task
    }
}

struct DataAppendingResult: CustomStringConvertible, Loggerable {
    // 写入的数据字节
    let readBytes: Int64
    // 写入到真实文件系统的加密数据字节
    let writtenBytes: Int64
    let lastEncryptedSize: Int64
    let lastTag: Int
    
    init(_ readBytes: Int64, _ writtenBytes: Int64, _ lastEncryptedSize: Int64, _ lastTag: Int) {
        self.readBytes = readBytes
        self.writtenBytes = writtenBytes
        self.lastTag = lastTag
        self.lastEncryptedSize = lastEncryptedSize
    }
    
    var description: String {
        formatJson([
            "read_bytes": AnyCodable(readBytes),
            "written_bytes": AnyCodable(writtenBytes),
            "last_encrypted_size": AnyCodable(lastEncryptedSize),
            "last_tag": AnyCodable(lastTag)
        ])
    }
}

extension __FileWriter {
    
    func appendRemainingPart(
        with byteOffset: Int64,
        greaterEqualThan bound: Int64,
        in db: FileStorage.PGDatabase,
        fileId: UUID,
        logger: Logger
    ) async throws {
        let sql = """
        UPDATE "\(FilePart.schema)"
        SET 
            "\(FilePart.fields.byteStart.name)" = "\(FilePart.fields.byteStart.name)" + \(byteOffset),
            "\(FilePart.fields.byteEnd.name)" = "\(FilePart.fields.byteEnd.name)" + \(byteOffset)
        WHERE
            "\(FilePart.fields.fileId.name)" = '\(fileId.uuidString)' AND
            "\(FilePart.fields.byteStart.name)" >= \(bound)
        """
        
        logger.debug("偏移后段需受影响字段，偏移 byteOffset 大小", metadata: [
            "byte_offset": .stringConvertible(byteOffset),
            "bound": .stringConvertible(bound),
            "sql": .string(sql)
        ])
        
        _ = try await db.query(sql).get()
        
        logger.debug("受影响字段偏移完成")
    }
    
    /// 将 channel 中的数据进行加密并追加到文件 fileHandler 的末尾
    func appendChannelDataAndEncryptToFile(
        _ fileHandler: WritableFileHandle,
        tagStart: Int,
        channel: AsyncThrowingChannel<Data, Error>,
        logger: Logger
    ) async throws(FileWriterError.ErrType) -> DataAppendingResult {
        // 取得该文件的大小，用于追加数据
        let size = try await required(throws: FileWriterError.appendDataFailed, "获取真实文件大小信息时失败", category: .internal) {
            try await fileHandler.info().size
        }
        logger.debug("取得真实文件大小", metadata: ["size": .stringConvertible(size)])
        var writer = fileHandler.bufferedWriter(startingAtAbsoluteOffset: size)
        // 写入到真实文件系统的加密数据字节
        var writtenBytes: Int64 = 0
        // 写入的数据字节
        var readBytes: Int64 = 0
        var curTag = tagStart
        try await required(throws: FileWriterError.appendDataFailed, "将数据写入真实文件中时失败", category: .inherit) {
            // 按照 fileCrypto.chunkSize 大小读取每一块数据
            for try await chunk in channel.chunkedChannel(fileCrypto.chunkSize) {
                // 自动将 channel 中的数据流加密写入
                let cipher = try Crypto.Symm.Stream.encrypt(chunk, key: key, chunkTag: curTag).get()
                logger.debug("完成数据加密", metadata: [
                    "tag": .stringConvertible(curTag),
                    "plain_size": .stringConvertible(chunk.count),
                    "cipher_size": .stringConvertible(cipher.count)
                ])
                let buffer = ByteBuffer(data: cipher)
                logger.debug("已写入数据 tag \(curTag)", metadata: [
                    "size": .stringConvertible(chunk.count),
                    "real_size": .stringConvertible(cipher.count),
                    "written_bytes": .stringConvertible(readBytes),
                    "written_real_bytes": .stringConvertible(writtenBytes)
                ])
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
    ) async throws(FileWriterError.ErrType) -> FileWriterSeparationResult {
        // 从数据库中取得包括该插入位置的范围块
        let p = try await required(throws: FileWriterError.separateFilePartFailed, "数据库查询失败", category: .internal) {
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
            throw FileWriterError.separateFilePartFailed.d("索引超限", category: .external())
        }
        
        if part.byteStart - part.byteHeadIgnore == index {
            return .noNeed(part: part)
        }
        
        let bufferSpace = BufferSpace(.chunk(fileCrypto.chunkSize, total: part.byteEnd - part.byteStart + part.byteHeadIgnore + part.byteTailIgnore))
        
        let indexResult = try required(throws: FileWriterError.separateFilePartFailed, "落点判断失败", category: .inherit) {
            try ChunkHelpers.index(
                index - part.byteStart + part.byteHeadIgnore,
                in: bufferSpace,
                offset: Crypto.Symm.Stream.cipherExtraLength
            )
        }
        
        let separationRes = try required(throws: FileWriterError.separateFilePartFailed, "数据片段分割失败", category: .inherit) {
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
        let logger: Logger
        
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
            logger: Logger,
            storage: FileStorage
        ) {
            self.fileIndex = fileIndex
            self.fileCrypto = fileCrypto
            self.key = key
            self.storage = storage
            self.filePath = filePath
            self.fileRealPath = fileRealPath
            self.logger = logger
            self.__fileHandler = fileHandler
        }
    }
}
