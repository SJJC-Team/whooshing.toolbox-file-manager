import PgSQL
import Foundation
import DataConvertable

final class FileCrypto: PGModel, @unchecked Sendable {
    static let name = "file_cryptos"
    
    struct Fields: PGFields {
        let id = PGField("file_id", .uuid)                          .primary.foreign(FileIndex.self, \.id, onDelete: .cascade)
        let salt = PGField("hkdf_salt", .string)                    .required.unique
        let sharedData = PGField("hkdf_shared_data", .string)       .required
        let encryptedSize = PGField("encrypted_size", .int64)       .required
        let lastTag = PGField("last_tag", .int)                     .required
        let chunkSize = PGField("chunk_size", .int64)               .required
        let storageKey = PGField("storage_key", .string)            .required.unique
        let deleteAt = PGField("delete_at", .string)
    }
    
    @ID(custom: fields.id.key)                  var id: UUID?
    
    var salt: Base64String {
        get { .init(__salt) }
        set { __salt = newValue.string }
    }
    
    @Field(fields.salt)                         private var __salt: String
    @Field(fields.sharedData)                   var sharedData: String
    @Field(fields.encryptedSize)                var encryptedSize: Int64
    @Field(fields.lastTag)                      var lastTag: Int
    @Field(fields.chunkSize)                    var chunkSize: Int64
    @Field(fields.storageKey)                   var storageKey: String
    
    @Timestamp(fields.deleteAt, on: .delete)    var deleteAt: Date!
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
