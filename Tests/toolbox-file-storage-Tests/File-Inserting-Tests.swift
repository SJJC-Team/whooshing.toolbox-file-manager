import Testing
import ErrorHandle
import NIOFileSystem
import Foundation
import FluentKit
import Cryptos
import NIOCore
@testable import FileStorage

@Suite("File 数据插入测试集", .serialized)
struct FileInsertionTests {
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .fileInsertion {
            sleep(1)
        }
    }
    
    typealias Insertion = (
        index: ByteIndex,
        data: ByteBuffer
    )
    
    static let fileList: [(StoragePath, ByteBuffer, Int64, [Insertion])] = [
        (
            file: "example-0.txt",
            data: ByteBuffer(string: "Hello World! Testing String"),
            chunkSize: 5,
            insertions: [
                (.begin(), ByteBuffer(string: "123")),
                (.begin(of: 5), ByteBuffer(string: "456")),
                (.begin(of: 10), ByteBuffer(string: "789")),
                (.begin(of: 26), ByteBuffer(string: "10111213")),
                (.end(of: 3), ByteBuffer(string: "end")),
                (.end(), ByteBuffer(string: "testing"))
            ]
        ),
        (
            file: "example-1.txt",
            data: randomData(size: 65535),
            chunkSize: 20,
            insertions: [
                (.begin(of: 65535), randomData(size: 10000)),
                (.begin(of: 8000), randomData(size: 4000)),
                (.end(of: 10000), randomData(size: 8192)),
                (.begin(of: 30), randomData(size: 6000))
            ]
        ),
        (
            file: "example-2.txt",
            data: randomData(size: 0),
            chunkSize: 100000,
            insertions: [
                (.begin(), randomData(size: 1000)),
                (.end(), randomData(size: 4000)),
                (.end(of: 2000), randomData(size: 3000)),
                (.begin(of: 0), randomData(size: 6000))
            ]
        )
    ]
    
    @Test("文件创建", arguments: fileList.map { ($0.0, $0.2) })
    func createFileTest(path: StoragePath, chunkSize: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        _ = try await storage.createFile(at: path, chunkSize: chunkSize).get()
    }
    
    @Test("文件数据插入测试", arguments: fileList)
    func fileDataInsertionTest(path: StoragePath, data: ByteBuffer, chunkSize: Int64, insertions: [Insertion]) async throws {
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
        
        for insertion in insertions {
            print(dataTest.readableBytes)
            
            let fileData = try await file.withReadWriter { readWriter in
                readWriter.write(at: insertion.index, bytes: insertion.data, method: .insert).flatMap {
                    readWriter.readData(part: .all)
                }
            }.get()
            
            let index: Int
            
            switch insertion.index {
            case .begin(of: let i):
                index = Int(i)
                
            case .end(of: let i):
                index = dataTest.readableBytes - Int(i)
            }
            
            var right = dataTest.getSlice(at: index, length: dataTest.readableBytes - index) ?? ByteBuffer()
            dataTest = dataTest.getSlice(at: 0, length: index) ?? ByteBuffer()
            
            dataTest.writeImmutableBuffer(insertion.data)
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
                
                var insertions: [Insertion] = []
                var curSize = size
                
                for _ in 0..<times {
                    let index = Int64.random(in: 0..<curSize)
                    let size = Int.random(in: 0..<10000)
                    curSize += Int64(size)
                    
                    insertions.append((Bool.random() ? .begin(of: index) : .end(of: index), randomData(size: size)))
                }
                
                print("""
                (
                    file: "\(filePath)", 
                    data: randomData(size: \(size)), 
                    chunkSize: \(chunkSize), 
                    insertions: [
                        \(insertions.map { insertion in
                            switch insertion.index {
                            case .begin(of: let i): return "(.begin(of: \(i)), randomData(size: \(insertion.data.readableBytes)))"
                            case .end(of: let i): return "(.end(of: \(i)), randomData(size: \(insertion.data.readableBytes)))"
                            }
                        }.joined(separator: ",\n\t\t"))
                    ]
                ),
                """)
                try await self.createFileTest(path: filePath, chunkSize: chunkSize)
                try await self.fileDataInsertionTest(path: filePath, data: randomData(size: Int(size)), chunkSize: chunkSize, insertions: insertions)
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
        TestingShared.testStage = .fileRemoving
    }
}
