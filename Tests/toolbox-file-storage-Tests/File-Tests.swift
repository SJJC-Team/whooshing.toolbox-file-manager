import Testing
import ErrorHandle
import NIOFileSystem
import Foundation
import FluentKit
import Cryptos
@testable import FileStorage

@Suite("File 测试集", .serialized)
struct FileTests {
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .file {
            sleep(1)
        }
    }
    
    static let fileList: [(StoragePath, Int64, Int64)] = [
        ("example-1.txt", 12343, 65535 * 5),
        ("example-2.txt", 2000, 2000 * 5),
        ("example-3.txt", 30000, 1)
    ]
    
    @Test("文件创建测试", arguments: fileList.map { ($0.0, $0.1) })
    func createFileTest(path: StoragePath, chunkSize: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let file = try await storage.createFile(at: path, chunkSize: chunkSize).get()
        
        #expect(file.name == path.last!)
        #expect(file.mimeType == .plain)
        #expect(file.path == path)
        #expect(file.size == 0)
        
        let fileCrypto = try #require(
            try await FileCrypto.query(on: storage.db)
                .filter(\.$id == file.id)
                .first()
        )
        
        #expect(fileCrypto.chunkSize == chunkSize)
        
        let fileTest = try await storage.getFile(at: path).get()
        
        #expect(file.id == fileTest.id)
        #expect(file.name == fileTest.name)
        #expect(file.mimeType == fileTest.mimeType)
        #expect(file.path == fileTest.path)
        #expect(file.size == fileTest.size)
    }
    
    @Test("文件写入测试", arguments: fileList)
    func fileWriteTest(path: StoragePath, chunkSize: Int64, dataSize: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let file = try await storage.getFile(at: path).get()
        
        let testData = randomData(size: Int(dataSize))
        
        try await file.withWriter { writer in
            writer.insert(at: .begin(), bytes: testData)
        }.get()
        
        let fileCrypto = try #require(
            try await FileCrypto.query(on: storage.db)
                .filter(\.$id == file.id)
                .first()
        )
        
        #expect(fileCrypto.lastTag == dataSize / chunkSize + ((dataSize % chunkSize == 0) ? 0 : 1))
        #expect(fileCrypto.encryptedSize == dataSize + Int64(fileCrypto.lastTag) * (Crypto.Symm.Stream.cipherExtraLength))
    }
    
    @Test("从主目录删除所有子文件夹和子文件")
    func emptyAllTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        try await storage.rootDir.empty(force: true).get()
    }
    
    @Test("数据库和文件系统中的数据应当为空")
    func emptyTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let dir = try await FileSystem.shared.openDirectory(atPath: .init(storage.storagePath))
        
        var pass = true
        do {
            for try await entry in dir.listContents() {
                if let last = entry.path.lastComponent, last.string.hasPrefix(".") {
                    continue
                }
                pass = false
                break
            }
            try await dir.close()
        } catch {
            try await dir.close()
        }
        
        #expect(pass)
        #expect(try await FileIndex.query(on: storage.db).withDeleted().all().count == 0)
        #expect(try await FileCrypto.query(on: storage.db).withDeleted().all().count == 0)
        #expect(try await FilePart.query(on: storage.db).withDeleted().all().count == 0)
    }
    
    @MainActor
    @Test("测试结束")
    func end() async throws {
        TestingShared.testStage = .entryBasics
    }
}
