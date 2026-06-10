import Testing
import ErrorHandle
import NIOFileSystem
import Foundation
import FluentKit
import Cryptos
@testable import FileStorage

@Suite("File 追加测试集", .serialized, .enabled(if: TestingShared.dbListening))
struct FileAppendingTests {
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .fileAppending {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
    
    static let testDir: StoragePath = "testing"
    
    static let fileList: [
        (
            file: StoragePath,
            chunkSize: Int64,
            firstInsert: Int64,
            appendWrite: Int64
        )
    ] = [
        (
            file: testDir + "example-1.txt",
            chunkSize: 12343,
            firstInsert: 65535 * 5,
            appendWrite: 2000
        ),
        (
            file: testDir + "example-2.txt",
            chunkSize: 2000,
            firstInsert: 2000 * 5,
            appendWrite: 15213
        ),
        (
            file: testDir + "example-3.txt",
            chunkSize: 30000,
            firstInsert: 1,
            appendWrite: 200
        )
    ]
    
    static let fileCreate = fileList.map { ($0.0, $0.1) }
    static let fileWrite = fileList.map { ($0.0, $0.1, $0.2) }
    static let fileAppend = fileList.map { ($0.0, $0.3) }
    
    @Test("文件创建", arguments: fileCreate)
    func createFileTest(path: StoragePath, chunkSize: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let file = try await storage.createFile(at: path, chunkSize: chunkSize, withIntermediateDirectories: true)
        
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
        
        let fileTest = try await storage.getFile(at: path)
        
        #expect(file.id == fileTest.id)
        #expect(file.name == fileTest.name)
        #expect(file.mimeType == fileTest.mimeType)
        #expect(file.path == fileTest.path)
        #expect(file.size == fileTest.size)
    }
    
    @Test("文件写入测试", arguments: fileWrite)
    func fileWriteTest(path: StoragePath, chunkSize: Int64, dataSize: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let file = try await storage.getFile(at: path)
        
        let testData = randomData(size: Int(dataSize))
        
        try await file.withWriter { writer in
            try await writer.write(at: .begin(), bytes: testData, method: .insert)
        }
        
        let fileTest = try await storage.getFile(at: path)
        
        #expect(fileTest.size == file.size)
        #expect(fileTest.size == dataSize)
        
        let fileCrypto = try #require(
            try await FileCrypto.query(on: storage.db)
                .filter(\.$id == file.id)
                .first()
        )
        
        #expect(fileCrypto.chunkSize == chunkSize)
        #expect(fileCrypto.lastTag == dataSize / chunkSize + ((dataSize % chunkSize == 0) ? 0 : 1))
        #expect(fileCrypto.encryptedSize == dataSize + Int64(fileCrypto.lastTag) * (Crypto.Symm.Stream.cipherExtraLength))
        
        let data = try await file.withReader { reader in
            try await reader.readData(part: .range(0..<dataSize))
        }
        
        #expect(data == testData)
        
        let readRange = (dataSize / 2)..<(dataSize * 2 / 3)
        
        let data2 = try await file.withReader { reader in
            try await reader.readData(part: .range(readRange))
        }
        
        #expect(data2 == testData.subdata(in: Int(readRange.lowerBound)..<Int(readRange.upperBound)))
        
        let zeroParts = try await FilePart.query(on: storage.db)
            .filter(\.$byteStart == \.$byteEnd)
            .all()
        
        #expect(zeroParts.count == 0)
    }
    
    @Test("文件夹大小计算测试")
    func directorySizeTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let dir = try await storage.getDirectory(at: Self.testDir)
        
        let size = try await dir.getSize()
        
