import PgSQL
import Fluent
import Foundation

final class FileIndex: PGModel, @unchecked Sendable {
    
    static let name = "file_indexes"
    
    struct Fields: PGFields {
        let id = PGField("id", .uuid)                                           .primary
        let name = PGField("name", .string)                                     .required
        let mimeType = PGField("mime_type", .string)
        let parent = PGField("parent_id", .uuid)                                .foreign(FileIndex.self, .id, onDelete: .cascade)
        let type = PGField("type", .string)                                     .required
        let size = PGField("size", .int64)
        let createdAt = PGField("create_at", .string)                           .required
        let updateAt = PGField("update_at", .string)                            .required
        let deleteAt = PGField("delete_at", .string)
    }
    
    @ID(key: .id)                                   var id: UUID?
    @Field(fields.name)                             var name: String
    @OptionalEnum(fields.mimeType)                  var mimeType: File.MimeType?
    @OptionalParent(fields.parent)                  var parent: FileIndex?
    @Enum(fields.type)                              var type: File.Typed
    @Field(fields.size)                             var size: Int64?
    @Timestamp(fields.createdAt, on: .create)       var createdAt: Date!
    @Timestamp(fields.updateAt, on: .update)        var updatedAt: Date!
    @Timestamp(fields.deleteAt, on: .delete)        var deleteAt: Date!
    
    let isRoot: Bool
    
    func getId() throws -> UUID? {
        self.isRoot ? nil : try self.requireID()
    }
    
    init(isRoot: Bool = false) { self.isRoot = isRoot }
    convenience init() { self.init(isRoot: false) }
}

extension FileIndex {
    struct MIG: PGMigration, Sendable {
        typealias DataModel = FileIndex
        
        var tdeEncrypt: Bool
        
        init(tdeEncrypt: Bool = true) {
            self.tdeEncrypt = tdeEncrypt
        }
    }
}
