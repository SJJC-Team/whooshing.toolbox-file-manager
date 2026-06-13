import ErrorHandle
import Foundation
import LoggingAdvanced

/// 该模块 `FileStorage` 中存储的文件的相对路径结构体，封装路径的组成部分并提供路径操作。
///
/// 该类型表示一个标准化的路径，支持路径的拼接、删除子路径等操作。
///
/// #### 创建一个 `StoragePath` 对象
///
/// 直接使用字符串字面量初始化
/// ``` swift
/// let path: StoragePath = "user/documents/file.txt"
/// print(path)         // <-- print: user/documents/file.txt
/// ```
///
/// 使用数组字面两初始化
/// ``` swift
/// let path: StoragePath = ["user", "documents", "file.txt"]
/// print(path)         // <-- print: user/documents/file.txt
/// ```
///
/// 使用构造函数初始化
/// ``` swift
/// let path = StoragePath(stringLiteral: "user/documents/file.txt")
/// print(path)         // <-- print: user/documents/file.txt
/// ```
///
/// 也可以提供路径链进行初始化
/// ``` swift
/// let path = StoragePath(components: ["user", "documents", "file.txt"])
/// print(path)         // <-- print: user/documents/file.txt
/// ```
///
/// #### 遍历路径链
/// 对比由一个字符串表示的文件路径，该类型可以使用 for in 遍历其每个组成部分，
/// 以下例子将会遍历其路径中的所有三个项目:
///
/// 分别是 String 类型的 `[user, documents, file.txt]`
/// ``` swift
/// let path: StoragePath = "user/documents/file.txt"
/// for component in path {
///     print(component)
///     // 第一次 print: user
///     // 第二次 print: documents
///     // 第三次 print: file.txt
/// }
/// ```
///
/// #### 路径操作
/// 你也可以方便地进行路径拼接操作，该类型提供多种拼接操作：
///
/// 将一个字符串追加到最后
/// ``` swift
/// let path: StoragePath = "a/b"
/// let path2 = path + "c"
/// print(path2)            // <-- print: a/b/c
/// print(path2.count)      // <-- print: 3
/// ```
///
/// 也可以支持链式添加以数组形式，字符串形式以及 StoragePath 类型
/// ``` swift
/// let path: StoragePath = "a/b/c"
/// let path2 = path + "d/e" + "f/g" + ["h", "i", "j"] + StoragePath(stringLiteral: "k/l/m")
/// print(path2)            // <-- print: a/b/c/d/e/f/g/h/i/j/k/l/m
/// print(path2.count)      // <-- print: 13
/// ```
///
/// 或者选择将字符串加至路径开头
/// ``` swift
/// let path: StoragePath = "d/e/f"
/// let path2 = "a" + ["b", "c"] + path
/// print(path2)            // <-- print: a/b/c/d/e/f
/// print(path2.count)      // <-- print: 6
/// ```
///
/// 或自增
/// ``` swift
/// var path: StoragePath = "a/b"
/// path += "c/d/e"
/// path += ["f", "g", "h"]
/// print(path)             // <-- print: a/b/c/d/e/f/g/h
/// print(path.count)       // <-- print: 8
/// ```
///
/// 你也可以不使用运算符重载函数们，采用函数调用的方式
/// ``` swift
/// let path: StoragePath = "a/b/c"
/// let path2 = path.add("d/e", to: .tail)
/// print(path2)            // <-- print: a/b/c/d/e
/// ```
///
/// 删除操作，对于删除操作，你也可以使用 -, -= 运算符或 remove(_, from: _) 函数
///
/// 使用 - 进行裁剪，运算符左侧或右侧可以指定：
///     - 字符串
///     - 字符串数组
///     - StoragePath 实例
///     - 数字(指定从尾部删除几个组件)
///
/// ``` swift
/// let path: StoragePath = "a/b/c/d/e/f/g/h/i/j/k/l/m/o/p/q"
///
/// let path2 = path - "p/q"
/// print(path2.string)     // <-- print: a/b/c/d/e/f/g/h/i/j/k/l/m/o
/// print(path2.count)      // <-- print: 14
///
/// let path3 = "x/y/a/b/c/d/e/f/g/h/i/j/k/l/m/o" - path2
/// print(path3.string)     // <-- print: x/y
/// print(path3.count)      // <-- print: 2
///
/// let path4 = path2 - ["k", "l", "m", "o"]
/// print(path4.string)     // <-- print: a/b/c/d/e/f/g/h/i/j
/// print(path4.count)      // <-- print: 10
///
/// let path5 = ["z", "f", "k", "l"] + "a/b/c/d/e/f/g/h/i/j" - path4
/// print(path5.string)     // <-- print: z/f/k/l
/// print(path5.count)      // <-- print: 4
///
/// let path6 = path5 - 3
/// print(path6.string)     // <-- print: z
/// print(path6.count)      // <-- print: 1
/// ```
/// 使用 -= 自减:
/// ``` swift
/// var path: StoragePath = "x/y/z/a/b/c/d/e/f/g/h/i/j/k"
/// path -= "i/j/k"
/// path -= "f/g/h"
/// path -= ["d", "e"]
/// path -= ["c"]
/// path -= 1
/// path -= 2
/// print(path.string)      // <-- print: x/y
/// print(path.count)       // <-- print: 2
/// ```
///
/// - Warning: `FileStorage` 模块中的每个文件并不真实存在于文件系统中，无论是路径还是内容，
/// 从文件系统中都是不可读的。该类型 `StoragePath` 仅仅模仿文件系统，抽象了文件
/// 在该系统中的路径。请勿与普通的文件路径混用，勿使用该路径直接从文件系统中读取数据。
@frozen
public struct StoragePath: Sendable {
    
