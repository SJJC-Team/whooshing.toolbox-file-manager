import Testing
@testable import FileStorage

@Suite("ChunkHelper 重分割算法测试集")
struct ChunkHelperReseparationTests {
    
    static let replacementParaSet: [
        (
            BufferSpace,
            Int64,
            BufferSpace,
            Int64,
            Result<ChunkHelpers.ReseparationResult, ChunkHelpers.RangeErrcase>
        )
    ] = [
        (
            [4, 6, 7],
            2,
            [7, 4, 6, 11],
            2,
            .success(.init(headCombine: .combine, tailCombine: .combine(.init(1, 3, 17, 8))))
        ),
        (
            [4, 6, 7],
            2,
            [7, 4, 6, 10],
            2,
            .success(.init(headCombine: .combine, tailCombine: .none))
        ),
        (
            [4, 6, 7],
            2,
            [7, 4, 6, 5],
            2,
            .success(.init(headCombine: .combine, tailCombine: .none))
        ),
        (
            [10, 8, 7, 9],
            0,
            [42],
            2,
            .success(.init(headCombine: .none, tailCombine: .combine(.init(6, 0, 0, 34))))
        ),
        (
            [35],
            0,
            [14, 9, 11, 12],
            2,
            .success(.init(headCombine: .none, tailCombine: .combine(.init(3, 3, 34, 7))))
        ),
        (
            [5, 6, 7, 10],
            2,
            [7, 4, 6, 8],
            0,
            .success(.init(headCombine: .combine, tailCombine: .none))
        ),
        (
            [5, 6, 7, 10, 20],
            2,
            [7, 4, 6, 8],
            0,
            .success(.init(headCombine: .combine, tailCombine: .none))
        ),
        (
            [5, 6, 2],
            2,
            [7, 4, 6, 8],
            0,
            .failure(.rangeSizeTooSmall)
        ),
        (
            [5, 6, 2],
            8,
            [7, 4, 6, 8],
            0,
            .failure(.rangeBeginIndexNotFound)
        ),
        (
            [5, 6, 2],
            -1,
            [7, 4, 6, 8],
            0,
            .failure(.rangeSizeInvalid)
        ),
        (
            [50000, 60000, 70000],
            ChunkHelpers.minChunkSize,
            [70000, 40000, 60000, 80000 + ChunkHelpers.minChunkSize],
            0,
            .success(.init(
                headCombine: .combine,
                tailCombine: .separate(.init(
                    70000,
                    3,
                    170000,
                    [50000, 60000, 70000].reduce(ChunkHelpers.minChunkSize, +) - [70000, 40000, 60000].reduce(0, +)
                ))
            ))
        ),
        (
            [50000, 60000, 70000],
            ChunkHelpers.minChunkSize + 1,
            [70000, 40000, 60000, 80000 + ChunkHelpers.minChunkSize + 1],
            0,
            .success(.init(
                headCombine: .separate,
                tailCombine: .separate(.init(
                    70000,
                    3,
                    170000,
                    [50000, 60000, 70000].reduce(ChunkHelpers.minChunkSize + 1, +) - [70000, 40000, 60000].reduce(0, +)
                ))
            ))
        ),
        (
            [50000, 60000, 70000],
            0,
            [70000, 40000, 60000, 10000 + ChunkHelpers.minChunkSize],
            0,
            .success(.init(
                headCombine: .none,
                tailCombine: .combine(.init(
                    ChunkHelpers.minChunkSize,
                    3,
                    170000,
                    [50000, 60000, 70000].reduce(0, +) - [70000, 40000, 60000].reduce(0, +)
                ))
            ))
        ),
        (
            [50000, 60000, 70000],
            ChunkHelpers.minChunkSize,
            [70000, 40000, 60000, 10000 + ChunkHelpers.minChunkSize * 2],
            0,
            .success(.init(
                headCombine: .combine,
                tailCombine: .combine(.init(
                    ChunkHelpers.minChunkSize,
                    3,
                    170000,
                    [50000, 60000, 70000].reduce(ChunkHelpers.minChunkSize, +) - [70000, 40000, 60000].reduce(0, +)
                ))
            ))
        ),
        (
            [50000, 60000, 70000],
            ChunkHelpers.minChunkSize,
            [70000, 40000, 60000, 10000 + ChunkHelpers.minChunkSize * 2 + 1],
            0,
            .success(.init(
                headCombine: .combine,
                tailCombine: .separate(.init(
                    ChunkHelpers.minChunkSize + 1,
                    3,
                    170000,
                    [50000, 60000, 70000].reduce(ChunkHelpers.minChunkSize, +) - [70000, 40000, 60000].reduce(0, +)
                ))
            ))
        ),
        (
            [50000, 60000, 70000],
            0,
            [70000, 40000, 60000, 10000 + ChunkHelpers.minChunkSize + 1],
            0,
            .success(.init(
                headCombine: .none,
                tailCombine: .separate(.init(
                    ChunkHelpers.minChunkSize + 1,
                    3,
                    170000,
                    [50000, 60000, 70000].reduce(0, +) - [70000, 40000, 60000].reduce(0, +)
                ))
            ))
        ),
        (
            [],
            ChunkHelpers.minChunkSize + 1,
            [ChunkHelpers.minChunkSize * 2, ChunkHelpers.minChunkSize * 2],
            0,
            .failure(.rangeSizeTooSmall)
        ),
        (
            [],
            0,
            [],
            0,
            .success(.init(headCombine: .none, tailCombine: .none))
        ),
        (
            [],
            0,
            [],
            2,
            .success(.init(headCombine: .none, tailCombine: .none))
        )
    ]
    
