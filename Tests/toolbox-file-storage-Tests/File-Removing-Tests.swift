import Testing
import ErrorHandle
import NIOFileSystem
import Foundation
import FluentKit
import Cryptos
@testable import FileStorage

@Suite("File 数据删除测试集", .serialized)
struct FileRemovingTests {
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .fileRemoving {
            sleep(1)
        }
    }
    
    static let fileList: [(StoragePath, Int64, Int64, Range<Int64>, Range<Int64>, Range<Int64>)] = [
        (
            file: "example-1.txt",
            chunkSize: 12343,
            firstInsert: 65535 * 5,
            removing1: 500..<1000,
            removing2: 0..<100,
            removing3: 0..<100
        ),
        (
            file: "example-2.txt",
            chunkSize: 2000,
            firstInsert: 2000 * 5,
            removing1: 1024..<2048,
            removing2: 0..<738,
            removing3: 0..<100
        ),
        (
            file: "example-3.txt",
            chunkSize: 30000,
            firstInsert: 1,
            removing1: 0..<1,
            removing2: 0..<0,
            removing3: 0..<100
        )
    ]
    
    @Test("文件创建", arguments: fileList.map { ($0.0, $0.1) })
    func createFileTest(path: StoragePath, chunkSize: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        let file = try await storage.createFile(at: path, chunkSize: chunkSize).get()
    }
    
    @Test("文件写入", arguments: fileList.map { ($0.0, $0.1, $0.2) })
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
        
        #expect(fileCrypto.chunkSize == chunkSize)
        #expect(fileCrypto.lastTag == dataSize / chunkSize + ((dataSize % chunkSize == 0) ? 0 : 1))
        #expect(fileCrypto.encryptedSize == dataSize + Int64(fileCrypto.lastTag) * (Crypto.Symm.Stream.cipherExtraLength))
    }
    
    @Test("删除数据", arguments: fileList.map { ($0.0, $0.3) })
    func fileDataRemoveTest(path: StoragePath, removing: Range<Int64>) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let file = try await storage.getFile(at: path).get()
        
        file.withWriter { writer in
            writer.remove(in: removing)
        }
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