    /// 路径的组成部分数组。
    public let components: [String]
    
    /// 路径的字符串形式，使用 `/` 分隔。
    public let string: String
    
    /// 空路径，表示根路径。
    public static let root = StoragePath(components: [])
    
    /// 通过路径组件数组初始化。
    /// - Parameter components: 路径组件数组。
    @inlinable
    public init(components: [String]) {
        self.components = components
        self.string = components.joined(separator: "/")
    }
    
    /// 通过同类型切片初始化。
    /// - Parameter slice: StoragePath 的切片。
    @inlinable
    public init(_ slice: Slice<Self>) {
        var comps: [String] = []
        for c in slice {
            comps.append(c)
        }
        self.init(components: comps)
    }
}

extension StoragePath: CustomStringConvertible, Loggerable {
    /// 路径的描述字符串，即路径字符串。
    @inlinable
    public var description: String { self.string }
    
    @inlinable
    public var summaryDescription: String { self.string }
}

extension StoragePath: ExpressibleByStringLiteral {
    /// 通过字符串字面量初始化，自动拆分路径组件。
    /// - Parameter value: 字符串字面量。
    @inlinable
    public init(stringLiteral value: StringLiteralType) {
        self.components = value.components(separatedBy: "/").filter { !$0.isEmpty }
        self.string = components.joined(separator: "/")
    }
}

extension StoragePath: ExpressibleByArrayLiteral {
    /// 通过路径组件数组字面量初始化。
    /// - Parameter value: 字符串字面量。
    @inlinable
    public init(arrayLiteral elements: String...) {
        self.init(components: elements)
    }
}

extension StoragePath: Collection {
    /// 集合起始索引。
    @inlinable
    public var startIndex: Int { components.startIndex }
    
    /// 集合结束索引。
    @inlinable
    public var endIndex: Int { components.endIndex }
    
    /// 路径最后一个组件。
    @inlinable
    public var last: String? { components.last }
    
    /// 是否为空路径（根路径）。
    @inlinable
    public var isRoot: Bool { isEmpty }
    
    /// 获取父路径。
    ///
    /// - Returns: 父路径。
    /// - Note: 根路径无父路径，调用将导致运行时错误。
    @inlinable
    public var parent: StoragePath {
        guard !self.isRoot else { preconditionFailure("无法获取根目录的父目录") }
        var comps = self.components
        comps.removeLast()
        return .init(components: comps)
    }
    
