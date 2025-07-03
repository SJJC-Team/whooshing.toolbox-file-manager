import ErrorHandle

/// 表示文件路径的结构体，封装路径的组成部分和操作。
///
/// 该类型表示一个标准化的路径，支持路径的拼接、删除子路径等操作。
public struct StoragePath: Sendable {
    
    /// StoragePath 相关错误类型。
    public enum Errcase: String, ErrList {
        /// 要移除的路径项数目超出范围。
        case removeCountExceed = "要移除的路径项数目超限"
        /// 从路径头部移除子路径失败。
        case removeFromHeadFailed = "从路径头移除失败"
        /// 从路径尾部移除子路径失败。
        case removeFromTailFailed = "从路径尾移除失败"
    }
    
    /// 路径的组成部分数组。
    public let components: [String]
    
    /// 路径的字符串形式，使用 `/` 分隔。
    public let string: String
    
    /// 空路径，表示根路径。
    public static let root = StoragePath(components: [])
    
    /// 通过路径组件数组初始化。
    /// - Parameter components: 路径组件数组。
    public init(components: [String]) {
        self.components = components
        self.string = components.joined(separator: "/")
    }
    
    /// 通过同类型切片初始化。
    /// - Parameter slice: StoragePath 的切片。
    public init(_ slice: Slice<Self>) {
        var comps: [String] = []
        for c in slice {
            comps.append(c)
        }
        self.init(components: comps)
    }
}

extension StoragePath: CustomStringConvertible, ExpressibleByStringLiteral {
    /// 路径的描述字符串，即路径字符串。
    public var description: String { self.string }
    
    /// 通过字符串字面量初始化，自动拆分路径组件。
    /// - Parameter value: 字符串字面量。
    public init(stringLiteral value: StringLiteralType) {
        self.components = value.components(separatedBy: "/").filter { !$0.isEmpty }
        self.string = components.joined(separator: "/")
    }
}

extension StoragePath: Collection {
    /// 集合起始索引。
    public var startIndex: Int { components.startIndex }
    
    /// 集合结束索引。
    public var endIndex: Int { components.endIndex }
    
    /// 路径最后一个组件。
    public var last: String? { components.last }
    
    /// 是否为空路径（根路径）。
    public var isRoot: Bool { isEmpty }
    
    /// 获取父路径。
    ///
    /// - Returns: 父路径。
    /// - Note: 根路径无父路径，调用将导致运行时错误。
    public var parent: StoragePath {
        guard !self.isRoot else { preconditionFailure("无法获取根目录的父目录") }
        var comps = self.components
        comps.removeLast()
        return .init(components: comps)
    }
    
    /// 获取下一个索引。
    /// - Parameter i: 当前索引。
    /// - Returns: 下一个索引。
    public func index(after i: Int) -> Int {
        components.index(after: i)
    }
    
    /// 根据索引获取路径组件。
    /// - Parameter position: 组件索引。
    /// - Returns: 路径组件字符串。
    public subscript(position: Int) -> String {
        get {
            components[position]
        }
    }
}

