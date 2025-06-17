import Testing
import ErrorHandle
@testable import FileStorage

@Suite("ChunkHelper 重分割算法测试集")
struct ChunkHelperReseparationTests {
    
    static let replacementParaSet: [([Int64], Int64, [Int64], Result<ChunkHelpers.ReseparationResult, ChunkHelpers.RangeErrcase>)] = [
        (
            [5, 6, 7],
            2,
            [7, 4, 6, 8],
            .success(.init(headCombine: .combine, tailCombine: .combine(tailLength: 5, chunkIndex: 3, byteIndex: 3)))
        ),
        (
            [5, 6, 7, 10],
            2,
            [7, 4, 6, 8],
            .success(.init(headCombine: .combine, tailCombine: .none))
        ),
        (
            [5, 6, 7, 10, 20],
            2,
            [7, 4, 6, 8],
            .success(.init(headCombine: .combine, tailCombine: .none))
        ),
        (
            [5, 6, 2],
            2,
            [7, 4, 6, 8],
            .failure(.rangeSizeTooSmall)
        ),
        (
            [5, 6, 2],
            8,
            [7, 4, 6, 8],
            .failure(.rangeBeginIndexNotFound)
        ),
        (
            [5, 6, 2],
            -1,
            [7, 4, 6, 8],
            .failure(.rangeSizeInvalid)
        ),
        (
            [50000, 60000, 70000],
            ChunkHelpers.minChunkSize,
            [70000, 40000, 60000, 80000 + ChunkHelpers.minChunkSize],
            .success(.init(
                headCombine: .combine,
                tailCombine: .separate(
                    tailLength: 70000,
                    chunkIndex: 3,
                    byteIndex: [50000, 60000, 70000].reduce(ChunkHelpers.minChunkSize, +) - [70000, 40000, 60000].reduce(0, +)
                )
            ))
        ),
        (
            [50000, 60000, 70000],
            ChunkHelpers.minChunkSize + 1,
            [70000, 40000, 60000, 80000 + ChunkHelpers.minChunkSize + 1],
            .success(.init(
                headCombine: .separate,
                tailCombine: .separate(
                    tailLength: 70000,
                    chunkIndex: 3,
                    byteIndex: [50000, 60000, 70000].reduce(ChunkHelpers.minChunkSize + 1, +) - [70000, 40000, 60000].reduce(0, +)
                )
            ))
        ),
        (
            [50000, 60000, 70000],
            0,
            [70000, 40000, 60000, 10000 + ChunkHelpers.minChunkSize],
            .success(.init(
                headCombine: .none,
                tailCombine: .combine(
                    tailLength: ChunkHelpers.minChunkSize,
                    chunkIndex: 3,
                    byteIndex: [50000, 60000, 70000].reduce(0, +) - [70000, 40000, 60000].reduce(0, +)
                )
            ))
        ),
        (
            [50000, 60000, 70000],
            ChunkHelpers.minChunkSize,
            [70000, 40000, 60000, 10000 + ChunkHelpers.minChunkSize * 2],
            .success(.init(
                headCombine: .combine,
                tailCombine: .combine(
                    tailLength: ChunkHelpers.minChunkSize,
                    chunkIndex: 3,
                    byteIndex: [50000, 60000, 70000].reduce(ChunkHelpers.minChunkSize, +) - [70000, 40000, 60000].reduce(0, +)
                )
            ))
        ),
        (
            [50000, 60000, 70000],
            ChunkHelpers.minChunkSize,
            [70000, 40000, 60000, 10000 + ChunkHelpers.minChunkSize * 2 + 1],
            .success(.init(
                headCombine: .combine,
                tailCombine: .separate(
                    tailLength: ChunkHelpers.minChunkSize + 1,
                    chunkIndex: 3,
                    byteIndex: [50000, 60000, 70000].reduce(ChunkHelpers.minChunkSize, +) - [70000, 40000, 60000].reduce(0, +)
                )
            ))
        ),
        (
            [50000, 60000, 70000],
            0,
            [70000, 40000, 60000, 10000 + ChunkHelpers.minChunkSize + 1],
            .success(.init(
                headCombine: .none,
                tailCombine: .separate(
                    tailLength: ChunkHelpers.minChunkSize + 1,
                    chunkIndex: 3,
                    byteIndex: [50000, 60000, 70000].reduce(0, +) - [70000, 40000, 60000].reduce(0, +)
                )
            ))
        ),
        (
            [],
            ChunkHelpers.minChunkSize + 1,
            [ChunkHelpers.minChunkSize * 2, ChunkHelpers.minChunkSize * 2],
            .failure(.rangeSizeTooSmall)
        ),
        (
            [],
            0,
            [],
            .success(.init(headCombine: .none, tailCombine: .none))
        )
    ]
    
