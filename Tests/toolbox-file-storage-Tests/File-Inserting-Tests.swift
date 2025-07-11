import Testing
import ErrorHandle
import NIOFileSystem
import Foundation
import FluentKit
import Cryptos
import NIOCore
@testable import FileStorage

@Suite("File 数据插入测试集", .serialized, .enabled(if: TestingShared.dbListening))
struct FileInsertionTests {
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .fileInsertion {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
    
    typealias Insertion = (
        index: ByteIndex,
        data: TestingData
    )
    
    static let fileList: [
        (
            file: StoragePath,
            data: TestingData,
            chunkSize: Int64,
            insertions: [Insertion]
        )
    ] = [
        (
            file: "example-0.txt",
            data: .string("Hello World! Testing String"),
            chunkSize: 5,
            insertions: [
                (.begin(), .string("123")),
                (.begin(of: 5), .string("456")),
                (.begin(of: 10), .string("789")),
                (.begin(of: 26), .string("10111213")),
                (.end(of: 3), .string("end")),
                (.end(), .string("testing"))
            ]
        ),
        (
            file: "example-1.txt",
            data: .random(65535),
            chunkSize: 20,
            insertions: [
                (.begin(of: 65535), .random(10000)),
                (.begin(of: 8000), .random(4000)),
                (.end(of: 10000), .random(8192)),
                (.begin(of: 30), .random(6000))
            ]
        ),
        (
            file: "example-2.txt",
            data: .random(0),
            chunkSize: 100000,
            insertions: [
                (.begin(), .random(1000)),
                (.end(), .random(4000)),
                (.end(of: 2000), .random(3000)),
                (.begin(of: 0), .random(6000))
            ]
        )
    ]
    
    static let fileCreate = fileList.map { ($0.0, $0.2) }
    
    @Test("文件创建", arguments: fileCreate)
    func createFileTest(path: StoragePath, chunkSize: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        _ = try await storage.createFile(at: path, chunkSize: chunkSize)
    }
    
    @Test("文件数据插入测试", arguments: fileList)
    func fileDataInsertionTest(path: StoragePath, testingData: TestingData, chunkSize: Int64, insertions: [Insertion]) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let file = try await storage.getFile(at: path)
        
        let data: Data
        
        switch testingData {
        case .string(let s): data = s.data(using: .utf8)!
        case .random(let size): data = randomData(size: size)
        }
        
        let dataSize = Int64(data.count)
        
        try await file.withWriter { writer in
            try await writer.insert(at: .begin(), bytes: data)
        }
        
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
            print(dataTest.count)
            
            let insertData: Data
            
            switch insertion.data {
            case .string(let s): insertData = s.data(using: .utf8)!
            case .random(let size): insertData = randomData(size: size)
            }
            
            let fileData = try await file.withReadWriter { readWriter in
                try await readWriter.write(at: insertion.index, bytes: insertData, method: .insert)
                return try await readWriter.readData(part: .all)
            }
            
            let index: Int
            
            switch insertion.index {
            case .begin(of: let i):
                index = Int(i)
                
            case .end(of: let i):
                index = dataTest.count - Int(i)
            }
            
            let right = dataTest.subdata(in: index..<dataTest.count)
            dataTest = dataTest.subdata(in: 0..<index)
            
            dataTest += insertData
            dataTest += right
            
//            print("dataTest: \(dataTest.getString(at: 0, length: dataTest.readableBytes) ?? "nil")")
//            print("fileData: \(fileData.getString(at: 0, length: fileData.readableBytes) ?? "nil")")
            
            #expect(dataTest == fileData)
            #expect(file.size == dataTest.count)
            
            let parts = try await FilePart.query(on: storage.db)
                .filter(\.$fileIndex.$id == file.id)
                .all()
            
            #expect(parts.reduce(0, { $0 + ($1.byteEnd - $1.byteStart) }) == dataTest.count)
            
            let zeroParts = try await FilePart.query(on: storage.db)
                .filter(\.$byteStart == \.$byteEnd)
                .all()
            
            #expect(zeroParts.count == 0)
        }
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
                    
                    insertions.append((Bool.random() ? .begin(of: index) : .end(of: index), .random(size)))
                }
                
                print("""
                (
                    file: "\(filePath)", 
                    data: randomData(size: \(size)), 
                    chunkSize: \(chunkSize), 
                    insertions: [
                        \(insertions.map { insertion in
                            switch insertion.index {
                            case .begin(of: let i):
                                switch insertion.data {
                                    case .random(let s): return "(.begin(of: \(i)), .random(\(s)))"
                                    case .string(let s): return "(.begin(of: \(i)), .string(\(s.count)))"
                                }
                            case .end(of: let i):
                                    switch insertion.data {
                                        case .random(let s): return "(.end(of: \(i)), .random(\(s)))"
                                        case .string(let s): return "(.end(of: \(i)), .string(\(s.count)))"
                                    }
                            }
                        }.joined(separator: ",\n\t\t"))
                    ]
                ),
                """)
                try await self.createFileTest(path: filePath, chunkSize: chunkSize)
                try await self.fileDataInsertionTest(path: filePath, testingData: .random(Int(size)), chunkSize: chunkSize, insertions: insertions)
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