    @Test("覆写重分割函数测试", arguments: replacementParaSet)
    func replacementReseparationTest(
        chunks: BufferSpace,
        begin: Int64,
        originChunks: BufferSpace,
        offset: Int64,
        expect: Result<ChunkHelpers.ReseparationResult, ChunkHelpers.RangeErrcase>
    ) async throws {
        switch expect {
        case .success(let expect):
            let res = try ChunkHelpers.replacementReseparation(chunks, at: begin, in: originChunks, offset: offset)
            #expect(res == expect)
        case .failure(let errorExpect):
            do {
                let res = try ChunkHelpers.replacementReseparation(chunks, at: begin, in: originChunks, offset: offset)
                #expect(res != res)
            } catch {
                print(error)
                #expect(error.error == errorExpect)
            }
        }
    }
    
    static let insertionParaSet: [(BufferSpace, Int64, Int64, Int64, Result<ChunkHelpers.ReseparationResult, ChunkHelpers.RangeErrcase>)] = [
        (
            [5, 7, 9, 10],
            2,
            5,
            0,
            .success(.init(headCombine: .combine, tailCombine: .combine(.init(3, 0, 0, 2))))
        ),
        (
            [5, 7, 9, 10],
            2,
            5,
            2,
            .success(.init(headCombine: .combine, tailCombine: .combine(.init(1, 0, 0, 2))))
        ),
        (
            [5, 7, 9, 10],
            5,
            5,
            0,
            .success(.init(headCombine: .combine, tailCombine: .none))
        ),
        (
            [5, 7, 9, 10],
            0,
            5,
            0,
            .success(.init(headCombine: .none, tailCombine: .combine(.init(5, 0, 0, 0))))
        ),
        (
            [5, 7, 9, 10],
            -10,
            5,
            0,
            .failure(.rangeSizeInvalid)
        ),
        (
            [],
            -10,
            5,
            0,
            .failure(.rangeSizeInvalid)
        ),
        (
            [5, 7, 9, 10],
            2,
            0,
            0,
            .failure(.rangeBeginIndexNotFound)
        ),
        (
            [50000, 60000, 70000],
            0,
            ChunkHelpers.minChunkSize + 1,
            0,
            .success(.init(
                headCombine: .none,
                tailCombine: .separate(.init(ChunkHelpers.minChunkSize + 1, 0, 0, 0))
            ))
        ),
        (
            [50000, 60000, 70000],
            0,
            ChunkHelpers.minChunkSize,
            0,
            .success(.init(
                headCombine: .none,
                tailCombine: .combine(.init(ChunkHelpers.minChunkSize, 0, 0, 0))
            ))
        ),
        (
            [50000, 60000, 70000],
            ChunkHelpers.minChunkSize + 1,
            ChunkHelpers.minChunkSize * 2,
            0,
            .success(.init(
                headCombine: .separate,
                tailCombine: .combine(.init(ChunkHelpers.minChunkSize - 1, 0, 0, ChunkHelpers.minChunkSize + 1))
            ))
        ),
        (
            [],
            2,
            0,
            0,
            .failure(.rangeBeginIndexNotFound)
        ),
        (
            [],
            -2,
            0,
            0,
            .failure(.rangeSizeInvalid)
        ),
        (
            [],
            0,
            0,
            0,
            .success(.init(headCombine: .none, tailCombine: .none))
        ),
        (
            [],
            0,
            0,
            2,
            .success(.init(headCombine: .none, tailCombine: .none))
        )
    ]
    
    @Test("插入重分割函数测试", arguments: insertionParaSet)
    func insertionReseparationTest(
        chunks: BufferSpace,
        begin: Int64,
        chunk: Int64,
        offset: Int64,
        expect: Result<ChunkHelpers.ReseparationResult, ChunkHelpers.RangeErrcase>
    ) async throws {
        switch expect {
        case .success(let expect):
            let res = try ChunkHelpers.insertionReseparation(chunks, at: begin, in: chunk, offset: offset)
            #expect(res == expect)
        case .failure(let errorExpect):
            do {
                let res = try ChunkHelpers.insertionReseparation(chunks, at: begin, in: chunk, offset: offset)
                #expect(res != res)
            } catch {
                print(error)
                #expect(error.error == errorExpect)
            }
        }
    }
}

extension ChunkHelpers.ReseparationResult.TailCombine.TailParas {
    init(
        _ length: Int64,
        _ chunkIndex: Int,
        _ chunkBegin: Int64,
        _ byteOffset: Int64
    ) {
        self = Self.init(length: length, chunkIndex: chunkIndex, chunkBegin: chunkBegin, byteOffset: byteOffset)
    }
}
