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
        let path: StoragePath = "user/documents/file.txt"
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
        path = try path.remove(of: 2)
        #expect(path.components == ["a", "b"])
    }

    @Test("测试移除过多组件时抛出错误")
    func removeTooManyComponentsThrows() throws {
        let path: StoragePath = "a/b"
        #expect(throws: Error.self, performing: { try path.remove(of: 3) })
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
        let result = try path.remove("c/d", from: .tail)
        #expect(result == "a/b")
    }

    @Test("测试从头部移除子路径")
    func removeSubPathFromHead() throws {
        let path: StoragePath = "a/b/c/d"
        let result = try path.remove("a/b", from: .head)
        #expect(result == "c/d")
    }

    @Test("测试从尾部移除组件数组")
    func removeComponentsFromTail() throws {
        let path: StoragePath = "a/b/c/d"
        let result = try path.remove(components: ["c", "d"], from: .tail)
        #expect(result == "a/b")
    }

    @Test("测试从头部移除组件数组")
    func removeComponentsFromHead() throws {
        let path: StoragePath = "a/b/c/d"
        let result = try path.remove(components: ["a", "b"], from: .head)
        #expect(result == "c/d")
    }

    @Test("测试从尾部移除子路径失败情况")
    func removeSubPathFromTailFailure() {
        let path: StoragePath = "a/b/c"
        #expect(throws: Error.self, performing: {
            _ = try path.remove("c/c", from: .tail) // not an exact suffix
        })
    }

    @Test("测试从头部移除子路径失败情况")
    func removeSubPathFromHeadFailure() {
        let path: StoragePath = "a/b/c"
        #expect(throws: Error.self, performing: {
            _ = try path.remove("a/c", from: .head) // not an exact prefix
        })
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
    }
}
