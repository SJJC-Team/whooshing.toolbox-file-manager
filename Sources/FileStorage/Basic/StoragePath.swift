import ErrorHandle

struct StoragePath: Sendable {
    
    enum Err: String, ErrList {
        var domain: String { "woo.sys.storage.path.err" }
        case removeCountExceed = "要移除的路径项数目超限"
        case removeFromHeadFailed = "从路径头移除失败"
        case removeFromTailFailed = "从路径尾移除失败"
    }
    
    let components: [String]
    let string: String
    
    init(components: [String]) {
        self.components = components
        self.string = components.joined(separator: "/")
    }
}

extension StoragePath: CustomStringConvertible, ExpressibleByStringLiteral {
    var description: String { self.string }
    
    init(stringLiteral value: StringLiteralType) {
        self.components = value.components(separatedBy: "/").filter { !$0.isEmpty }
        self.string = components.joined(separator: "/")
    }
}

extension StoragePath: Collection {
    var startIndex: Int {
        components.startIndex
    }
    
    var endIndex: Int {
        components.endIndex
    }
    
    var last: String? {
        components.last
    }
    
    var parent: StoragePath? {
        guard self.count > 0 else { return nil }
        var comps = self.components
        comps.removeLast()
        return .init(components: comps)
    }
    
    func index(after i: Int) -> Int {
        components.index(after: i)
    }
    
    subscript(position: Int) -> String {
        get {
            components[position]
        }
    }
}

extension StoragePath: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.components == rhs.components
    }
    
    static func + (lhs: StoragePath, rhs: String) -> StoragePath { lhs.add(rhs) }
    static func + (lhs: StoragePath, rhs: [String]) -> StoragePath { lhs.add(components: rhs) }
    static func + (lhs: StoragePath, rhs: StoragePath) -> StoragePath { lhs.add(rhs) }
    
    func add(_ component: String) -> StoragePath {
        let newComponents = component.components(separatedBy: "/").filter { !$0.isEmpty }
        return add(components: newComponents)
    }
    
    func add(components: [String]) -> StoragePath {
        .init(components: self.components + components)
    }
    
    func add(_ path: StoragePath) -> StoragePath {
        .init(components: self.components + path.components)
    }
    
    enum RemoveDirection {
        case head, tail
    }
    
    func remove(_ subPath: String, from direction: RemoveDirection = .tail) throws -> StoragePath {
        try remove(StoragePath(stringLiteral: subPath), from: direction)
    }
    
    func remove(components: [String], from direction: RemoveDirection = .tail) throws -> StoragePath {
        try remove(StoragePath(components: components), from: direction)
    }
    
    func remove(_ subPath: StoragePath, from direction: RemoveDirection = .tail) throws -> StoragePath {
        if direction == .tail {
            guard subPath.isSuffixPath(of: self) else { throw Err.removeFromTailFailed.d(16011) }
        } else {
            guard subPath.isPrefixPath(of: self) else { throw Err.removeFromHeadFailed.d(16012) }
        }
        return try self.remove(of: subPath.count, from: direction)
    }
    
    func remove(of count: Int, from direction: RemoveDirection = .tail) throws -> StoragePath {
        guard self.count >= count else { throw Err.removeCountExceed.d("预期为 \(self.count), 却得到 \(count)", 16010) }
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
    
    func isPrefixPath(of path: StoragePath) -> Bool {
        guard path.count >= self.count else { return false }
        for (i, name) in components.enumerated() {
            guard path.components[i] == name else { return false }
        }
        return true
    }
    
    func isSuffixPath(of path: StoragePath) -> Bool {
        guard path.count >= self.count else { return false }
        for (i, name) in components.reversed().enumerated() {
            guard path.components[path.count - 1 - i] == name else { return false }
        }
        return true
    }
}
