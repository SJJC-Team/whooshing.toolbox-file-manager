import NIOFileSystem
import Cryptos
import NIOConcurrencyHelpers

extension File {
    struct ReaderAndWriter: __FileReader, __FileWriter, @unchecked Sendable {
        typealias WritableFileHandle = ReadWriteFileHandle
        
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
