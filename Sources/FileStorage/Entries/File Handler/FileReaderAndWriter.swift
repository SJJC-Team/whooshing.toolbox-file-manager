import NIOFileSystem
import Cryptos
import Logging
import NIOConcurrencyHelpers

extension File {
    struct ReaderAndWriter: __FileReader, __FileWriter, @unchecked Sendable {
        typealias WritableFileHandle = ReadWriteFileHandle
        typealias ReadableFileHandle = ReadWriteFileHandle
        typealias WritableReadableFileHandle = WritableFileHandle
        
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
            fileHandler: WritableReadableFileHandle,
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
