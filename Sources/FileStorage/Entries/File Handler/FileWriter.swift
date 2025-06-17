import NIOFileSystem
import NIOConcurrencyHelpers
import NIOCore
import NIOAdvanced
import ErrorHandle
import AsyncAlgorithms
import Cryptos

public enum WriteMethod: Sendable {
    case overwrite
    case insert
}

public protocol FileWriter: FileContentHandler {
//    func write(from start: Int64, with data: ByteBuffer) -> EventLoopResult<Void, BscError<File.Errcase>>
}

protocol __FileWriter: FileWriter, __FileContentHandler {
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

extension __FileWriter {
//    func backPressureWrite(
//        from startIndex: Int64,
//        with space: BufferSpace,
//        method: WriteMethod = .insert
//    ) async throws(BscError<File.Errcase>) {
//        guard fileCrypto.encryptedSize >= startIndex else {
//            throw File.Errcase.writeFileFailed.d("写指针起始索引超出限制，总大小为 \(fileCrypto.encryptedSize), 却得到 \(startIndex)")
//        }
//        
//        switch method {
//        case .insert:
//            let indexResult = try required(throws: File.Errcase.writeFileFailed, "插入数据-数据落点计算失败") {
//                try ChunkHelpers.index(startIndex, in: .init(.array(fileCrypto.chunks)), offset: Int64(Crypto.Symm.Stream.cipherExtraLength))
//            }
//            
//            
//        case .overwrite:
//        }
//        
//    }
}

extension File {
    struct Writer: __FileWriter, @unchecked Sendable {
        var fileIndex: FileIndex
        var fileCrypto: FileCrypto
        var key: Crypto.Symm.Key
        
        var lock = NIOLock()
        var __fileHandler: FileHandleProtocol
        
        init(
            fileIndex: FileIndex,
            fileCrypto: FileCrypto,
            key: Crypto.Symm.Key,
            fileHandler: WriteFileHandle
        ) {
            self.fileIndex = fileIndex
            self.fileCrypto = fileCrypto
            self.key = key
            self.__fileHandler = fileHandler
        }
    }
}