    /// 获取下一个索引。
    /// - Parameter i: 当前索引。
    /// - Returns: 下一个索引。
    @inlinable
    public func index(after i: Int) -> Int {
        components.index(after: i)
    }
    
    /// 根据索引获取路径组件。
    /// - Parameter position: 组件索引。
    /// - Returns: 路径组件字符串。
    @inlinable
    public subscript(position: Int) -> String {
        get {
            components[position]
        }
    }
}

extension StoragePath: Equatable, AdditiveArithmetic {
    @inlinable
    public static var zero: StoragePath { .root }
    
    /// 判断两个路径是否相等（组件逐一比较）。
    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.components == rhs.components
    }
    
    /// 路径拼接：追加字符串组件。
    @inlinable public static func + (lhs: StoragePath, rhs: String) -> StoragePath { lhs.add(rhs, to: .tail) }
    /// 路径拼接：字符串 + 路径，将字符串添加到路径头。
    @inlinable public static func + (lhs: String, rhs: StoragePath) -> StoragePath { rhs.add(lhs, to: .head) }
    /// 路径拼接：追加另一路径组件。
    @inlinable public static func + (lhs: StoragePath, rhs: StoragePath) -> StoragePath { lhs.add(rhs, to: .tail) }
    
    
    /// 路径拼接：裁剪尾组件。
    @inlinable public static func - (lhs: StoragePath, rhs: String) -> StoragePath { lhs.remove(rhs, from: .tail) }
    /// 路径拼接：裁剪尾组件。
    @inlinable public static func - (lhs: String, rhs: StoragePath) -> StoragePath { StoragePath(stringLiteral: lhs).remove(rhs, from: .tail) }
    /// 路径拼接：从尾裁剪 rhs 数量的组件。
    @inlinable public static func - (lhs: StoragePath, rhs: Int) -> StoragePath { lhs.remove(of: rhs, from: .tail) }
    /// 路径拼接：从尾裁剪一个 path。
    @inlinable public static func - (lhs: StoragePath, rhs: StoragePath) -> StoragePath { lhs.remove(rhs, from: .tail) }
    
    
    /// 路径拼接赋值操作：追加路径。
    @inlinable public static func += (lhs: inout StoragePath, rhs: String) { lhs = lhs + rhs }
    /// 路径拼接赋值操作：追加路径。
    @inlinable public static func += (lhs: inout StoragePath, rhs: StoragePath) { lhs = lhs + rhs }
    
    
    /// 路径拼接赋值操作：从尾裁剪组件。
    @inlinable
    public static func -= (lhs: inout StoragePath, rhs: String) { lhs = lhs - rhs }
    /// 路径拼接赋值操作：从尾裁剪 rhs 数量的组件。
    @inlinable
    public static func -= (lhs: inout StoragePath, rhs: Int) { lhs = lhs - rhs }
    /// 路径拼接赋值操作：从尾裁剪一个 path。
    @inlinable
    public static func -= (lhs: inout StoragePath, rhs: StoragePath) { lhs = lhs - rhs }
}

extension StoragePath: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let components = try container.decode([String].self)
        self.init(components: components)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.components)
    }
}

extension StoragePath {
    /// 方向枚举
    @frozen
    public enum Direction {
        case head
        case tail
    }
    
    /// 判断当前路径是否是指定路径的前缀路径。
    ///
    /// - Parameter path: 待比较路径。
    /// - Returns: 如果是前缀路径，返回 true。
    @inlinable
    public func isPrefixPath(of path: StoragePath) -> Bool {
        guard path.count >= self.count else { return false }
        for (i, name) in components.enumerated() {
            guard path.components[i] == name else { return false }
        }
        return true
    }
    
    /// 判断当前路径是否是指定路径的后缀路径。
    ///
    /// - Parameter path: 待比较路径。
    /// - Returns: 如果是后缀路径，返回 true。
    @inlinable
    public func isSuffixPath(of path: StoragePath) -> Bool {
        guard path.count >= self.count else { return false }
        for (i, name) in components.reversed().enumerated() {
            guard path.components[path.count - 1 - i] == name else { return false }
        }
        return true
    }
    