    @Test("覆写重分割函数测试", arguments: replacementParaSet)
    func replacementReseparationTest(
        chunks: [Int64],
        begin: Int64,
        originChunks: [Int64],
        expect: Result<ChunkHelpers.ReseparationResult, ChunkHelpers.RangeErrcase>
    ) async throws {
        switch expect {
        case .success(let expect):
            let res = try ChunkHelpers.replacementReseparation(chunks, at: begin, in: originChunks)
            #expect(res == expect)
        case .failure(let errorExpect):
            do {
                let res = try ChunkHelpers.replacementReseparation(chunks, at: begin, in: originChunks)
                #expect(res != res)
            } catch {
                print(error)
                #expect(error.error == errorExpect)
            }
        }
    }
    
    static let insertionParaSet: [([Int64], Int64, Int64, Result<ChunkHelpers.ReseparationResult, ChunkHelpers.RangeErrcase>)] = [
        (
            [5, 7, 9, 10],
            2,
            5,
            .success(.init(headCombine: .combine, tailCombine: .combine(tailLength: 3, chunkIndex: 0, byteIndex: 2)))
        ),
        (
            [5, 7, 9, 10],
            5,
            5,
            .success(.init(headCombine: .combine, tailCombine: .none))
        ),
        (
            [5, 7, 9, 10],
            0,
            5,
            .success(.init(headCombine: .none, tailCombine: .combine(tailLength: 5, chunkIndex: 0, byteIndex: 0)))
        ),
        (
            [5, 7, 9, 10],
            -10,
            5,
            .failure(.rangeSizeInvalid)
        ),
        (
            [],
            -10,
            5,
            .failure(.rangeSizeInvalid)
        ),
        (
            [5, 7, 9, 10],
            2,
            0,
            .failure(.rangeBeginIndexNotFound)
        ),
        (
            [50000, 60000, 70000],
            0,
            ChunkHelpers.minChunkSize + 1,
            .success(.init(
                headCombine: .none,
                tailCombine: .separate(tailLength: ChunkHelpers.minChunkSize + 1, chunkIndex: 0, byteIndex: 0)
            ))
        ),
        (
            [50000, 60000, 70000],
            0,
            ChunkHelpers.minChunkSize,
            .success(.init(
                headCombine: .none,
                tailCombine: .combine(tailLength: ChunkHelpers.minChunkSize, chunkIndex: 0, byteIndex: 0)
            ))
        ),
        (
            [50000, 60000, 70000],
            ChunkHelpers.minChunkSize + 1,
            ChunkHelpers.minChunkSize * 2,
            .success(.init(
                headCombine: .separate,
                tailCombine: .combine(tailLength: ChunkHelpers.minChunkSize - 1, chunkIndex: 0, byteIndex: ChunkHelpers.minChunkSize + 1)
            ))
        ),
        (
            [],
            2,
            0,
            .failure(.rangeBeginIndexNotFound)
        ),
        (
            [],
            -2,
            0,
            .failure(.rangeSizeInvalid)
        ),
        (
            [],
            0,
            0,
            .success(.init(headCombine: .none, tailCombine: .none))
        ),
    ]
    
    @Test("插入重分割函数测试", arguments: insertionParaSet)
    func insertionReseparationTest(
        chunks: [Int64],
        begin: Int64,
        chunk: Int64,
        expect: Result<ChunkHelpers.ReseparationResult, ChunkHelpers.RangeErrcase>
    ) async throws {
        switch expect {
        case .success(let expect):
            let res = try ChunkHelpers.insertionReseparation(chunks, at: begin, in: chunk)
            #expect(res == expect)
        case .failure(let errorExpect):
            do {
                let res = try ChunkHelpers.insertionReseparation(chunks, at: begin, in: chunk)
                #expect(res != res)
            } catch {
                print(error)
                #expect(error.error == errorExpect)
            }
        }
    }
}
