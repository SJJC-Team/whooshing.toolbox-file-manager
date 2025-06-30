import Testing
import ErrorHandle
import NIOFileSystem
import Foundation
@testable import FileStorage

@Suite("FileStorage 实体基本测试集", .serialized)
struct EntryBasicsTests {
    
    @Test("开始测试")
    func start() async throws {
        while await TestingShared.testStage != .entryBasics {
            sleep(1)
        }
    }
    
    @Test("文件创建测试")
    func createFileTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let testPath: StoragePath = "example.txt"
        
        let file = try await storage.createFile(at: testPath).get()
        
        #expect(file.name == testPath.last!)
        #expect(file.mimeType == .plain)
        #expect(file.path == testPath)
        #expect(file.size == 0)
        
        let fileTest = try await storage.getFile(at: testPath).get()
        
        #expect(file.id == fileTest.id)
        #expect(file.name == fileTest.name)
        #expect(file.mimeType == fileTest.mimeType)
        #expect(file.path == fileTest.path)
        #expect(file.size == fileTest.size)
        
        await #expect(throws: BscError<File.Errcase>.self) {
            try await storage.createFile(at: testPath).get()
        }
        
        try await file.delete(force: false).get()
        
        await #expect(throws: BscError<FileStorage.Errcase>.self) {
            try await storage.getFile(at: testPath).get()
        }
    }
    
    @Test("文件创建测试-软删除")
    func createFileSoftDeleteTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let testPath: StoragePath = "example.txt"
        
        let file = try await storage.createFile(at: testPath).get()
        
        #expect(file.name == testPath.last!)
        #expect(file.mimeType == .plain)
        #expect(file.path == testPath)
        #expect(file.size == 0)
        
        let fileTest = try await storage.getFile(at: testPath).get()
        
        #expect(file.id == fileTest.id)
        #expect(file.name == fileTest.name)
        #expect(file.mimeType == fileTest.mimeType)
        #expect(file.path == fileTest.path)
        #expect(file.size == fileTest.size)
        
        let (filePath, _) = try await fileTest.getRealFilePath()
        
        try await file.delete(force: false).get()
        
        await #expect(throws: BscError<FileStorage.Errcase>.self) {
            try await storage.getFile(at: testPath).get()
        }
        
        try await FileSystem.shared.removeItem(at: filePath)
    }
    
    @Test("在文件夹中文件创建测试")
    func createFileInDirectoryTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let testPath: StoragePath = "testing/0/1/2/3/4/5/example.txt"
        
        let file = try await storage.createFile(at: testPath, withIntermediateDirectories: true).get()
        
        #expect(file.name == testPath.last!)
        #expect(file.mimeType == .plain)
        #expect(file.path == testPath)
        #expect(file.size == 0)
        
        let fileTest = try await storage.getFile(at: testPath).get()
        
        #expect(file.id == fileTest.id)
        #expect(file.name == fileTest.name)
        #expect(file.mimeType == fileTest.mimeType)
        #expect(file.path == fileTest.path)
        #expect(file.size == fileTest.size)
        
        try await file.delete(force: false).get()
        
        await #expect(throws: BscError<FileStorage.Errcase>.self) {
            try await storage.getFile(at: testPath).get()
        }
    }
    
    @Test("在文件夹中文件创建测试-软删除")
    func createFileInDirectorySoftDeleteTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let testPath: StoragePath = "testing/0/1/2/3/4/5/example.txt"
        
        let file = try await storage.createFile(at: testPath, withIntermediateDirectories: true).get()
        
        #expect(file.name == testPath.last!)
        #expect(file.mimeType == .plain)
        #expect(file.path == testPath)
        #expect(file.size == 0)
        
        let fileTest = try await storage.getFile(at: testPath).get()
        
        #expect(file.id == fileTest.id)
        #expect(file.name == fileTest.name)
        #expect(file.mimeType == fileTest.mimeType)
        #expect(file.path == fileTest.path)
        #expect(file.size == fileTest.size)
        
        let (filePath, _) = try await fileTest.getRealFilePath()
        
        try await file.delete(force: false).get()
        
        await #expect(throws: BscError<FileStorage.Errcase>.self) {
            try await storage.getFile(at: testPath).get()
        }
        
        try await FileSystem.shared.removeItem(at: filePath)
    }
    
    @Test("删除嵌套文件夹")
    func deleteIntermediateDirectoriesTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let testPath: StoragePath = "testing/0/1/2/3/4/5"
        
        for i in (1...testPath.count).reversed() {
            let p = StoragePath(components: .init(testPath.components[0..<i]))
            
            let dir = try await storage.getDirectory(at: p).get()
            
            #expect(dir.name == p.last!)
            #expect(dir.path == p)
            
            try await dir.delete(force: false).get()
            
            await #expect(throws: BscError<FileStorage.Errcase>.self) {
                try await storage.getDirectory(at: p).get()
            }
        }
    }
    
    @Test("在文件夹中文件创建测试-应当失败")
    func createFileInDirectoryShouldFailTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let testPath: StoragePath = "testing/unknow/example.txt"
        
        await #expect(throws: BscError<FileStorage.Errcase>.self) {
            try await storage.createFile(at: testPath, withIntermediateDirectories: false).get()
        }
    }
    
    @Test("文件夹创建测试")
    func createDirectoryTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let testPath: StoragePath = "testing_directory"
        
        let dir = try await storage.createDirectory(at: testPath).get()
        
        #expect(dir.name == testPath.last!)
        #expect(dir.path == testPath)
        
        let dirTest = try await storage.getDirectory(at: testPath).get()
        
        #expect(dir.id == dirTest.id)
        #expect(dir.name == dirTest.name)
        #expect(dir.path == dirTest.path)
        
        await #expect(throws: BscError<File.Errcase>.self) {
            try await storage.createDirectory(at: testPath).get()
        }
        
        try await dir.delete(force: false).get()
        
        await #expect(throws: BscError<FileStorage.Errcase>.self) {
            try await storage.getDirectory(at: testPath).get()
        }
    }
    
    @Test("文件夹创建测试-应当失败")
    func createDirectoryShouldFailTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let testPath: StoragePath = "testing_directory/0/1/2/3/4/5"
        await #expect(throws: BscError<FileStorage.Errcase>.self) {
            try await storage.createDirectory(at: testPath).get()
        }
    }
    
    @Test("多层文件夹创建测试")
    func createDirectoryWithIntermediateTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let testPath: StoragePath = "testing_directory/1/2/4/5/6/7"
        
        let dir = try await storage.createDirectory(at: testPath, withIntermediateDirectories: true).get()
        
        #expect(dir.name == testPath.last!)
        #expect(dir.path == testPath)
        
        let dirTest = try await storage.getDirectory(at: testPath).get()
        
        #expect(dir.id == dirTest.id)
        #expect(dir.name == dirTest.name)
        #expect(dir.path == dirTest.path)
        
        try await dir.delete(force: false).get()
        
        await #expect(throws: BscError<FileStorage.Errcase>.self) {
            try await storage.getDirectory(at: testPath).get()
        }
    }
    
    @Test("删除嵌套文件夹")
    func deleteIntermediateDirectoriesTest2() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        let testPath: StoragePath = "testing_directory/1/2/4/5/6"
        
        for i in (1...testPath.count).reversed() {
            let p = StoragePath(components: .init(testPath.components[0..<i]))
            
            let dir = try await storage.getDirectory(at: p).get()
            
            #expect(dir.name == p.last!)
            #expect(dir.path == p)
            
            try await dir.delete(force: false).get()
            
            await #expect(throws: BscError<FileStorage.Errcase>.self) {
                try await storage.getDirectory(at: p).get()
            }
        }
    }
    
    @Test("数据库和文件系统中的数据应当为空")
    func emptyTest() async throws {
        let storage = try await TestingShared.getFileStorage()

        #expect(try await FileIndex.query(on: storage.db).all().count == 0)
        #expect(try await FileCrypto.query(on: storage.db).all().count == 0)
        #expect(try await FilePart.query(on: storage.db).withDeleted().all().count == 0)
        #expect(try await FileIndex.query(on: storage.db).withDeleted().all().count > 0)
        #expect(try await FileCrypto.query(on: storage.db).withDeleted().all().count > 0)
    }
    
    @Test("从主目录删除所有子文件夹和子文件")
    func emptyAllTest() async throws {
        let storage = try await TestingShared.getFileStorage()
        
        try await storage.rootDir.empty(force: true).get()
    }
    
    @Test("数据库和文件系统中的数据应当为空")
    func emptyTest2() async throws {
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
        TestingShared.testStage = .directory
    }
}
