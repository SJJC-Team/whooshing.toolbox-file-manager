import NIOFileSystem
import NIOConcurrencyHelpers
import NIOCore
import NIOAdvanced
import ErrorHandle
import AsyncAlgorithms
import Cryptos
import FluentKit

public enum InsertIndex: Sendable {
    case begin(of: Int64)
    case end(of: Int64)
}

public protocol FileWriter: FileContentHandler {
//    func insert(from start: Int64, with data: ByteBuffer) -> EventLoopResult<Void, BscError<File.Errcase>>
}

protocol __FileWriter: FileWriter, __FileContentHandler {
    var storage: FileStorage { get }
    var fileWriteHandler: ReadWriteFileHandle { get }
}

extension __FileWriter {
    var fileWriteHandler: ReadWriteFileHandle {
        guard let handler = self.fileHandler as? ReadWriteFileHandle else {
            fatalError("FileHandler 配置不正确")
        }
        return handler
    }
    
//    func write(from start: Int64 = 0, with data: ByteBuffer) -> EventLoopResult<Void, BscError<File.Errcase>> {
//        // 创建读取任务准备进行异步写入
//        
//    }
}

public enum WriteSubActionErrcase: String, ErrList {
    case writeChunkToFileFailed = "将数据写入文件时失败"
    case readChunkFromFileFailed = "从文件中读取数据时失败"
}

extension __FileWriter {
    func backPressureInsert(
        from insertIndex: InsertIndex,
        in dataBuffer: AsyncThrowingChannel<ByteBuffer, Error>
    ) async throws(BscError<File.Errcase>) {
        
        let byteStartIndex: Int64
        switch insertIndex {
        case .begin(of: let i):
            byteStartIndex = i
        case .end(of: let i):
            byteStartIndex = fileCrypto.encryptedSize - i
        }
        
        // 从数据库中取得包括该插入位置的范围块
        let p = try await required(throws: File.Errcase.writeFileFailed, "数据库查询失败") {
            try await FilePart.query(on: storage.db)
                .filter(\.$byteStart <= byteStartIndex)
                .filter(\.$byteEnd > byteStartIndex)
                .first()
        }
        
        guard let part = p else {
            //创建新的
            return
        }
        
        
    }
    
}

extension File {
    struct Writer: __FileWriter, @unchecked Sendable {
        let fileIndex: FileIndex
        let fileCrypto: FileCrypto
        let key: Crypto.Symm.Key
        
        let lock = NIOLock()
        let __fileHandler: FileHandleProtocol
        unowned let storage: FileStorage
        
        init(
            fileIndex: FileIndex,
            fileCrypto: FileCrypto,
            key: Crypto.Symm.Key,
            fileHandler: ReadWriteFileHandle,
            storage: FileStorage
        ) {
            self.fileIndex = fileIndex
            self.fileCrypto = fileCrypto
            self.key = key
            self.storage = storage
            self.__fileHandler = fileHandler
        }
    }
}
