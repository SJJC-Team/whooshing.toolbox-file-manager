public extension String {
    /// 获取字符串中的文件扩展名（不包含点），如果没有扩展名则返回 nil。
    ///
    /// 例如：
    /// `"example.txt".fileExtension` 返回 `"txt"`
    /// `"archive.tar.gz".fileExtension` 返回 `"gz"`
    /// `"filename".fileExtension` 返回 `nil`
    var fileExtension: String? {
        guard let dotIndex = self.lastIndex(of: ".") else { return nil }
        let extIndex = self.index(after: dotIndex)
        guard extIndex < self.endIndex else { return nil }
        return String(self[extIndex...])
    }
}
