public extension File {
    
    enum Typed: String, Codable, Sendable {
        case file = "file"
        case directory = "directory"
    }
    
    enum MimeType: String, Codable, Sendable {
        // 文本类型
        case plain = "text/plain"
        case html = "text/html"
        case css = "text/css"
        case csv = "text/csv"
        case xml = "application/xml"
        case json = "application/json"

        // 图像类型
        case png = "image/png"
        case jpeg = "image/jpeg"
        case gif = "image/gif"
        case svg = "image/svg+xml"
        case webp = "image/webp"
        
        // 音频/视频
        case mp3 = "audio/mpeg"
        case wav = "audio/wav"
        case mp4 = "video/mp4"
        case webm = "video/webm"

        // 应用类型
        case pdf = "application/pdf"
        case zip = "application/zip"
        case gzip = "application/gzip"
        case formURLEncoded = "application/x-www-form-urlencoded"
        case octetStream = "application/octet-stream"
        
        case unknow = "unknow"

        // 自定义初始化（如果需要从扩展的 MIME 字符串中恢复）
        public init(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "txt": self = .plain
            case "html", "htm": self = .html
            case "css": self = .css
            case "csv": self = .csv
            case "xml": self = .xml
            case "json": self = .json
            case "png": self = .png
            case "jpg", "jpeg": self = .jpeg
            case "gif": self = .gif
            case "svg": self = .svg
            case "webp": self = .webp
            case "mp3": self = .mp3
            case "wav": self = .wav
            case "mp4": self = .mp4
            case "webm": self = .webm
            case "pdf": self = .pdf
            case "zip": self = .zip
            case "gz", "gzip": self = .gzip
            case "bin": self = .octetStream
            default: self = .unknow
            }
        }
    }
}
