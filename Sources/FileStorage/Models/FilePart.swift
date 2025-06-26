import PgSQL
import Foundation
import DataConvertable

final class FilePart: PGModel, @unchecked Sendable {
    static let name = "file_parts"
    
    struct Fields: PGFields {
        let id = PGField("file_id", .uuid)                          .primary.foreign(FileIndex.self, FileIndex.fields.id, onDelete: .cascade)
        let tagStart = PGField("tag_start", .int)                   .required
        let byteStart = PGField("byte_start", .int64)               .required
        let byteEnd = PGField("byte_end", .int64)                   .required
        let encryptedStart = PGField("encrypted_start", .int64)     .required
        let encryptedEnd = PGField("encrypted_end", .int64)         .required
    }
    
    var byteRange: Range<Int64> {
        byteStart..<byteEnd
    }
    
    var encryptedRange: Range<Int64> {
        encryptedStart..<encryptedEnd
    }
    
    @Field(fields.id)                           var id: UUID?
    @Parent(fields.id)                          var fileIndex: FileIndex
    @Field(fields.tagStart)                     var tagStart: Int
    
    @Field(fields.byteStart)                    var byteStart: Int64
    @Field(fields.byteEnd)                      var byteEnd: Int64
    
    @Field(fields.encryptedStart)               var encryptedStart: Int64
    @Field(fields.encryptedEnd)                 var encryptedEnd: Int64
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