        #expect(Self.fileList.reduce(0) { $0 + $1.2 } == size)
    }
    
    @Test("写指针非法写入测试", arguments: [
        ("writeIllegalTest/testing1.gzip", 100, -1, 1000),
        ("writeIllegalTest/testing2.gzip", 1000, 1001, 1000),
        ("writeIllegalTest/testing3.gzip", 10000, 10001, 1000),
        ("writeIllegalTest/testing4.gzip", 10000, 20000, 1000)
    ])
    func writeIllegalTest(path: StoragePath, initSize: Int64, begin: Int64, size: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let chunkSize: Int64 = 300
        
        let file = try await storage.createFile(at: path, chunkSize: chunkSize, withIntermediateDirectories: true)
        
        try await file.withWriter { writer in
            try await writer.insert(at: .begin(of: 0), bytes: randomData(size: .init(initSize)))
        }
        
        #expect(file.mimeType == .gzip)

        await #expect(throws: BscError<File.Errcase>.self) {
            try await file.withWriter { writer in
                try await writer.write(at: .begin(of: begin), bytes: randomData(size: .init(size)), method: .insert)
            }.get()
        }
        
        try await file.withWriter { writer in
            do {
                try await writer.write(at: .end(of: begin), bytes: randomData(size: .init(size)), method: .insert)
                try #require(Bool(false))
            } catch {
                let e = error as! BscError<File.Errcase>
                #expect(e.error == File.Errcase.writeFileFailed)
                #expect(e.explain == "插入索引有误")
                print(error)
            }
        }
        
        let data = try await file.withReader { reader in
            try await reader.readData(part: .all)
        }
        
        #expect(data.count == initSize)
    }
    
    @Test("写指针正常写入测试", arguments: [
        ("writeNormalTest/testing1.gzip", 0, 0, 1000),
        ("writeNormalTest/testing2.gzip", 1000, 1000, 1000),
        ("writeNormalTest/testing3.gzip", 10000, 10000, 1000),
        ("writeNormalTest/testing4.gzip", 10000, 9999, 1000)
    ])
    func writeNormalTest(path: StoragePath, initSize: Int64, begin: Int64, size: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let chunkSize: Int64 = 300
        
        let file = try await storage.createFile(at: path, chunkSize: chunkSize, withIntermediateDirectories: true)
        
        try await file.withWriter { writer in
            try await writer.insert(at: .begin(of: 0), bytes: randomData(size: .init(initSize)))
        }
        
        #expect(file.mimeType == .gzip)

        try await file.withWriter { writer in
            try await writer.write(at: .begin(of: begin), bytes: randomData(size: .init(size)), method: .insert)
        }
        
        let data = try await file.withReader { reader in
            try await reader.readData(part: .all)
        }
        
        #expect(data.count == initSize + size)
    }
    
    @Test("文件追加测试", arguments: fileAppend)
    func fileAppendWriteTest(path: StoragePath, dataSize: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let file = try await storage.getFile(at: path)
        
        let fileOriginSize = file.size
        
        let testData = randomData(size: Int(dataSize))
        
        var fileCrypto = try #require(
            try await FileCrypto.query(on: storage.db)
                .filter(\.$id == file.id)
                .first()
        )
        
        let originSize = fileCrypto.encryptedSize
        let lastTag = fileCrypto.lastTag
        let byteOriginSize = originSize - (Crypto.Symm.Stream.cipherExtraLength * Int64(lastTag))
        
        try await file.withWriter { writer in
            try await writer.insert(at: .end(), bytes: testData)
        }
        
        let fileTest = try await storage.getFile(at: path)
        
        #expect(file.size == fileOriginSize + dataSize)
        #expect(fileTest.size == file.size)
        
        fileCrypto = try #require(
            try await FileCrypto.query(on: storage.db)
                .filter(\.$id == file.id)
                .first()
        )
        
        #expect(fileCrypto.lastTag == lastTag + Int(dataSize / fileCrypto.chunkSize + ((dataSize % fileCrypto.chunkSize == 0) ? 0 : 1)))
        #expect(fileCrypto.encryptedSize == originSize + dataSize + Int64(fileCrypto.lastTag - lastTag) * (Crypto.Symm.Stream.cipherExtraLength))
        
        let fileParts = try await FilePart.query(on: storage.db)
            .filter(\.$fileIndex.$id == file.id)
            .all()
        
        #expect(fileParts.count == 2)
        #expect(fileParts[0].byteStart == 0)
        #expect(fileParts[0].byteEnd == byteOriginSize)
        #expect(fileParts[1].byteStart == byteOriginSize)
        #expect(fileParts[1].byteEnd == byteOriginSize + dataSize)
        
        #expect(fileParts[0].encryptedStart == 0)
        #expect(fileParts[0].encryptedEnd == originSize)
        #expect(fileParts[1].encryptedStart == originSize)
        #expect(fileParts[1].encryptedEnd == originSize + dataSize + Int64(fileCrypto.lastTag - lastTag) * (Crypto.Symm.Stream.cipherExtraLength))
    }
    
    @Test("文件夹大小计算测试2")
    func directorySizeTest2() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let dir = try await storage.getDirectory(at: Self.testDir)
        
        let size = try await dir.getSize()
        
        #expect(Self.fileList.reduce(0) { $0 + $1.2 + $1.3 } == size)
    }
    
    @Test("从主目录删除所有子文件夹和子文件")
    func emptyAllTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        try await storage.rootDir.empty(force: true)
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
        TestingShared.testStage = .fileInsertion
    }
}
