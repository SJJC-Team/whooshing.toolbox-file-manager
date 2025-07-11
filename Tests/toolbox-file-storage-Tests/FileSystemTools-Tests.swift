import Testing
import Foundation
@testable import FileStorage

@Suite("FileSystemTools 测试集")
struct FileSystemToolsTests {
    @Test("路径拼接")
    func pathResolveTest() async throws {
        let path = FileSystemTools.resolvePath(basePath: "/", append: "hello")
        #expect(path == "/hello")
        
        let path2 = FileSystemTools.resolvePath(basePath: "/", append: "./hello")
        #expect(path2 == "/hello")
    }
    
    @Test("路径拼接 2")
    func pathResolveTest2() async throws {
        let path = FileSystemTools.resolvePath(basePath: "/testing", append: "./hello")
        #expect(path == "/testing/hello")
        
        let path2 = FileSystemTools.resolvePath(append: "./hello")
        #expect(path2 == "\(FileManager.default.currentDirectoryPath)/hello")
    }
    
    @Test("路径拼接 3")
    func pathResolveTest3() async throws {
        let path = FileSystemTools.resolvePath(basePath: "/testing", append: "../hello")
        #expect(path == "/hello")
        
        let path2 = FileSystemTools.resolvePath(basePath: "/testing/1/2/3", append: "../../hello")
        #expect(path2 == "/testing/1/hello")
    }
    
    @Test("路径拼接 4")
    func pathResolveTest4() async throws {
        let path = FileSystemTools.resolvePath(basePath: "/", append: "~/testing")
        #expect(path == "\(FileManager.default.homeDirectoryForCurrentUser.appending(component: "testing").path())")
        
        let path2 = FileSystemTools.resolvePath(basePath: "/", append: "/testing")
        #expect(path2 == "/testing")
        
        let path3 = FileSystemTools.resolvePath(basePath: "/", append: "/hello/world/testing/image.png")
        #expect(path3 == "/hello/world/testing/image.png")
    }
    
    @Test("路径拼接 5")
    func pathResolveTest5() async throws {
        let path = FileSystemTools.resolvePath(append: "~/testing")
        #expect(path == "\(FileManager.default.homeDirectoryForCurrentUser.appending(component: "testing").path())")
        
        let path2 = FileSystemTools.resolvePath(basePath: "/1/2/3/4/5", append: "~/testing")
        #expect(path2 == "\(FileManager.default.homeDirectoryForCurrentUser.appending(component: "testing").path())")
        
        let path3 = FileSystemTools.resolvePath(basePath: "~/1/2/3/4/5", append: "~/testing")
        #expect(path3 == "\(FileManager.default.homeDirectoryForCurrentUser.appending(component: "testing").path())")
    }
}
