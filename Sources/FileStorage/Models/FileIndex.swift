import PgSQL
import Foundation
import LoggingAdvanced

@usableFromInline
final class FileIndex: PGModel, @unchecked Sendable {
    
    @usableFromInline
    static let name = "file_indexes"
    
    @usableFromInline
    struct Fields: PGFields {
        let id = PGField("id", .uuid)                                           .primary
        let name = PGField("name", .string)                                     .required
        let mimeType = PGField("mime_type", .string)
        let parent = PGField("parent_id", .uuid)                                .foreign(FileIndex.self, .id, onDelete: .cascade)
        let type = PGField("type", .string)                                     .required
        let size = PGField("size", .int64)
        let createdAt = PGField("create_at", .datetime)                         .required
        let updatedAt = PGField("update_at", .datetime)                         .required
        let deleteAt = PGField("delete_at", .datetime)
        
        @inlinable
        init() {}
    }
    
    @usableFromInline
    static let fields = Fields()
    
    @usableFromInline @ID(key: .id)                                   var id: UUID?
    @usableFromInline @Field(fields.name)                             var name: String
    @usableFromInline @OptionalEnum(fields.mimeType)                  var mimeType: File.MimeType?
    @usableFromInline @OptionalParent(fields.parent)                  var parent: FileIndex?
    @usableFromInline @Enum(fields.type)                              var type: File.Typed
    @usableFromInline @Field(fields.size)                             var size: Int64?
    @usableFromInline @Timestamp(fields.createdAt, on: .create)       var createdAt: Date!
    @usableFromInline @Timestamp(fields.updatedAt, on: .update)       var updatedAt: Date!
    @usableFromInline @Timestamp(fields.deleteAt, on: .delete)        var deleteAt: Date!
    
    @usableFromInline
    let isRoot: Bool
    
    @inlinable
    func getId() throws -> UUID? {
        self.isRoot ? nil : try self.requireID()
    }
    
    @inlinable
    init(isRoot: Bool = false) { self.isRoot = isRoot }
    
    @inlinable
    convenience init() { self.init(isRoot: false) }
}

extension FileIndex {
    @usableFromInline
    struct MIG: PGMigration, Sendable {
        @usableFromInline
        typealias DataModel = FileIndex
        
        @usableFromInline
        var tdeEncrypt: Bool
        
        @inlinable
        init(tdeEncrypt: Bool = true) {
            self.tdeEncrypt = tdeEncrypt
        }
    }
}

extension FileIndex: Loggerable, CustomStringConvertible {
    @inlinable
    var json: [String: AnyCodable] {[
        "id": AnyCodable(id),
        "name": AnyCodable(name),
        "mime_type": AnyCodable(mimeType?.rawValue),
        "type": AnyCodable(type.rawValue),
        "size": AnyCodable(size),
        "created_at": AnyCodable(createdAt),
        "updated_at": AnyCodable(updatedAt),
        "delete_at": AnyCodable(deleteAt)
    ]}
    
    @usableFromInline
    var summaryJson: [String: AnyCodable] {[
        "id": AnyCodable(id?.shortString ?? "null"),
        "name": AnyCodable(name),
        "mime_type": AnyCodable(mimeType?.rawValue),
        "type": AnyCodable(type.rawValue),
        "size": AnyCodable(size)
    ]}
    
    @usableFromInline
    var description: String {
        formatJson(json)
    }
    
    @usableFromInline
    var summaryDescription: String {
        formatJson(summaryJson)
    }
}
