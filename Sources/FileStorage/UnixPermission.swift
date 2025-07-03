import NIOFileSystem
import ErrorHandle
import Foundation

public extension FileStorage {
    struct UnixPermission: Sendable {
        public let owner: User?
        public let group: Group?
        public let rwxPermissions: FilePermissions?
        
        public enum User: Sendable {
            case id(CUnsignedLong)
            case name(String)
        }
        
        public enum Group: Sendable {
            case id(CUnsignedLong)
            case name(String)
        }
        
        public init(owner: User? = nil, group: Group? = nil, rwx: FilePermissions? = nil) {
            self.owner = owner
            self.group = group
            self.rwxPermissions = rwx
        }
        
        public enum Errcase: String, ErrList {
            case uidNotValid = "用户 id 无效"
            case userNameNotValid = "用户名称无效"
            case gidNotValid = "组 id 无效"
            case groupNameNotValid = "组名称无效"
        }
        
        var attributes: Res<[FileAttributeKey: Any], Errcase> {
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

struct FileSystemTools {
    /// 拼接路径的工具函数。
    /// - 参数 basePath: 基础路径，默认为当前目录。
    /// - 参数 pathToAppend: 要追加的路径。
    /// - 返回: 标准化后的完整路径。
    static func resolvePath(basePath: String = FileManager.default.currentDirectoryPath, append pathToAppend: String) -> String {
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
