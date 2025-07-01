import Testing
import ErrorHandle
import Foundation
import Cryptos
@testable import FileStorage

@Suite("ChunkHelper 文件数据块分割算法测试集")
struct FilePartSeparateTests {
    
    typealias FilePartParas = (
        tagStart: Int,
        byteStart: Int64,
        byteEnd: Int64,
        byteHeadIgnore: Int64,
        byteTailIgnore: Int64,
        encryptedStart: Int64,
        encryptedEnd: Int64
    )
    
    static let indexId = UUID()
    
    static let separateParas: [(Int64, Int, FilePartParas, ChunkHelpers.IntersectionResult, Result<(FilePartParas?, FilePartParas?), BscError<FileWriterError>>)] = [
        (
            chunkSize: 65535,
            lastTag: 0,
            (
                tagStart: 0,
                byteStart: 0,
                byteEnd: 100,
                byteHeadIgnore: 0,
                byteTailIgnore: 0,
                encryptedStart: 0,
                encryptedEnd: 100 + Crypto.Symm.Stream.cipherExtraLength
            ),
            .init(
                rangeOffset: 0,
                rangeInIntersection: true,
                chunkIndex: 0,
                chunkBegin: 0,
                chunks: [100 + Crypto.Symm.Stream.cipherExtraLength]
            ),
            .success((nil, nil))
        ),
        (
            chunkSize: 10,
            lastTag: 0,
            (
                tagStart: 0,
                byteStart: 0,
                byteEnd: 10000,
                byteHeadIgnore: 0,
                byteTailIgnore: 0,
                encryptedStart: 0,
                encryptedEnd: 10000 + (10000 / 10 * Crypto.Symm.Stream.cipherExtraLength)
            ),
            .init(
                rangeOffset: 2,
                rangeInIntersection: false,
                chunkIndex: 20,
                chunkBegin: (20 + Crypto.Symm.Stream.cipherExtraLength) * 10,
                chunks: [10 + Crypto.Symm.Stream.cipherExtraLength]
            ),
            .success((
                (
                    tagStart: 0,
                    byteStart: 0,
                    byteEnd: 20 * 10 + 2,
                    byteHeadIgnore: 0,
                    byteTailIgnore: 8,
                    encryptedStart: 0,
                    encryptedEnd: 21 * 10 + (21 * Crypto.Symm.Stream.cipherExtraLength)
                ),(
                    tagStart: 20,
                    byteStart: 20 * 10 + 2,
                    byteEnd: 10000,
                    byteHeadIgnore: 2,
                    byteTailIgnore: 0,
                    encryptedStart: 20 * 10 + (20 * Crypto.Symm.Stream.cipherExtraLength),
                    encryptedEnd: 10000 + (10000 / 10 * Crypto.Symm.Stream.cipherExtraLength)
                )
            ))
        ),
        (
            chunkSize: 10,
            lastTag: 100000,
            (
                tagStart: 100,
                byteStart: 1006,
                byteEnd: 9996,
                byteHeadIgnore: 6,
                byteTailIgnore: 4,
                encryptedStart: 1000 + (1000 / 10 * Crypto.Symm.Stream.cipherExtraLength),
                encryptedEnd: 10000 + (10000 / 10 * Crypto.Symm.Stream.cipherExtraLength)
            ),
            .init(
                rangeOffset: 6,
                rangeInIntersection: false,
                chunkIndex: 30,
                chunkBegin: (30 + Crypto.Symm.Stream.cipherExtraLength) * 10,
                chunks: [10 + Crypto.Symm.Stream.cipherExtraLength]
            ),
            .success((
                (
                    tagStart: 100,
                    byteStart: 1006,
                    byteEnd: 1006 + 30 * 10,
                    byteHeadIgnore: 6,
                    byteTailIgnore: 4,
                    encryptedStart: 1000 + (1000 / 10 * Crypto.Symm.Stream.cipherExtraLength),
                    encryptedEnd: 1310 + (1310 / 10 * Crypto.Symm.Stream.cipherExtraLength)
                ),(
                    tagStart: 130,
                    byteStart: 1006 + 30 * 10,
                    byteEnd: 9996,
                    byteHeadIgnore: 6,
                    byteTailIgnore: 4,
                    encryptedStart: 1300 + (1300 / 10 * Crypto.Symm.Stream.cipherExtraLength),
                    encryptedEnd: 10000 + (10000 / 10 * Crypto.Symm.Stream.cipherExtraLength)
                )
            ))
        )
    ]
    
