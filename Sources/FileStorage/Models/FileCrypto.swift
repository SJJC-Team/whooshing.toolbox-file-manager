import PgSQL
import Foundation
import LoggingAdvanced

@usableFromInline
final class FileCrypto: PGModel, @unchecked Sendable {
    @usableFromInline
    static let name = "file_cryptos"
    
    @usableFromInline
    struct Fields: PGFields {
        let id = PGField("file_id", .uuid)                          .primary.foreign(FileIndex.self, \.id, onDelete: .cascade)
        let salt = PGField("hkdf_salt", .string)                    .required.unique
        let sharedData = PGField("hkdf_shared_data", .string)       .required
        let encryptedSize = PGField("encrypted_size", .int64)       .required
        let lastTag = PGField("last_tag", .int)                     .required
        let chunkSize = PGField("chunk_size", .int64)               .required
        let storageKey = PGField("storage_key", .string)            .required.unique
        let deleteAt = PGField("delete_at", .datetime)
        
        @inlinable
        init() {}
    }
    
    @usableFromInline
    static let fields = Fields()
    
    @usableFromInline @ID(custom: fields.id.key)                  var id: UUID?
    
    @inlinable
    var salt: Base64String {
        get { .init(__salt) }
        set { __salt = newValue.string }
    }
    
    @usableFromInline @Field(fields.salt)                         private(set) var __salt: String
    @usableFromInline @Field(fields.sharedData)                   var sharedData: String
    @usableFromInline @Field(fields.encryptedSize)                var encryptedSize: Int64
    @usableFromInline @Field(fields.lastTag)                      var lastTag: Int
    @usableFromInline @Field(fields.chunkSize)                    var chunkSize: Int64
    @usableFromInline @Field(fields.storageKey)                   var storageKey: String
    
    @usableFromInline @Timestamp(fields.deleteAt, on: .delete)    var deleteAt: Date!
    
    @inlinable
    init() {}
}

extension FileCrypto {
    @usableFromInline
    struct MIG: PGMigration, Sendable {
        @usableFromInline
        typealias DataModel = FileCrypto
        
        @usableFromInline
        var tdeEncrypt: Bool
        
        @inlinable
        init(tdeEncrypt: Bool = true) {
            self.tdeEncrypt = tdeEncrypt
        }
    }
}

extension FileCrypto: Loggerable, CustomStringConvertible {
    @inlinable
    var json: [String: AnyCodable] {[
        "id": AnyCodable(id),
        "encrypted_size": AnyCodable(encryptedSize),
        "last_tag": AnyCodable(lastTag),
        "chunk_size": AnyCodable(chunkSize),
        "storage_key": AnyCodable(storageKey),
        "delete_at": AnyCodable(deleteAt)
    ]}
    
    @usableFromInline
    var summaryJson: [String: AnyCodable] {[
        "id": AnyCodable(id),
        "encrypted_size": AnyCodable(encryptedSize),
        "last_tag": AnyCodable(lastTag),
        "chunk_size": AnyCodable(chunkSize)
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
