import ErrorHandle

public extension FileStorage {
    /// FileStorage 所有可能抛出的错误类型枚举，按功能划分为数据库错误、目录操作错误、文件操作错误。
    @frozen
    enum Errcase: String, ErrList {
        case databaseInitFailed = "数据库连接失败"
        case fileSystemInitFailed = "文件系统初始化失败"
        case unknow = "未知错误"
        
        // 目录相关错误
        case createDirectoryFailed = "目录创建失败"
        case getDirectoryFailed = "目录获取失败"
        case fetchDirectorySubItemFailed = "获取子项目失败"
        case deleteDirectoryFailed = "删除目录失败"
        case renameDirectoryFailed = "重命名目录失败"
        case moveDirectoryFailed = "移动目录失败"
        case emptyDirectoryFailed = "清空目录失败"
        case fetchDirectorySizeFailed = "计算目录大小失败"
        
        // 文件相关错误
        case createFileFailed = "文件创建失败"
        case getFileFailed = "文件获取失败"
        case deleteFileFailed = "删除文件失败"
        case renameFileFailed = "重命名文件失败"
        case moveFileFailed = "移动文件失败"
        case readFileFailed = "文件读取失败"
        case writeFileFailed = "文件写入失败"
        case removeFileDataFailed = "文件数据抹除失败"
        case openFileFailed = "文件打开失败"
        case closeFileFailed = "文件关闭失败"
    }
}
