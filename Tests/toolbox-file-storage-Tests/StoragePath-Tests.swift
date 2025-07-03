import Testing
@testable import FileStorage

@Suite("StoragePath 测试集")
struct StoragePathTests {
    @Test("测试使用组件初始化 StoragePath")
    func initWithComponents() {
        let path = StoragePath(components: ["user", "documents", "file.txt"])
        #expect(path.components == ["user", "documents", "file.txt"])
        #expect(path.string == "user/documents/file.txt")
    }

    @Test("测试通过字符串字面量初始化 StoragePath")
    func expressibleByStringLiteral() {
        let path: StoragePath = ["user", "documents", "file.txt"]
        #expect(path.components == ["user", "documents", "file.txt"])
        #expect(path.string == "user/documents/file.txt")
    }

    @Test("测试 StoragePath 的集合协议符合性")
    func collectionConformance() {
        let path: StoragePath = "a/b/c"
        #expect(path.count == 3)
        #expect(path.first == "a")
        #expect(path.last == "c")
        #expect(path[1] == "b")
    }

    @Test("测试 StoragePath 的等价比较")
    func equatableComparison() {
        let a: StoragePath = "x/y/z"
        let b: StoragePath = "x/y/z"
        let c: StoragePath = "x/y"
        #expect(a == b)
        #expect(a != c)
    }

    @Test("测试向 StoragePath 添加组件")
    func addComponents() {
        var path: StoragePath = "a/b"
        path = path + "c"
        #expect(path.components == ["a", "b", "c"])

        path = path + ["d", "e"]
        #expect(path.components == ["a", "b", "c", "d", "e"])

        let extra: StoragePath = "f/g"
        path = path + extra
        #expect(path.components == ["a", "b", "c", "d", "e", "f", "g"])
    }

    @Test("测试从 StoragePath 中移除组件")
    func removeComponents() throws {
        var path: StoragePath = "a/b/c/d"
        path = path.remove(of: 2)
        #expect(path.components == ["a", "b"])
    }

    @Test("测试判断子路径关系")
    func isSubPathCheck() {
        let a: StoragePath = "a/b"
        let b: StoragePath = "a/b/c/d"
        #expect(a.isPrefixPath(of: b))
        #expect(!a.isSuffixPath(of: b))
        #expect(!b.isSuffixPath(of: a))
    }

    @Test("测试从尾部移除子路径")
    func removeSubPathFromTail() throws {
        let path: StoragePath = "a/b/c/d"
        let result = path.remove("c/d", from: .tail)
        #expect(result == "a/b")
    }

    @Test("测试从头部移除子路径")
    func removeSubPathFromHead() throws {
        let path: StoragePath = "a/b/c/d"
        let result = path.remove("a/b", from: .head)
        #expect(result == "c/d")
    }

    @Test("测试从尾部移除组件数组")
    func removeComponentsFromTail() throws {
        let path: StoragePath = "a/b/c/d"
        let result = path.remove(["c", "d"], from: .tail)
        #expect(result == "a/b")
    }

    @Test("测试从头部移除组件数组")
    func removeComponentsFromHead() throws {
        let path: StoragePath = "a/b/c/d"
        let result = path.remove(["a", "b"], from: .head)
        #expect(result == "c/d")
    }

    @Test("测试添加空字符串对路径无影响")
    func addEmptyStringHasNoEffect() {
        let path: StoragePath = "a/b"
        let added = path + ""
        #expect(added == path)
    }

    @Test("测试添加单斜杠字符串对路径无影响")
    func addSingleSlashStringHasNoEffect() {
        let path: StoragePath = "a/b"
        let added = path + "/"
        #expect(added == path)
    }
    
    @Test("测试 + 函数")
    func addTest() async throws {
        var path: StoragePath = "a/b"
        path += "c/d/b"
        #expect(path.count == 5)
        
        let newPath = "c" + path
        #expect(newPath.string == "c/a/b/c/d/b")
        
        let path2 = ["yas", "icu"] + newPath
        #expect(path2.string == "yas/icu/c/a/b/c/d/b")
        
        let path3 = path2 + ["kk", "oie"]
        #expect(path3.string == "yas/icu/c/a/b/c/d/b/kk/oie")
        
        let path4 = "u/e/a/d" + path3
        #expect(path4.count == 14)
        
        let path5 = path4 + ["uu/e", "i"]
        #expect(path5.count == 16)
        
        let path6 = StoragePath(stringLiteral: "a/b") + "c" + "d" + ["e", "f", "g"] + "h/i" + StoragePath(stringLiteral: "j/k/l")
        #expect(path6.string == "a/b/c/d/e/f/g/h/i/j/k/l")
        #expect(path6.count == 12)
    }
    
    @Test("测试 - 函数")
    func minusTest() async throws {
        let path: StoragePath = "a/b/c/d/e/f/g/h/i/j/k/l/m/o/p/q"
        
        let path2 = path - "p/q"
        #expect(path2.string == "a/b/c/d/e/f/g/h/i/j/k/l/m/o")
        #expect(path2.count == 14)
        
        let path3 = "x/y/a/b/c/d/e/f/g/h/i/j/k/l/m/o" - path2
        #expect(path3.string == "x/y")
        #expect(path3.count == 2)
        
        let path4 = path2 - ["k", "l", "m", "o"]
        #expect(path4.string == "a/b/c/d/e/f/g/h/i/j")
        #expect(path4.count == 10)
        
        let path5 = ["z", "f", "k", "l"] + "a/b/c/d/e/f/g/h/i/j" - path4
        #expect(path5.string == "z/f/k/l")
        #expect(path5.count == 4)
        
        let path6 = path5 - 3
        #expect(path6.string == "z")
        #expect(path6.count == 1)
    }
    
    @Test("测试自增函数")
    func selfAddTest() async throws {
        var path: StoragePath = "a/b"
        path += "c/d"
        path += ["e", "f"]
        path += "g/h/i" + ["j", "k"]
        #expect(path.string == "a/b/c/d/e/f/g/h/i/j/k")
        #expect(path.count == 11)
    }
    
    @Test("测试自减函数")
    func selfMinusTest() async throws {
        var path: StoragePath = "x/y/z/a/b/c/d/e/f/g/h/i/j/k"
        path -= "i/j/k"
        path -= "f/g/h"
        path -= ["d", "e"]
        path -= ["c"]
        path -= 1
        path -= 2
        #expect(path.string == "x/y")
        #expect(path.count == 2)
    }
}