    /// 追加字符串组件并返回新路径。
    /// - Parameter component: 字符串组件，支持包含多个用 `/` 分隔的部分。
    /// - Returns: 新路径。
    @inlinable
    public func add(_ component: String, to direction: Direction = .tail) -> StoragePath {
        let newComponents = component.components(separatedBy: "/").filter { !$0.isEmpty }
        return add(components: newComponents, to: direction)
    }
    
    /// 追加多个字符串组件并返回新路径。
    /// - Parameter components: 字符串数组。
    /// - Returns: 新路径。
    @inlinable
    public func add(components: [String], to direction: Direction = .tail) -> StoragePath {
        switch direction {
        case .head: return .init(components: components + self.components)
        case .tail: return .init(components: self.components + components)
        }
    }
    
    /// 追加另一路径的组件并返回新路径。
    /// - Parameter path: 另一路径。
    /// - Returns: 新路径。
    @inlinable
    public func add(_ path: StoragePath, to direction: Direction = .tail) -> StoragePath {
        switch direction {
        case .head: return .init(components: path.components + self.components)
        case .tail: return .init(components: self.components + path.components)
        }
    }
    
    /// 删除指定子路径（字符串）从指定方向（尾部或头部）。
    ///
    /// - Parameters:
    ///   - subPath: 要删除的子路径字符串。
    ///   - direction: 删除方向，默认为尾部。
    ///
    /// - Returns: 删除后的新路径。
    ///
    /// - Warning: 所要删除的路径串必须为原路径的子串，头子串或尾子串取决于删除方向
    /// 若非子串，会引发程序断言，导致崩溃
    @inlinable
    public func remove(_ subPath: String, from direction: Direction = .tail) -> StoragePath {
        remove(StoragePath(stringLiteral: subPath), from: direction)
    }
    
    /// 删除指定字符串组件数组从指定方向。
    ///
    /// - Parameters:
    ///   - components: 要删除的字符串数组。
    ///   - direction: 删除方向。
    ///
    /// - Returns: 删除后的新路径。
    ///
    /// - Warning: 所要删除的路径串必须为原路径的子串，头子串或尾子串取决于删除方向
    /// 若非子串，会引发程序断言，导致崩溃
    @inlinable
    public func remove(components: [String], from direction: Direction = .tail) -> StoragePath {
        remove(StoragePath(components: components), from: direction)
    }
    
    /// 删除指定子路径从指定方向。
    ///
    /// - Parameters:
    ///   - subPath: 要删除的子路径。
    ///   - direction: 删除方向。
    ///
    /// - Returns: 删除后的新路径。
    ///
    /// - Warning: 所要删除的路径串必须为原路径的子串，头子串或尾子串取决于删除方向
    /// 若非子串，会引发程序断言，导致崩溃
    @inlinable
    public func remove(_ subPath: StoragePath, from direction: Direction = .tail) -> StoragePath {
        if direction == .tail {
            precondition(subPath.isSuffixPath(of: self), "裁剪失败，subPath 并非路径尾子串。removing \(subPath) of \(self)")
        } else {
            precondition(subPath.isPrefixPath(of: self), "裁剪失败，subPath 并非路径头子串。removing \(subPath) of \(self)")
        }
        return self.remove(of: subPath.count, from: direction)
    }
    
    /// 删除指定数量的路径组件从指定方向。
    ///
    /// - Parameters:
    ///   - count: 要删除的组件数量。
    ///   - direction: 删除方向。
    ///
    /// - Returns: 删除后的新路径。
    ///
    /// - Warning: 所要删除的项目数量必须小与或等于原路径的项目数，否则会引发程序断言，导致崩溃
    @inlinable
    public func remove(of count: Int, from direction: Direction = .tail) -> StoragePath {
        precondition(self.count >= count, "要裁剪的路径项数目超限，预期为 \(self.count), 却得到 \(count)")
        var components = self.components
        for _ in 0..<count {
            if direction == .tail {
                components.removeLast()
            } else {
                components.removeFirst()
            }
        }
        return .init(components: components)
    }
}
