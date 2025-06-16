import PgSQL
import Foundation
import DataConvertable

final class FileCrypto: PGModel, @unchecked Sendable {
    static let name = "file_cryptos"
    
    struct Fields: PGFields {
        let id = PGField("file_id", .uuid)                          .primary.foreign(FileIndex.self, FileIndex.fields.id)
        let salt = PGField("hkdf_salt", .string)                    .required.unique
        let sharedData = PGField("hkdf_shared_data", .string)       .required
        let chunks = PGField("chunks", .array(of: .int64))          .required
        let chunkTags = PGField("chunk_tags", .array(of: .int))     .required
        let encryptedSize = PGField("encrypted_size", .int64)       .required
        let storageKey = PGField("storage_key", .string)            .required.unique
    }
    
    @Field(fields.id)                           var id: UUID?
    @Parent(fields.id)                          var fileIndex: FileIndex
    
    var salt: Base64String {
        get { .init(__salt) }
        set { __salt = newValue.string }
    }
    
    @Field(fields.salt)                         private var __salt: String
    @Field(fields.sharedData)                   var sharedData: String
    @Field(fields.chunks)                       var chunks: [Int64]
    @Field(fields.chunkTags)                    var chunkTags: [Int]
    @Field(fields.encryptedSize)                var encryptedSize: Int64
    @Field(fields.storageKey)                   var storageKey: String
}

extension FileCrypto {
    struct MIG: PGMigration, Sendable {
        typealias DataModel = FileCrypto
        
        var tdeEncrypt: Bool
        
        init(tdeEncrypt: Bool = true) {
            self.tdeEncrypt = tdeEncrypt
        }
    }
}