    @Test("FilePart 分割测试", arguments: separateParas)
    func separationTest(
        chunkSize: Int64,
        lastTag: Int,
        partParas: FilePartParas,
        indexRes: ChunkHelpers.IntersectionResult,
        expect: Result<(FilePartParas?, FilePartParas?), BscError<FileWriterError>>
    ) async throws {
        
        let index = FileIndex()
        index.id = Self.indexId
        
        let crypto = FileCrypto()
        crypto.id = Self.indexId
        crypto.chunkSize = chunkSize
        crypto.lastTag = lastTag
        
        let part = FilePart(
            fileIndexId: Self.indexId,
            tagStart: partParas.tagStart,
            byteStart: partParas.byteStart,
            byteEnd: partParas.byteEnd,
            byteHeadIgnore: partParas.byteHeadIgnore,
            byteTailIgnore: partParas.byteTailIgnore,
            encryptedStart: partParas.encryptedStart,
            encryptedEnd: partParas.encryptedEnd
        )
        
        let partCheck = FilePart(
            fileIndexId: Self.indexId,
            tagStart: partParas.tagStart,
            byteStart: partParas.byteStart,
            byteEnd: partParas.byteEnd,
            byteHeadIgnore: partParas.byteHeadIgnore,
            byteTailIgnore: partParas.byteTailIgnore,
            encryptedStart: partParas.encryptedStart,
            encryptedEnd: partParas.encryptedEnd
        )
        
        switch expect {
        case .success(let expect):
            let res = try ChunkHelpers.filePartSeparate(in: part, fileCrypto: crypto, indexResult: indexRes)
            #expect(res?.byteStart == expect.0?.byteStart)
            #expect(res?.byteEnd == expect.0?.byteEnd)
            #expect(res?.encryptedStart == expect.0?.encryptedStart)
            #expect(res?.encryptedEnd == expect.0?.encryptedEnd)
            #expect(res?.tagStart == expect.0?.tagStart)
            #expect(res?.byteHeadIgnore == expect.0?.byteHeadIgnore)
            #expect(res?.byteTailIgnore == expect.0?.byteTailIgnore)
            
            if let origin = expect.1 {
                #expect(part.byteStart == origin.byteStart)
                #expect(part.byteEnd == origin.byteEnd)
                #expect(part.encryptedStart == origin.encryptedStart)
                #expect(part.encryptedEnd == origin.encryptedEnd)
                #expect(part.tagStart == origin.tagStart)
                #expect(part.byteHeadIgnore == origin.byteHeadIgnore)
                #expect(part.byteTailIgnore == origin.byteTailIgnore)
            } else {
                #expect(part.byteStart == partCheck.byteStart)
                #expect(part.byteEnd == partCheck.byteEnd)
                #expect(part.encryptedStart == partCheck.encryptedStart)
                #expect(part.encryptedEnd == partCheck.encryptedEnd)
                #expect(part.tagStart == partCheck.tagStart)
                #expect(part.byteHeadIgnore == partCheck.byteHeadIgnore)
                #expect(part.byteTailIgnore == partCheck.byteTailIgnore)
            }
        case .failure(let error):
            do {
                let res = try ChunkHelpers.filePartSeparate(in: part, fileCrypto: crypto, indexResult: indexRes)
                #expect(res?.byteStart != res?.byteStart)
            } catch let err {
                #expect(error == err)
            }
        }
    }
    
}