extension StoragePath: Equatable {
    /// 判断两个路径是否相等（组件逐一比较）。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.components == rhs.components
    }
    
    /// 路径拼接：追加字符串组件。
    public static func + (lhs: StoragePath, rhs: String) -> StoragePath { lhs.add(rhs) }
    /// 路径拼接：字符串 + 路径。
    public static func + (lhs: String, rhs: StoragePath) -> StoragePath { rhs + lhs }
    /// 路径拼接：追加字符串数组组件。
    public static func + (lhs: StoragePath, rhs: [String]) -> StoragePath { lhs.add(components: rhs) }
    /// 路径拼接：字符串数组 + 路径。
    public static func + (lhs: [String], rhs: StoragePath) -> StoragePath { rhs + lhs }
    /// 路径拼接：追加另一路径组件。
    public static func + (lhs: StoragePath, rhs: StoragePath) -> StoragePath { lhs.add(rhs) }
    
    /// 路径拼接赋值操作：追加字符串。
    public static func += (lhs: inout StoragePath, rhs: String) { lhs = lhs + rhs }
    /// 路径拼接赋值操作：追加字符串数组。
    public static func += (lhs: inout StoragePath, rhs: [String]) { lhs = lhs + rhs }
    /// 路径拼接赋值操作：追加路径。
    public static func += (lhs: inout StoragePath, rhs: StoragePath) { lhs = lhs + rhs }
    
    /// 追加字符串组件并返回新路径。
    /// - Parameter component: 字符串组件，支持包含多个用 `/` 分隔的部分。
    /// - Returns: 新路径。
    public func add(_ component: String) -> StoragePath {
        let newComponents = component.components(separatedBy: "/").filter { !$0.isEmpty }
        return add(components: newComponents)
    }
    
    /// 追加多个字符串组件并返回新路径。
    /// - Parameter components: 字符串数组。
    /// - Returns: 新路径。
    public func add(components: [String]) -> StoragePath {
        .init(components: self.components + components)
    }
    
    /// 追加另一路径的组件并返回新路径。
    /// - Parameter path: 另一路径。
    /// - Returns: 新路径。
    public func add(_ path: StoragePath) -> StoragePath {
        .init(components: self.components + path.components)
    }
    
    /// 删除指定子路径（字符串）从指定方向（尾部或头部）。
    ///
    /// - Parameters:
    ///   - subPath: 要删除的子路径字符串。
    ///   - direction: 删除方向，默认为尾部。
    /// - Throws: 路径删除错误。
    /// - Returns: 删除后的新路径。
    public func remove(_ subPath: String, from direction: RemoveDirection = .tail) throws(BscError<Errcase>) -> StoragePath {
        try remove(StoragePath(stringLiteral: subPath), from: direction)
    }
    
    /// 删除指定字符串组件数组从指定方向。
    ///
    /// - Parameters:
    ///   - components: 要删除的字符串数组。
    ///   - direction: 删除方向。
    /// - Throws: 路径删除错误。
    /// - Returns: 删除后的新路径。
    public func remove(components: [String], from direction: RemoveDirection = .tail) throws(BscError<Errcase>) -> StoragePath {
        try remove(StoragePath(components: components), from: direction)
    }
    
    /// 删除指定子路径从指定方向。
    ///
    /// - Parameters:
    ///   - subPath: 要删除的子路径。
    ///   - direction: 删除方向。
    /// - Throws: 删除失败错误。
    /// - Returns: 删除后的新路径。
    public func remove(_ subPath: StoragePath, from direction: RemoveDirection = .tail) throws(BscError<Errcase>) -> StoragePath {
        if direction == .tail {
            guard subPath.isSuffixPath(of: self) else { throw Errcase.removeFromTailFailed.d("subPath 判断失败, \(subPath)") }
        } else {
            guard subPath.isPrefixPath(of: self) else { throw Errcase.removeFromHeadFailed.d("subPath 判断失败, \(subPath)") }
        }
        return try self.remove(of: subPath.count, from: direction)
    }
    
    /// 删除指定数量的路径组件从指定方向。
    ///
    /// - Parameters:
    ///   - count: 要删除的组件数量。
    ///   - direction: 删除方向。
    /// - Throws: 删除失败错误。
    /// - Returns: 删除后的新路径。
    public func remove(of count: Int, from direction: RemoveDirection = .tail) throws(BscError<Errcase>) -> StoragePath {
        guard self.count >= count else { throw Errcase.removeCountExceed.d("预期为 \(self.count), 却得到 \(count)") }
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
    
    /// 判断当前路径是否是指定路径的前缀路径。
    ///
    /// - Parameter path: 待比较路径。
    /// - Returns: 如果是前缀路径，返回 true。
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
    public func isSuffixPath(of path: StoragePath) -> Bool {
        guard path.count >= self.count else { return false }
        for (i, name) in components.reversed().enumerated() {
            guard path.components[path.count - 1 - i] == name else { return false }
        }
        return true
    }
    
    /// 删除路径组件方向枚举。
    public enum RemoveDirection {
        /// 从头部删除。
        case head
        /// 从尾部删除。
        case tail
    }
}
