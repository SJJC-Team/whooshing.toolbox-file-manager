import PgSQL
import Foundation
import LoggingAdvanced

@usableFromInline
final class FilePart: PGModel, @unchecked Sendable {
    @usableFromInline
    static let name = "file_parts"
    
    @usableFromInline
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
        let deleteAt = PGField("delete_at", .datetime)
        
        @inlinable
        init() {}
    }
    
    @usableFromInline
    static let fields = Fields()
    
    @usableFromInline @ID(key: .id)                               var id: UUID?
    
    @usableFromInline @Parent(fields.fileId)                      var fileIndex: FileIndex
    @usableFromInline @Field(fields.tagStart)                     var tagStart: Int
    
    @usableFromInline @Field(fields.byteStart)                    var byteStart: Int64
    @usableFromInline @Field(fields.byteEnd)                      var byteEnd: Int64
    
    @usableFromInline @Field(fields.byteHeadIgnore)               var byteHeadIgnore: Int64
    @usableFromInline @Field(fields.byteTailIgnore)               var byteTailIgnore: Int64
    
    @usableFromInline @Field(fields.encryptedStart)               var encryptedStart: Int64
    @usableFromInline @Field(fields.encryptedEnd)                 var encryptedEnd: Int64
    
    @usableFromInline @Timestamp(fields.deleteAt, on: .delete)    var deleteAt: Date!
    
    @inlinable
    init() {}
    
    @usableFromInline
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
    @usableFromInline
    struct MIG: PGMigration, Sendable {
        @usableFromInline
        typealias DataModel = FilePart
        
        @usableFromInline
        var tdeEncrypt: Bool
        
        @inlinable
        init(tdeEncrypt: Bool = true) {
            self.tdeEncrypt = tdeEncrypt
        }
    }
}

extension FilePart: Loggerable, CustomStringConvertible {
    @inlinable
    var json: [String: AnyCodable] {[
        "id": AnyCodable(id),
        "tag_start": AnyCodable(tagStart),
        "byte_start": AnyCodable(byteStart),
        "byte_end": AnyCodable(byteEnd),
        "byte_head_ignore": AnyCodable(byteHeadIgnore),
        "byte_tail_ignore": AnyCodable(byteTailIgnore),
        "encrypted_start": AnyCodable(encryptedStart),
        "encrypted_end": AnyCodable(encryptedEnd),
        "delete_at": AnyCodable(deleteAt)
    ]}
    
    @usableFromInline
    var summaryJson: [String: AnyCodable] {[
        "id": AnyCodable(id),
        "file_id": AnyCodable(fileIndex.id),
        "tag_start": AnyCodable(tagStart),
        "byte_start": AnyCodable(byteStart),
        "byte_end": AnyCodable(byteEnd),
        "byte_head_ignore": AnyCodable(byteHeadIgnore),
        "byte_tail_ignore": AnyCodable(byteTailIgnore),
        "encrypted_start": AnyCodable(encryptedStart),
        "encrypted_end": AnyCodable(encryptedEnd)
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
