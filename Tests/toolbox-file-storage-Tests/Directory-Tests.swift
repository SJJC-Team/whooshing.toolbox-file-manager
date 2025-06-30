import Testing
import ErrorHandle
import NIOFileSystem
import Foundation
@testable import FileStorage

@Suite("Directory 测试集", .serialized)
struct DirectoryTests {
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .directory {
            sleep(1)
        }
    }
    
    static let testDir: StoragePath = "testing/0/1/2/3/4/5"
    
    static let originDir = "origin_test_dir" + StoragePath(testDir.dropFirst().dropLast())
    
    static let dirList: [StoragePath] = [
        "a/b",
        "c",
        "d/e/f/g"
    ]
    static let fileList: [(StoragePath, File.MimeType)] = [
        ("a/b/file1.txt", .plain),
        ("file2.mp4", .mp4),
        ("d/e/f/g/file3.wav", .wav),
        ("c/file2.mp4", .mp4),
        ("file4.webp", .webp)
    ]
    
    @Test("创建测试文件夹")
    func createDirectoyrTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let dir = try await storage.createDirectory(at: Self.originDir, withIntermediateDirectories: true).get()
        
        #expect(dir.name == Self.originDir.last!)
        #expect(dir.path == Self.originDir)
        
        let dirTest = try await storage.getDirectory(at: Self.originDir).get()
        
        #expect(dir.id == dirTest.id)
        #expect(dir.name == dirTest.name)
        #expect(dir.path == dirTest.path)
    }
    
    @Test("文件夹移动测试")
    func moveTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let dir = try await storage.createDirectory(at: .init(stringLiteral: Self.testDir.last!), withIntermediateDirectories: true).get()
        
        let destination = try await storage.getDirectory(at: Self.originDir).get()
        
        let newDir = try await dir.move(to: destination).get()
        
        #expect(newDir.id == dir.id)
        #expect(newDir.name == Self.testDir.last!)
        #expect(newDir.path == Self.originDir + Self.testDir.last!)
    }
    
    @Test("文件夹重命名测试")
    func renameTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let dir = try await storage.getDirectory(at: .init(stringLiteral: Self.originDir.first!)).get()
        
        let newDir = try await dir.rename(as: Self.testDir.first!).get()
        
        let dirTest = try await storage.getDirectory(at: .init(stringLiteral: Self.testDir.first!)).get()
        
        #expect(newDir.id == dirTest.id)
        #expect(newDir.name == dirTest.name)
        #expect(newDir.path == dirTest.path)
        
        await #expect(throws: BscError<FileStorage.Errcase>.self) {
            try await storage.getDirectory(at: Self.originDir).get()
        }
    }
    
    @Test("在测试文件夹中创建子文件夹", arguments: dirList)
    func createDirectoryTest(path: StoragePath) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let testPath = Self.testDir + path
        
        let dir = try await storage.createDirectory(at: testPath, withIntermediateDirectories: true).get()
        
        #expect(dir.name == testPath.last!)
        #expect(dir.path == testPath)
        
        let dirTest = try await storage.getDirectory(at: testPath).get()
        
        #expect(dir.id == dirTest.id)
        #expect(dir.name == dirTest.name)
        #expect(dir.path == dirTest.path)
    }
    
    @Test("在测试文件夹中创建子文件", arguments: fileList)
    func createFileInDirectoryTest(path: StoragePath, mimeType: File.MimeType) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let testPath = Self.testDir + path
        
        let file = try await storage.createFile(at: testPath).get()
        
        #expect(file.name == testPath.last!)
        #expect(file.mimeType == mimeType)
        #expect(file.path == testPath)
        #expect(file.size == 0)
        
        let fileTest = try await storage.getFile(at: testPath).get()
        
        #expect(file.id == fileTest.id)
        #expect(file.name == fileTest.name)
        #expect(file.mimeType == fileTest.mimeType)
        #expect(file.path == fileTest.path)
        #expect(file.size == fileTest.size)
    }
    
    @Test("检查 subItems")
    func subItemsTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let dir = try await storage.getDirectory(at: Self.testDir).get()
        
        var fileCheck: [Bool] = .init(repeating: false, count: Self.fileList.count)
        var dirCheck: [Bool] = .init(repeating: false, count: Self.dirList.count)
        
        try await travel(dir: dir)
        
        #expect(fileCheck.allSatisfy { $0 == true } )
        #expect(dirCheck.allSatisfy { $0 == true } )
        
        func travel(dir: Directory) async throws {
            let entries = try await dir.subitems().get()
            
            var last = true
            
            for entry in entries {
                if let file = entry as? File {
                    let fileInfo = try #require(
                        Self.fileList.enumerated().first { element in
                            try element.element.0 == file.path.remove(Self.testDir, from: .head)
                        }
                    )
                    #expect(file.mimeType == fileInfo.element.1)
                    fileCheck[fileInfo.offset] = true
                } else if let dir = entry as? Directory {
                    last = false
                    
                    #expect(
                        try Self.dirList.first {
                            try $0.contains(dir.path.remove(Self.testDir, from: .head))
                        } != nil
                    )
                    try await travel(dir: dir)
                }
            }
            
            if last {
                let dirInfo = try #require(
                    Self.dirList.enumerated().first { element in
                        try element.element == dir.path.remove(Self.testDir, from: .head)
                    }
                )
                dirCheck[dirInfo.offset] = true
            }
        }
    }
    
    @Test("硬删除测试", arguments: dirList.enumerated().map { ($0, $1) })
    func hardDeletionTest(index: Int, path: StoragePath) async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let dir = try await storage.getDirectory(at: Self.testDir + path.first!).get()
        
        try await dir.empty(force: true).get()
        
        let storageDir = try await FileSystem.shared.openDirectory(atPath: .init(storage.storagePath))
        
        var entries: [DirectoryEntry] = []
        do {
            for try await entry in storageDir.listContents() {
                guard !entry.name.string.hasPrefix(".") else {
                    continue
                }
                entries.append(entry)
            }
            try await storageDir.close()
        } catch {
            try await storageDir.close()
        }
        
        let filtered = Self.fileList.filter { path, type in
            for i in 0...index {
                guard !path.contains(Self.dirList[i].first!) else {
                    return false
                }
            }
            return true
        }
        
        #expect(entries.count == filtered.count)
    }
    
    @Test("递归清空嵌套子文件夹")
    func directoryEmptyTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let dir = try await storage.getDirectory(at: .init(stringLiteral: Self.testDir.first!)).get()
        
        try await dir.empty(force: true).get()
        
        for i in (2...Self.testDir.count).reversed() {
            let p = StoragePath(components: .init(Self.testDir.components[0..<i]))
            
            await #expect(throws: BscError<FileStorage.Errcase>.self) {
                try await storage.getDirectory(at: p).get()
            }
        }
    }
    
    @Test("从主目录删除所有子文件夹和子文件")
    func emptyAllTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        try await storage.rootDir.empty(force: true).get()
        
        await #expect(throws: BscError<FileStorage.Errcase>.self) {
            try await storage.getDirectory(at: .init(stringLiteral: Self.testDir.first!)).get()
        }
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
        TestingShared.testStage = .file
    }
}
