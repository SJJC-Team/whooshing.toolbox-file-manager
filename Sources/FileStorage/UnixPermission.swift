import NIOFileSystem
import ErrorHandle
import Foundation

public extension FileStorage {
    
    /// 表示文件系统中可选的 Unix 权限配置，包括所有者、所属组和 POSIX 权限位。
    struct UnixPermission: Sendable {
        /// 所有者用户标识，可指定 UID 或用户名。
        public let owner: User?
        /// 所属用户组标识，可指定 GID 或组名。
        public let group: Group?
        /// POSIX rwx 权限位设置。
        public let rwxPermissions: FilePermissions?
        
        /// 文件所有者的标识方式。
        public enum User: Sendable {
            /// 使用用户 ID 指定。
            case id(CUnsignedLong)
            /// 使用用户名指定。
            case name(String)
        }
        
        /// 文件所属组的标识方式。
        public enum Group: Sendable {
            /// 使用组 ID 指定。
            case id(CUnsignedLong)
            /// 使用组名指定。
            case name(String)
        }
        
        /// 创建 UnixPermission 配置对象。
        /// - Parameters:
        ///   - owner: 可选所有者标识。
        ///   - group: 可选所属组标识。
        ///   - rwx: 可选权限位设置。
        public init(owner: User? = nil, group: Group? = nil, rwx: FilePermissions? = nil) {
            self.owner = owner
            self.group = group
            self.rwxPermissions = rwx
        }
        
        /// 表示在设置权限时可能遇到的错误。
        public enum Errcase: String, ErrList {
            /// 提供的用户 ID 无效。
            case uidNotValid = "用户 id 无效"
            /// 提供的用户名无效。
            case userNameNotValid = "用户名称无效"
            /// 提供的组 ID 无效。
            case gidNotValid = "组 id 无效"
            /// 提供的组名无效。
            case groupNameNotValid = "组名称无效"
        }
        
        /// 转换为 FileManager 可用的权限属性字典。
        /// 包含合法性验证逻辑，若失败将返回对应错误。
        public var attributes: Res<[FileAttributeKey: Any], Errcase> {
            var permissions: [FileAttributeKey: Any] = [:]
            
            switch owner {
            case .id(let id):
                guard FileSystemTools.isValidUID(uid_t(id)) else {
                    return .failure(.uidNotValid, String(id))
                }
                
                permissions[.ownerAccountID] = id
            case .name(let name):
                guard FileSystemTools.isValidUsername(name) else {
                    return .failure(.userNameNotValid, name)
                }
                
                permissions[.ownerAccountName] = name
            case nil: break
            }
            
            switch group {
            case .id(let id):
                guard FileSystemTools.isValidGID(gid_t(id)) else {
                    return .failure(.gidNotValid, String(id))
                }
                
                permissions[.groupOwnerAccountID] = id
            case .name(let name):
                guard FileSystemTools.isValidGroupname(name) else {
                    return .failure(.groupNameNotValid, name)
                }
                
                permissions[.groupOwnerAccountName] = name
            case nil: break
            }
            
            switch rwxPermissions {
            case .some(let permission): permissions[.posixPermissions] = Int16(permission.rawValue)
            case .none: break
            }
            
            return .success(permissions)
        }
    }
}

/// 工具集，用于路径处理与用户/组合法性验证。
public struct FileSystemTools {
    /// 拼接路径的工具函数。
    /// - 参数 basePath: 基础路径，默认为当前目录。
    /// - 参数 pathToAppend: 要追加的路径。
    /// - 返回: 标准化后的完整路径。
    public static func resolvePath(basePath: String = FileManager.default.currentDirectoryPath, append pathToAppend: String) -> String {
        let base = (basePath as NSString).expandingTildeInPath
        let baseURL = URL(fileURLWithPath: base).deletingLastPathComponent()
        let appended = (pathToAppend as NSString).expandingTildeInPath
        let finalURL: URL
        if appended.hasPrefix("/") {
            finalURL = URL(fileURLWithPath: appended)
        } else {
            finalURL = baseURL.appendingPathComponent(appended)
        }
        return finalURL.standardized.path
    }
    
    /// 检查指定组名是否存在
    static func isValidGroupname(_ groupname: String) -> Bool {
        return getgrnam(groupname) != nil
    }

    /// 检查指定组 ID 是否存在
    static func isValidGID(_ gid: gid_t) -> Bool {
        return getgrgid(gid) != nil
    }
    
    /// 判断用户名是否存在
    /// - Parameter username: 用户名字符串（如 "root"）
    /// - Returns: 如果存在该用户名，返回 true；否则 false
    static func isValidUsername(_ username: String) -> Bool {
        return getpwnam(username) != nil
    }
    
    /// 判断 UID 是否存在系统用户
    /// - Parameter uid: 用户 ID（如 0, 501）
    /// - Returns: 如果存在该 UID 的用户，返回 true；否则 false
    static func isValidUID(_ uid: uid_t) -> Bool {
        return getpwuid(uid) != nil
    }
}
