import NIOFileSystem
import Cryptos
import NIOConcurrencyHelpers

extension File {
    struct ReaderAndWriter: __FileReader, __FileWriter, @unchecked Sendable {
        let fileIndex: FileIndex
        let fileCrypto: FileCrypto
        let key: Crypto.Symm.Key
        
        var lock = NIOLock()
        var __fileHandler: FileHandleProtocol
        
        init(
            fileIndex: FileIndex,
            fileCrypto: FileCrypto,
            key: Crypto.Symm.Key,
            fileHandler: ReadWriteFileHandle
        ) {
            self.fileIndex = fileIndex
            self.fileCrypto = fileCrypto
            self.key = key
            self.__fileHandler = fileHandler
        }
    }
}
