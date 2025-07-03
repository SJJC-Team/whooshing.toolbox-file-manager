import Testing
import ErrorHandle
import NIOFileSystem
import Foundation
import FluentKit
import Cryptos
import NIOCore
@testable import FileStorage

@Suite("File 数据覆写测试集", .serialized, .enabled(if: TestingShared.dbListening))
struct FileReplacmentTests {
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .fileReplacemeng {
            sleep(1)
        }
    }
    
    typealias Replacing = (
        start: Int64,
        data: TestingData
    )
    
    static let fileList: [
        (
            file: StoragePath,
            data: TestingData,
            chunkSize: Int64,
            replacings: [Replacing]
        )
    ] = [
        (
            file: "example-0.txt",
            data: .string("Hello World! Testing String"),
            chunkSize: 5,
            replacings: [
                (0, .string("123")),
                (5, .string("456")),
                (10, .string("789")),
                (26, .string("10111213")),
            ]
        ),
        (
            file: "example-1.txt",
            data: .random(0),
            chunkSize: 4000,
            replacings: [
                (0, .random(3000)),
                (1000, .random(3500)),
                (4500, .random(7000)),
                (11500, .random(3000)),
                (14500, .random(2000)),
                (16500, .random(1000)),
                (0, .random(0)),
            ]
        ),
        (
            file: "example-2.txt",
            data: .random(200000),
            chunkSize: 10000,
            replacings: [
                (12343, .random(30100)),
                (12897, .random(32412)),
                (433, .random(34334)),
                (312, .random(1423)),
                (8643, .random(65485)),
                (2345, .random(45435))
            ]
        ),
    ]
    
    static let fileCreate = fileList.map { ($0.0, $0.2) }
    
    @Test("文件创建", arguments: fileCreate)
    func createFileTest(path: StoragePath, chunkSize: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        _ = try await storage.createFile(at: path, chunkSize: chunkSize).get()
    }
    
    @Test("文件数据覆写测试", arguments: fileList)
    func fileDataReplacementTest(path: StoragePath, testingData: TestingData, chunkSize: Int64, replacings: [Replacing]) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let file = try await storage.getFile(at: path).get()
        
        let data: ByteBuffer
        
        switch testingData {
        case .string(let s): data = ByteBuffer(string: s)
        case .random(let size): data = randomData(size: size)
        }
        
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
            
            let replacingData: ByteBuffer
            
            switch replacing.data {
            case .string(let s): replacingData = ByteBuffer(string: s)
            case .random(let size): replacingData = randomData(size: size)
            }
            
            let fileData = try await file.withReadWriter { readWriter in
                readWriter.write(at: .begin(of: replacing.start), bytes: replacingData, method: .replace).flatMap {
                    readWriter.readData(part: .all)
                }
            }.get()
            
            let replaceEndIndex = Int(replacing.start) + replacingData.readableBytes
            
            var right = replaceEndIndex < dataTest.readableBytes ? dataTest.getSlice(at: replaceEndIndex, length: dataTest.readableBytes - replaceEndIndex)! : ByteBuffer()
            dataTest = dataTest.getSlice(at: 0, length: Int(replacing.start)) ?? ByteBuffer()
            
            dataTest.writeImmutableBuffer(replacingData)
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
                let size = Int.random(in: 10000..<300000)
                let chunkSize = Int64.random(in: 10..<10000)
                
                let times = Int.random(in: 2..<12)
                
                var replacings: [Replacing] = []
                var curSize = Int64(size)
                
                for _ in 0..<times {
                    let index = Int64.random(in: 0..<curSize)
                    let size = Int.random(in: 0..<10000)
                    curSize = max(curSize, index + Int64(size))
                    
                    replacings.append((index, .random(size)))
                }

                print("""
                (
                    file: "\(filePath)", 
                    data: randomData(size: \(size)), 
                    chunkSize: \(chunkSize), 
                    replacings: [
                        \(replacings.map { replacing in
                            switch replacing.data {
                                case .random(let s): return "(\(replacing.start), .string(\(s)))"
                                case .string(let s): return "(\(replacing.start), .random(\(s)))"
                            }
                        }.joined(separator: ",\n\t\t"))
                    ]
                ),
                """)
                try await self.createFileTest(path: filePath, chunkSize: chunkSize)
                try await self.fileDataReplacementTest(path: filePath, testingData: .random(size), chunkSize: chunkSize, replacings: replacings)
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
