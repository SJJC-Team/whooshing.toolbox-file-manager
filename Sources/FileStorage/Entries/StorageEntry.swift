import Foundation
import FluentKit
import NIOAdvanced
import ErrorHandle

/// 文件存储系统中的通用存储条目协议。
///
/// 表示文件系统中的一个存储条目，可以是文件或目录。
public protocol StorageEntry: Sendable {
    /// 条目名称。
    var name: String { get }
    
    /// 所属文件存储实例。
    var storage: FileStorage { get }
    
    /// 创建时间。
    var createdAt: Date { get }
    
    /// 最后更新时间。
    var updatedAt: Date { get }
    
    /// 获取条目的大小。
    ///
    /// - Returns: 异步事件循环结果，成功时返回字节大小，失败时返回错误。
    func getSize() -> EventLoopRes<Int64, FileStorage.Errcase>
    
    /// 删除条目。
    ///
    /// - Parameter force: 是否强制删除（包括数据库记录及物理文件）。
    /// - Returns: 异步事件循环结果，成功或失败。
    func delete(force: Bool) -> EventLoopRes<Void, FileStorage.Errcase>
    
    /// 重命名条目。
    ///
    /// - Parameter name: 新名称。
    /// - Returns: 异步事件循环结果，成功时返回更新后的条目。
    func rename(as name: String) -> EventLoopRes<Self, FileStorage.Errcase>
    
    /// 移动条目到指定路径（目录路径）并可重命名。
    ///
    /// - Parameters:
    ///   - path: 目标目录路径。
    ///   - name: 可选的新名称。
    /// - Returns: 异步事件循环结果，成功时返回更新后的条目。
    func move(to path: StoragePath, as name: String?) -> EventLoopRes<Self, FileStorage.Errcase>
    
    /// 移动条目到指定目录并可重命名。
    ///
    /// - Parameters:
    ///   - dir: 目标目录对象。
    ///   - name: 可选的新名称。
    /// - Returns: 异步事件循环结果，成功时返回更新后的条目。
    func move(to dir: Directory, as name: String?) -> EventLoopRes<Self, FileStorage.Errcase>
}

public extension StorageEntry {
    /// 将条目移动到指定目录路径，先获取目录对象后调用 `move(to: Directory, as:)`。
    ///
    /// - Parameters:
    ///   - path: 目标目录路径。
    ///   - name: 可选的新名称。
    /// - Returns: 异步事件循环结果。
    func move(to path: StoragePath, as name: String? = nil) -> EventLoopRes<Self, FileStorage.Errcase> {
        storage.getDirectory(at: path).flatMap { dir in
            move(to: dir, as: name)
        }
    }
}
