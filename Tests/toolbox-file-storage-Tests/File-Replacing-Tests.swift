import Testing
import ErrorHandle
import NIOFileSystem
import Foundation
import FluentKit
import Cryptos
import NIOCore
@testable import FileStorage

@Suite("File 数据覆写测试集", .serialized)
struct FileReplacmentTests {
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .fileReplacemeng {
            sleep(1)
        }
    }
    
    typealias Replacing = (
        start: Int64,
        data: ByteBuffer
    )
    
    static let fileList: [(StoragePath, ByteBuffer, Int64, [Replacing])] = [
        (
            file: "example-0.txt",
            data: ByteBuffer(string: "Hello World! Testing String"),
            chunkSize: 5,
            replacings: [
                (0, ByteBuffer(string: "123")),
                (5, ByteBuffer(string: "456")),
                (10, ByteBuffer(string: "789")),
                (26, ByteBuffer(string: "10111213")),
            ]
        ),
        (
            file: "example-1.txt",
            data: randomData(size: 0),
            chunkSize: 4000,
            replacings: [
                (0, randomData(size: 3000)),
                (1000, randomData(size: 3500)),
                (4500, randomData(size: 7000)),
                (11500, randomData(size: 3000)),
                (14500, randomData(size: 2000)),
                (16500, randomData(size: 1000)),
                (0, randomData(size: 0)),
            ]
        ),
        (
            file: "example-2.txt",
            data: randomData(size: 200000),
            chunkSize: 10000,
            replacings: [
                (12343, randomData(size: 30100)),
                (12897, randomData(size: 32412)),
                (433, randomData(size: 34334)),
                (312, randomData(size: 1423)),
                (8643, randomData(size: 65485)),
                (2345, randomData(size: 45435))
            ]
        ),
    ]
    
    @Test("文件创建", arguments: fileList.map { ($0.0, $0.2) })
    func createFileTest(path: StoragePath, chunkSize: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        _ = try await storage.createFile(at: path, chunkSize: chunkSize).get()
    }
    
    @Test("文件数据覆写测试", arguments: fileList)
    func fileDataReplacementTest(path: StoragePath, data: ByteBuffer, chunkSize: Int64, replacings: [Replacing]) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let file = try await storage.getFile(at: path).get()
        
        let dataSize = Int64(data.readableBytes)
        
        try await file.withWriter { writer in
            writer.insert(at: .begin(), bytes: data)
        }.get()
        
        let fileCrypto = try #require(
            try await FileCrypto.query(on: storage.db)
                .filter(\.$id == file.id)
                .first()
        )
        
        #expect(fileCrypto.chunkSize == chunkSize)
        #expect(fileCrypto.lastTag == dataSize / chunkSize + ((dataSize % chunkSize == 0) ? 0 : 1))
        #expect(fileCrypto.encryptedSize == dataSize + Int64(fileCrypto.lastTag) * (Crypto.Symm.Stream.cipherExtraLength))
        
        var dataTest = data
        
        for replacing in replacings {
            print(dataTest.readableBytes)
            
            let fileData = try await file.withReadWriter { readWriter in
                readWriter.write(at: .begin(of: replacing.start), bytes: replacing.data, method: .replace).flatMap {
                    readWriter.readData(part: .all)
                }
            }.get()
            
            let replaceEndIndex = Int(replacing.start) + replacing.data.readableBytes
            
            var right = replaceEndIndex < dataTest.readableBytes ? dataTest.getSlice(at: replaceEndIndex, length: dataTest.readableBytes - replaceEndIndex)! : ByteBuffer()
            dataTest = dataTest.getSlice(at: 0, length: Int(replacing.start)) ?? ByteBuffer()
            
            dataTest.writeImmutableBuffer(replacing.data)
            dataTest.writeBuffer(&right)
            
//            print("dataTest: \(dataTest.getString(at: 0, length: dataTest.readableBytes) ?? "nil")")
//            print("fileData: \(fileData.getString(at: 0, length: fileData.readableBytes) ?? "nil")")
            
            #expect(dataTest == fileData)
            #expect(file.size == dataTest.readableBytes)
            
            let parts = try await FilePart.query(on: storage.db)
                .filter(\.$fileIndex.$id == file.id)
                .all()
            
            #expect(parts.reduce(0, { $0 + ($1.byteEnd - $1.byteStart) }) == dataTest.readableBytes)
            
            let zeroParts = try await FilePart.query(on: storage.db)
                .filter(\.$byteStart == \.$byteEnd)
                .all()
            
            #expect(zeroParts.count == 0)
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
    
    @Test("额外随机测试")
    func extraRandomTests() async throws {
        do {
            for i in 3..<10 {
                let filePath: StoragePath = .init(stringLiteral: "example-\(i).txt")
                let size = Int64.random(in: 10000..<300000)
                let chunkSize = Int64.random(in: 10..<10000)
                
                let times = Int.random(in: 2..<12)
                
                var replacings: [Replacing] = []
                var curSize = size
                
                for _ in 0..<times {
                    let index = Int64.random(in: 0..<curSize)
                    let size = Int.random(in: 0..<10000)
                    curSize = max(curSize, index + Int64(size))
                    
                    replacings.append((index, randomData(size: size)))
                }

                print("""
                (
                    file: "\(filePath)", 
                    data: randomData(size: \(size)), 
                    chunkSize: \(chunkSize), 
                    replacings: [
                        \(replacings.map { "(\($0.start), randomData(size: \($0.data.readableBytes)))" }.joined(separator: ",\n\t\t"))
                    ]
                ),
                """)
                try await self.createFileTest(path: filePath, chunkSize: chunkSize)
                try await self.fileDataReplacementTest(path: filePath, data: randomData(size: Int(size)), chunkSize: chunkSize, replacings: replacings)
            }
            try await self.emptyAllTest()
            try await self.emptyTest()
        } catch {
            try await self.emptyAllTest()
            try await self.emptyTest()
            throw error
        }
    }
    
    @MainActor
    @Test("测试结束")
    func end() async throws {
        TestingShared.testStage = .entryBasics
    }
}
