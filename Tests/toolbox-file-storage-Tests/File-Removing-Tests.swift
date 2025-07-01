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
//    @Test("开始测试")
//    func start() async throws {
//        while await TestingShared.testStage != .fileRemoving {
//            sleep(1)
//        }
//    }
    
    typealias RemovingData = (
        range: Range<Int64>,
        byteParts: [Range<Int64>],
        encryptedParts: [(
            range: Range<Int64>,
            headIgnore: Int64,
            tailIgnore: Int64
        )]
    )
//    Hello World! Testing String
//    <->     <------>
//    Hello World! Testing String
//    <->  <------>
    static let fileList: [(StoragePath, ByteBuffer, Int64, [Range<Int64>])] = [
        (
            file: "example-0.txt",
            data: ByteBuffer(string: "Hello World! Testing String"),
            chunkSize: 5,
            removings: [
                0..<3,
                6..<13
            ]
        ),
//        (
//            file: "example-1.txt",
//            data: randomData(size: 65535 * 5),
//            chunkSize: 12343,
//            removings: [
//                0..<500,
//                200000..<300000,
//                0..<227175,
//                0..<0
//            ]
//        ),
//        (
//            file: "example-2.txt",
//            chunkSize: 200,
//            firstInsert: 2000 * 10,
//            removings: [
//                0..<500,
//                1..<1,
//                300..<8000
//            ]
//        ),
//        (
//            file: "example-3.txt",
//            chunkSize: 30000,
//            firstInsert: 1,
//            removings: [
//                0..<0,
//                0..<1
//            ]
//        )
    ]
    
//    removings: [
//        (
//            500..<1000,
//            [
//                0..<500,
//                500..<327175
//            ], [
//                (0..<12371, 0, 11843),
//                (0..<328431, 1000, 0)
//            ]
//        ),
//        (
//            200000..<300000,
//            [
//                0..<500,
//                500..<200000,
//                200000..<227175
//            ], [
//                (0..<12371, 0, 11843),
//                (0..<210307, 1000, 10331),
//                (296904..<328431, 3268, 0)
//            ]
//        )
//    ]
    
    @Test("文件创建", arguments: fileList.map { ($0.0, $0.2) })
    func createFileTest(path: StoragePath, chunkSize: Int64) async throws {
        let storage = try await TestingShared.getFileStorage()
        _ = try await storage.createFile(at: path, chunkSize: chunkSize).get()
    }
    
    @Test("文件写入", arguments: fileList)
    func fileWriteTest(path: StoragePath, data: ByteBuffer, chunkSize: Int64, removings: [Range<Int64>]) async throws {
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
        
        for removing in removings {
            try await file.withWriter { writer in
                writer.remove(in: removing)
            }.get()
            
            let fileData = try await file.withReader { reader in
                reader.readData(part: .all)
            }.get()
            
            var right = dataTest.getSlice(at: Int(removing.upperBound), length: dataTest.readableBytes - Int(removing.upperBound)) ?? ByteBuffer()
            dataTest = dataTest.getSlice(at: 0, length: Int(removing.lowerBound)) ?? ByteBuffer()
            
            dataTest.writeBuffer(&right)
            
            print("dataTest: \(dataTest.getString(at: 0, length: dataTest.readableBytes) ?? "nil")")
            print("fileData: \(fileData.getString(at: 0, length: fileData.readableBytes) ?? "nil")")
            
            #expect(dataTest == fileData)
        }
    }
    
//    @Test("删除数据", arguments: fileList.map { ($0.0, $0.3) })
//    func fileDataRemoveTest(path: StoragePath, removings: [RemovingData]) async throws {
//        let storage = try await TestingShared.getFileStorage()
//        
//        let file = try await storage.getFile(at: path).get()
//        
//        for removing in removings {
//            try await file.withWriter { writer in
//                writer.remove(in: removing.range)
//            }.get()
//            
//            let parts = try await FilePart.query(on: storage.db)
//                .filter(\.$fileIndex.$id == file.id)
//                .sort(\.$byteStart, .ascending)
//                .all()
//            
//            #expect(parts.count == removing.byteParts.count)
//            
//            for (i, part) in parts.enumerated() {
//                #expect(part.byteStart == removing.byteParts[i].lowerBound)
//                #expect(part.byteEnd == removing.byteParts[i].upperBound)
//                #expect(part.encryptedStart == removing.encryptedParts[i].range.lowerBound)
//                #expect(part.encryptedEnd == removing.encryptedParts[i].range.upperBound)
//                #expect(part.byteHeadIgnore == removing.encryptedParts[i].headIgnore)
//                #expect(part.byteTailIgnore == removing.encryptedParts[i].tailIgnore)
//            }
//        }
//    }
    
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
