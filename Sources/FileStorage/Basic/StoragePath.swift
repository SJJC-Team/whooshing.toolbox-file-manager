import ErrorHandle

public struct StoragePath: Sendable {
    
    public enum Errcase: String, ErrList {
        case removeCountExceed = "要移除的路径项数目超限"
        case removeFromHeadFailed = "从路径头移除失败"
        case removeFromTailFailed = "从路径尾移除失败"
    }
    
    public let components: [String]
    public let string: String
    
    public static let root = StoragePath(components: [])
    
    public init(components: [String]) {
        self.components = components
        self.string = components.joined(separator: "/")
    }
    
    public init(_ slice: Slice<Self>) {
        var comps: [String] = []
        for c in slice {
            comps.append(c)
        }
        self.init(components: comps)
    }
}

extension StoragePath: CustomStringConvertible, ExpressibleByStringLiteral {
    public var description: String { self.string }
    
    public init(stringLiteral value: StringLiteralType) {
        self.components = value.components(separatedBy: "/").filter { !$0.isEmpty }
        self.string = components.joined(separator: "/")
    }
}

extension StoragePath: Collection {
    public var startIndex: Int { components.startIndex }
    
    public var endIndex: Int { components.endIndex }
    
    public var last: String? { components.last }
    
    public var isRoot: Bool { isEmpty }
    
    public var parent: StoragePath {
        guard !self.isRoot else { preconditionFailure("无法获取根目录的父目录") }
        var comps = self.components
        comps.removeLast()
        return .init(components: comps)
    }
    
    public func index(after i: Int) -> Int {
        components.index(after: i)
    }
    
    public subscript(position: Int) -> String {
        get {
            components[position]
        }
    }
}

extension StoragePath: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.components == rhs.components
    }
    
    public static func + (lhs: StoragePath, rhs: String) -> StoragePath { lhs.add(rhs) }
    public static func + (lhs: String, rhs: StoragePath) -> StoragePath { rhs + lhs }
    public static func + (lhs: StoragePath, rhs: [String]) -> StoragePath { lhs.add(components: rhs) }
    public static func + (lhs: [String], rhs: StoragePath) -> StoragePath { rhs + lhs }
    public static func + (lhs: StoragePath, rhs: StoragePath) -> StoragePath { lhs.add(rhs) }
    
    public static func += (lhs: inout StoragePath, rhs: String) { lhs = lhs + rhs }
    public static func += (lhs: inout StoragePath, rhs: [String]) { lhs = lhs + rhs }
    public static func += (lhs: inout StoragePath, rhs: StoragePath) { lhs = lhs + rhs }
    
    public func add(_ component: String) -> StoragePath {
        let newComponents = component.components(separatedBy: "/").filter { !$0.isEmpty }
        return add(components: newComponents)
    }
    
    public func add(components: [String]) -> StoragePath {
        .init(components: self.components + components)
    }
    
    public func add(_ path: StoragePath) -> StoragePath {
        .init(components: self.components + path.components)
    }
    
    public enum RemoveDirection {
        case head, tail
    }
    
    public func remove(_ subPath: String, from direction: RemoveDirection = .tail) throws(BscError<Errcase>) -> StoragePath {
        try remove(StoragePath(stringLiteral: subPath), from: direction)
    }
    
    public func remove(components: [String], from direction: RemoveDirection = .tail) throws(BscError<Errcase>) -> StoragePath {
        try remove(StoragePath(components: components), from: direction)
    }
    
    public func remove(_ subPath: StoragePath, from direction: RemoveDirection = .tail) throws(BscError<Errcase>) -> StoragePath {
        if direction == .tail {
            guard subPath.isSuffixPath(of: self) else { throw Errcase.removeFromTailFailed.d("subPath 判断失败, \(subPath)") }
        } else {
            guard subPath.isPrefixPath(of: self) else { throw Errcase.removeFromHeadFailed.d("subPath 判断失败, \(subPath)") }
        }
        return try self.remove(of: subPath.count, from: direction)
    }
    
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
    
    public func isPrefixPath(of path: StoragePath) -> Bool {
        guard path.count >= self.count else { return false }
        for (i, name) in components.enumerated() {
            guard path.components[i] == name else { return false }
        }
        return true
    }
    
    public func isSuffixPath(of path: StoragePath) -> Bool {
        guard path.count >= self.count else { return false }
        for (i, name) in components.reversed().enumerated() {
            guard path.components[path.count - 1 - i] == name else { return false }
        }
        return true
    }
}
