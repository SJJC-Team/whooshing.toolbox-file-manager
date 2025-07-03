import Testing
import ErrorHandle
import NIOFileSystem
import Foundation
import FluentKit
import Cryptos
import NIOCore
@testable import FileStorage

@Suite("File 数据删除测试集", .serialized)
struct FileRemovingTests {
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .fileRemoving {
            sleep(1)
        }
    }
    
    typealias RemovingData = (
        range: Range<Int64>,
        byteParts: [Range<Int64>],
        encryptedParts: [(
            range: Range<Int64>,
            headIgnore: Int64,
            tailIgnore: Int64
        )]
    )
    
    static let fileList: [(StoragePath, TestingData, Int64, [Range<Int64>])] = [
        (
            file: "example-0.txt",
            data: .string("Hello World! Testing String"),
            chunkSize: 5,
            removings: [
                0..<3,
                6..<13
            ]
        ),
        (
            file: "example-1.txt",
            data: .random(65535 * 5),
            chunkSize: 12343,
            removings: [
                0..<500,
                200000..<300000,
                0..<227175,
                0..<0
            ]
        ),
        (
            file: "example-2.txt",
            data: .random(2000 * 10),
            chunkSize: 200,
            removings: [
                0..<500,
                1..<1,
                300..<8000
            ]
        ),
        (
            file: "example-3.txt",
            firstInsert: .random(1),
            chunkSize: 30000,
            removings: [
                0..<0,
                0..<1
            ]
        ),
        (
            file: "example-4.txt",
            firstInsert: .random(500000),
            chunkSize: 30000,
            removings: [
                100000..<110000,
                200000..<250000,
                300000..<310000,
                100..<250,
                1000..<330000
            ]
        ),
        (
            file: "example-5.txt",
            firstInsert: .random(100000),
            chunkSize: 3000,
            removings: [
                3000..<7800,
                1020..<5000
            ]
        ),
        (
            file: "example-6.txt",
            firstInsert: .random(100000),
            chunkSize: 3000,
            removings: [
                4000..<9000,
                1234..<3122
            ]
        ),
        (
            file: "example-7.txt",
            firstInsert: .random(100000),
            chunkSize: 1000,
            removings: [
                3000..<4000,
                0..<6050
            ]
        ),
        (
            file: "example-8.txt",
            firstInsert: .random(100000),
            chunkSize: 1000,
            removings: [
                3000..<4000,
                5000..<6000,
                2300..<5000
            ]
        ),
        (
            file: "example-9.txt",
            firstInsert: .random(100000),
            chunkSize: 1000,
            removings: [
                3000..<4000,
                5000..<6000,
                0..<5000
            ]
        ),
        (
            file: "example-10.txt",
            firstInsert: .random(10000),
            chunkSize: 1000,
            removings: [
                3000..<4000,
                2300..<9000
            ]
        )
    ]
    
    @Test("文件创建", arguments: fileList.map { ($0.0, $0.2) })
    func createFileTest(path: StoragePath, chunkSize: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        _ = try await storage.createFile(at: path, chunkSize: chunkSize).get()
    }
    
    @Test("文件数据抹除测试", arguments: fileList)
    func fileDataRemoveTest(path: StoragePath, testingData: TestingData, chunkSize: Int64, removings: [Range<Int64>]) async throws {
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
        
        for removing in removings {
            print(dataTest.readableBytes)
            
            let fileData = try await file.withReadWriter { readWriter in
                readWriter.remove(in: removing).flatMap {
                    readWriter.readData(part: .all)
                }
            }.get()
            
            var right = dataTest.getSlice(at: Int(removing.upperBound), length: dataTest.readableBytes - Int(removing.upperBound)) ?? ByteBuffer()
            dataTest = dataTest.getSlice(at: 0, length: Int(removing.lowerBound)) ?? ByteBuffer()
            
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
            for i in 5..<10 {
                let filePath: StoragePath = .init(stringLiteral: "example-\(i).txt")
                let size = Int.random(in: 10000..<300000)
                let chunkSize = Int64.random(in: 10..<10000)
                
                let times = Int.random(in: 2..<12)
                
                var removings: [Range<Int64>] = []
                var curSize = Int64(size)
                
                for _ in 0..<times {
                    let lower = Int64.random(in: 0..<curSize)
                    let upper = Int64.random(in: lower..<curSize)
                    curSize -= upper - lower
                    
                    let removing = lower..<upper
                    removings.append(removing)
                    guard curSize > 0 else { break }
                }
                
                print("""
                (
                    file: "\(filePath)", 
                    data: .random(\(size)), 
                    chunkSize: \(chunkSize), 
                    removings: [
                        \(removings.map { $0.description }.joined(separator: ",\n\t\t"))
                    ]
                ),
                """)
                try await self.createFileTest(path: filePath, chunkSize: chunkSize)
                try await self.fileDataRemoveTest(path: filePath, testingData: .random(size), chunkSize: chunkSize, removings: removings)
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
        TestingShared.testStage = .fileReplacemeng
    }
}
