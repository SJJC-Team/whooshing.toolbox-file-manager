import PgSQL
import Foundation
import DataConvertable

final class FilePart: PGModel, @unchecked Sendable {
    static let name = "file_parts"
    
    struct Fields: PGFields {
        let id = PGField("id", .uuid)                               .primary
        let fileId = PGField("file_id", .uuid)                      .required.foreign(FileIndex.self, \.id, onDelete: .cascade)
        let tagStart = PGField("tag_start", .int)                   .required
        let byteStart = PGField("byte_start", .int64)               .required
        let byteEnd = PGField("byte_end", .int64)                   .required
        let byteHeadIgnore = PGField("byte_head_ignore", .int64)    .required
        let byteTailIgnore = PGField("byte_tail_ignore", .int64)    .required
        let encryptedStart = PGField("encrypted_start", .int64)     .required
        let encryptedEnd = PGField("encrypted_end", .int64)         .required
        let deleteAt = PGField("delete_at", .string)
    }
    
    static let fields = Fields()
    
    @ID(key: .id)                               var id: UUID?
    
    @Parent(fields.fileId)                      var fileIndex: FileIndex
    @Field(fields.tagStart)                     var tagStart: Int
    
    @Field(fields.byteStart)                    var byteStart: Int64
    @Field(fields.byteEnd)                      var byteEnd: Int64
    
    @Field(fields.byteHeadIgnore)               var byteHeadIgnore: Int64
    @Field(fields.byteTailIgnore)               var byteTailIgnore: Int64
    
    @Field(fields.encryptedStart)               var encryptedStart: Int64
    @Field(fields.encryptedEnd)                 var encryptedEnd: Int64
    
    @Timestamp(fields.deleteAt, on: .delete)    var deleteAt: Date!
    
    init() {}
    
    init(
        fileIndexId: UUID,
        tagStart: Int,
        byteStart: Int64,
        byteEnd: Int64,
        byteHeadIgnore: Int64 = 0,
        byteTailIgnore: Int64 = 0,
        encryptedStart: Int64,
        encryptedEnd: Int64
    ) {
        self.$fileIndex.id = fileIndexId
        self.tagStart = tagStart
        self.byteStart = byteStart
        self.byteEnd = byteEnd
        self.byteHeadIgnore = byteHeadIgnore
        self.byteTailIgnore = byteTailIgnore
        self.encryptedStart = encryptedStart
        self.encryptedEnd = encryptedEnd
    }
}

extension FilePart {
    struct MIG: PGMigration, Sendable {
        typealias DataModel = FilePart
        
        var tdeEncrypt: Bool
        
        init(tdeEncrypt: Bool = true) {
            self.tdeEncrypt = tdeEncrypt
        }
    }
}
