import NIOFileSystem
import Cryptos
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
