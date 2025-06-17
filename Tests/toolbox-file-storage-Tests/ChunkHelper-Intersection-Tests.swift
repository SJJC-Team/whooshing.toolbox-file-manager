import Testing
import ErrorHandle
@testable import FileStorage

@Suite("ChunkHelper 落点计算算法测试集")
struct ChunkHelpeIntersectionrTests {
    
    static let rangeSet: [(Range<Int64>, [Int64], Int64, Result<ChunkHelpers.IntersectionResult, ChunkHelpers.RangeErrcase>)] = [
        (
            0..<5,
            [5, 5, 5],
            2,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, chunkIndex: 0, chunkBegin: 0, chunks: [7]))
        ),
        (
            5..<5,
            [5, 5, 5],
            2,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, chunkIndex: 1, chunkBegin: 7, chunks: []))
        ),
        (
            10..<13,
            [5, 3, 5, 8, 6],
            2,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 2, chunkIndex: 2, chunkBegin: 12, chunks: [7]))
        ),
        (
            10..<14,
            [5, 3, 5, 8, 6],
            2,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 2, chunkIndex: 2, chunkBegin: 12, chunks: [7, 10]))
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
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 3, chunkIndex: 2, chunkBegin: 12, chunks: []))
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
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 8192, chunkIndex: 0, chunkBegin: 0, chunks: [65535 + 16, 8192 + 16, 21340 + 16]))
        ),
        (
            5..<10,
            [],
            16,
            .failure(.rangeBeginIndexNotFound)
        ),
        (
            0..<0,
            [],
            0,
            .success(ChunkHelpers.IntersectionResult(rangeOffset: 0, chunkIndex: 0, chunkBegin: 0, chunks: []))
        )
    ]
    
    static let closedRangeSet: [(ClosedRange<Int64>, [Int64], Int64, Result<ChunkHelpers.IntersectionResult, ChunkHelpers.RangeErrcase>)] = rangeSet.compactMap {
        if $0.0.upperBound == $0.0.lowerBound {
            return nil
        }
        return (ClosedRange($0.0), $0.1, $0.2, $0.3)
    }
    
    static let indexSet: [(Int64, [Int64], Int64, Result<(Int64, Int64), ChunkHelpers.IndexErrcase>)] = rangeSet.compactMap {
        if $0.0.upperBound == $0.0.lowerBound {
            let result: Result<(Int64, Int64), ChunkHelpers.IndexErrcase>
            switch $0.3 {
            case .success(let res):
                result = .success((res.rangeOffset, res.chunkBegin))
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
        buffers: [Int64],
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
        buffers: [Int64],
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
        buffers: [Int64],
        offset: Int64,
        expect: Result<(Int64, Int64), ChunkHelpers.IndexErrcase>
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
