import Testing
import ErrorHandle
import NIOCore
@testable import FileStorage

@Suite("BufferSpaces 测试集")
struct BufferSpacesTests {
    
    @Test("array 模式：元素访问与索引测试")
    func testArrayModeAccess() {
        let buffers: [Int64] = [100, 200, 300]
        let space = BufferSpace(.array(buffers))
        
        #expect(space.startIndex == 0)
        #expect(space.endIndex == buffers.count)
        #expect(space.last == buffers.last)
        for i in 0..<space.endIndex {
            #expect(space[i] == buffers[i])
        }
        #expect(space.index(after: 1) == 2)
    }
    
    @Test("buffers 模式：元素访问与索引测试")
    func testBufferModeAccess() {
        let buffers: [ByteBuffer] = [.init(repeating: 1, count: 100), .init(repeating: 1, count: 200), .init(repeating: 1, count: 300)]
        let space = BufferSpace(.buffers(buffers))
        
        #expect(space.startIndex == 0)
        #expect(space.endIndex == buffers.count)
        #expect(space.last == Int64(buffers.last!.readableBytes))
        for i in 0..<space.endIndex {
            #expect(space[i] == buffers[i].readableBytes)
        }
        #expect(space.index(after: 1) == 2)
    }

    @Test("chunk 模式：整除 total 测试")
    func testChunkModeExactDivision() {
        let space = BufferSpace(.chunk(1024, total: 4096))
        #expect(space.startIndex == 0)
        #expect(space.endIndex == 4)
        #expect(space.count == 4)
        #expect(space.last == 1024)
        for i in 0..<space.endIndex {
            #expect(space[i] == 1024)
        }
    }

    @Test("chunk 模式：不能整除 total 测试")
    func testChunkModeUnevenDivision() {
        let space = BufferSpace(.chunk(1024, total: 2500))
        #expect(space.startIndex == 0)
        #expect(space.endIndex == 3)
        #expect(space.count == 3)
        #expect(space.last == 452)
        #expect(space[0] == 1024)
        #expect(space[1] == 1024)
        #expect(space[2] == 452)
    }

    @Test("chunk 模式：total = 0")
    func testChunkModeTotalZero() {
        let space = BufferSpace(.chunk(1024, total: 0))
        #expect(space.startIndex == 0)
        #expect(space.endIndex == 0)
        #expect(space.last == nil)
    }

    @Test("通过 arrayLiteral 初始化")
    func testArrayLiteralInit() {
        let space: BufferSpace = [10, 20, 30]
        #expect(space.count == 3)
        #expect(space[0] == 10)
        #expect(space[2] == 30)
        #expect(space.last == 30)
    }

    @Test("chunk 模式：chunkSize 不整除 total 时末尾值测试")
    func testChunkRemainderSubscript() {
        let space = BufferSpace(.chunk(1024, total: 2501))
        #expect(space[0] == 1024)
        #expect(space[1] == 1024)
        #expect(space[2] == 453) // 2501 % 1024
    }

    @Test("chunk 模式：subscript 边界测试")
    func testChunkSubscriptEdge() {
        let space = BufferSpace(.chunk(1000, total: 3000)
        )
        #expect(space[2] == 1000)
        #expect(space.count == 3)
        #expect(space.endIndex == 3)
    }

    @Test("chunk 模式：index(after:) 测试")
    func testIndexAfterInChunkMode() {
        let space = BufferSpace(.chunk(1024, total: 2048))
        #expect(space.index(after: 0) == 1)
        #expect(space.index(after: 1) == 2)
    }

    @Test("chunk 模式：zero total 时 subscript 应崩溃")
    func testChunkZeroTotalAccess() {
        let space = BufferSpace(.chunk(1024, total: 0))
        #expect(space.endIndex == 0)
        #expect(space.last == nil)
        #expect(space.count == 0)
        #expect(space.endIndex == 0)
    }
}
