public extension String {
    var fileExtension: String? {
        guard let dotIndex = self.lastIndex(of: ".") else { return nil }
        let extIndex = self.index(after: dotIndex)
        guard extIndex < self.endIndex else { return nil }
        return String(self[extIndex...])
    }
}
