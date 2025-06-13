import PgSQL
import Foundation
import DataConvertable

final class FileCrypto: PGModel, @unchecked Sendable {
    static let name = "file_cryptos"
    
    struct Fields: PGFields {
        let id = PGField("file_id", .uuid)                          .primary.foreign(FileIndex.self, FileIndex.fields.id)
        let salt = PGField("hkdf_salt", .string)                    .required.unique
        let sharedData = PGField("hkdf_shared_data", .string)       .required
        let chunkSize = PGField("chunk_size", .int64)               .required
        let storage_key = PGField("storage_key", .string)           .required.unique
    }
    
    @Field(fields.id)                           var id: UUID?
    @Parent(fields.id)                          var fileIndex: FileIndex
    
    var salt: Base64String {
        get { .init(__salt) }
        set { __salt = newValue.string }
    }
    
    var sharedData: Base64String {
        get { .init(__sharedData) }
        set { __sharedData = newValue.string }
    }
    
    @Field(fields.salt)                         private var __salt: String
    @Field(fields.sharedData)                   private var __sharedData: String
    @Field(fields.chunkSize)                    var chunkSize: Int64
    @Field(fields.storage_key)                  var storageKey: String
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
