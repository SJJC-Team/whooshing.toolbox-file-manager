import Testing
import ErrorHandle
@testable import FileStorage

@Suite("ChunkHelper 落点计算算法测试集")
struct ChunkHelpeIntersectionrTests {
    
    static let rangeSet: [
        (
            Range<Int64>,
            BufferSpace,
            Int64,
            Result<ChunkHelpers.IntersectionResult, ChunkHelpers.RangeErrcase>
        )
    ] = [
        (
            0..<5,
            [5, 5, 5],
            2,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, rangeInIntersection: false, chunkIndex: 0, chunkBegin: 0, chunks: [7]))
        ),
        (
            0..<5,
            .init(.chunk(5, total: 15)),
            2,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, rangeInIntersection: false, chunkIndex: 0, chunkBegin: 0, chunks: [7]))
        ),
        (
            20..<20,
            [5, 5, 5, 5],
            10,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, rangeInIntersection: true, chunkIndex: 4, chunkBegin: 60, chunks: []))
        ),
        (
            0..<21,
            [5, 5, 6, 5],
            10,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, rangeInIntersection: false, chunkIndex: 0, chunkBegin: 0, chunks: [15, 15, 16, 15]))
        ),
        (
            21..<21,
            [5, 5, 6, 5],
            10,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, rangeInIntersection: true, chunkIndex: 4, chunkBegin: 61, chunks: []))
        ),
        (
            0..<20,
            [5, 5, 5, 5],
            10,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, rangeInIntersection: false, chunkIndex: 0, chunkBegin: 0, chunks: [15, 15, 15, 15]))
        ),
        (
            5..<5,
            [5, 5, 5],
            2,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, rangeInIntersection: true, chunkIndex: 1, chunkBegin: 7, chunks: [7]))
        ),
        (
            5..<5,
            .init(.chunk(5, total: 15)),
            2,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, rangeInIntersection: true, chunkIndex: 1, chunkBegin: 7, chunks: [7]))
        ),
        (
            10..<13,
            [5, 3, 5, 8, 6],
            2,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 2, rangeInIntersection: false, chunkIndex: 2, chunkBegin: 12, chunks: [7]))
        ),
        (
            10..<14,
            [5, 3, 5, 8, 6],
            2,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 2, rangeInIntersection: false, chunkIndex: 2, chunkBegin: 12, chunks: [7, 10]))
        ),
        (
            100..<100,
            [5, 3, 5, 8, 6],
            2,
            .failure(.rangeBeginIndexNotFound)
        ),
        (
            11..<11,
            [5, 3, 5, 8, 6],
            2,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 3, rangeInIntersection: false, chunkIndex: 2, chunkBegin: 12, chunks: [7]))
        ),
        (
            13..<13,
            [5, 3, 5, 8, 6],
            2,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, rangeInIntersection: true, chunkIndex: 3, chunkBegin: 19, chunks: [10]))
        ),
        (
            -5..<100,
            [5, 5, 5],
            2,
            .failure(.rangeBeginIndexNotFound)
        ),
        (
            -5..<(-5),
            [5, 5, 5],
            2,
            .failure(.rangeBeginIndexNotFound)
        ),
        (
            8192..<81920,
            [65535, 8192, 2134],
            16,
            .failure(.rangeSizeExceed)
        ),
        (
            8192..<81920,
            [65535, 8192, 21340],
            16,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 8192, rangeInIntersection: false, chunkIndex: 0, chunkBegin: 0, chunks: [65535 + 16, 8192 + 16, 21340 + 16]))
        ),
        (
            327675..<327675,
            .init(.chunk(12343, total: 327675)),
            28,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, rangeInIntersection: true, chunkIndex: 27, chunkBegin: 327675 + 27 * 28, chunks: .init(.chunk(12343 + 28, total: 327675))))
        ),
        (
            5..<10,
            [],
            16,
            .failure(.rangeBeginIndexNotFound)
        ),
        (
            0..<0,
            .init(.chunk(3000, total: 1)),
            28,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, rangeInIntersection: true, chunkIndex: 0, chunkBegin: 0, chunks: [29]))
        ),
        (
            0..<0,
            [],
            0,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, rangeInIntersection: true, chunkIndex: 0, chunkBegin: 0, chunks: []))
        )
    ]
    
    static let closedRangeSet: [(ClosedRange<Int64>, BufferSpace, Int64, Result<ChunkHelpers.IntersectionResult, ChunkHelpers.RangeErrcase>)] = rangeSet.compactMap {
        if $0.0.upperBound == $0.0.lowerBound {
            return nil
        }
        return (ClosedRange($0.0), $0.1, $0.2, $0.3)
    }
    
    static let indexSet: [(Int64, BufferSpace, Int64, Result<ChunkHelpers.IntersectionResult, ChunkHelpers.IndexErrcase>)] = rangeSet.compactMap {
        if $0.0.upperBound == $0.0.lowerBound {
            let result: Result<ChunkHelpers.IntersectionResult, ChunkHelpers.IndexErrcase>
            switch $0.3 {
            case .success(let res):
                result = .success(res)
            case .failure(let error):
                result = .failure(.intersectionFailed)
            }
            return ($0.0.lowerBound, $0.1, $0.2, result)
        } else {
            return nil
        }
    }
    
    @Test("块大小落点检测函数测试 Range", arguments: rangeSet)
    func rangeIntersectionRangeTest(
        range: Range<Int64>,
        buffers: BufferSpace,
        offset: Int64,
        expect: Result<ChunkHelpers.IntersectionResult, ChunkHelpers.RangeErrcase>
    ) async throws {
        switch expect {
        case .success(let expect):
            let res = try ChunkHelpers.rangeIntersection(range, in: buffers, offset: offset)
            #expect(res == expect)
        case .failure(let errorExpect):
            do {
                let res = try ChunkHelpers.rangeIntersection(range, in: buffers, offset: offset)
                #expect(res != res)
            } catch {
                #expect(error.error == errorExpect)
            }
        }
    }
    
    @Test("块大小落点检测函数测试 ClosedRange", arguments: closedRangeSet)
    func rangeIntersectionClosedRangeTest(
        range: ClosedRange<Int64>,
        buffers: BufferSpace,
        offset: Int64,
        expect: Result<ChunkHelpers.IntersectionResult, ChunkHelpers.RangeErrcase>
    ) async throws {
        switch expect {
        case .success(let expect):
            let res = try ChunkHelpers.rangeIntersection(range, in: buffers, offset: offset)
            #expect(res == expect)
        case .failure(let errorExpect):
            do {
                let res = try ChunkHelpers.rangeIntersection(range, in: buffers, offset: offset)
                #expect(res != res)
            } catch {
                #expect(error.error == errorExpect)
            }
        }
    }
    
    @Test("块大小落点检测函数测试 Indexes", arguments: indexSet)
    func rangeIntersectionClosedRangeTest(
        index: Int64,
        buffers: BufferSpace,
        offset: Int64,
        expect: Result<ChunkHelpers.IntersectionResult, ChunkHelpers.IndexErrcase>
    ) async throws {
        switch expect {
        case .success(let expect):
            let res = try ChunkHelpers.index(index, in: buffers, offset: offset)
            #expect(res == expect)
        case .failure(let errorExpect):
            do {
                let res = try ChunkHelpers.index(index, in: buffers, offset: offset)
                #expect(res != res)
            } catch {
                #expect(error.error == errorExpect)
            }
        }
    }
}

extension ChunkHelpers.RangeErrcase: Error {}
extension ChunkHelpers.IndexErrcase: Error {}
