import Testing
import ErrorHandle
import NIOCore
import AsyncAlgorithms
@testable import FileStorage

@Suite("AsyncChannel 测试集")
struct AsyncChannelTests {
    @Test("测试流分块")
    func channelChunkTest() async throws {
        let datas = [
            randomData(size: 100),
            randomData(size: 330),
            randomData(size: 630),
            randomData(size: 20),
        ]
        
        let totalSize = datas.reduce(0, { $0 + $1.readableBytes })
        
        var totalByte = datas.reduce(into: ByteBuffer(), { $0.writeImmutableBuffer($1) })
        
        #expect(totalByte.readableBytes == totalSize)
        
        let chunkSize: Int64 = 50
        
        let channel = AsyncThrowingChannel<ByteBuffer, Error>()
        
        Task {
            for data in datas {
                await channel.send(data)
            }
            channel.finish()
        }
        
        var size = 0
        for try await chunk in channel.chunkedChannel(chunkSize) {
            #expect(chunk.readableBytes == min(Int(chunkSize), totalSize - size))
            #expect(totalByte.readSlice(length: chunk.readableBytes) == chunk)
            size += chunk.readableBytes
        }
        
        #expect(size == totalSize)
        #expect(totalByte.readableBytes == 0)
    }
    
    @Test("ByteBuffer 深拷贝")
    func byteBufferDeepCopyTest() async throws {
        func bufferPointer(_ buf: ByteBuffer) -> UnsafeRawPointer? {
            buf.withUnsafeReadableBytes { ptr in
                return ptr.baseAddress
            }
        }

        let buf1 = ByteBufferAllocator().buffer(string: "Hello, world")
        let buf1Pointer = bufferPointer(buf1)

        let buf2 = buf1.cloned
        let buf2Pointer = bufferPointer(buf2)
        
        #expect(buf1Pointer != buf2Pointer)
        #expect(buf1 == buf2)

        // 还可以修改 buf2 验证是否影响 buf1
        var buf2mut = buf2
        buf2mut.writeString("!!!")
        
        #expect(buf1.getString(at: 0, length: buf1.readableBytes) == "Hello, world")
        #expect(buf2mut.getString(at: 0, length: buf2mut.readableBytes) == "Hello, world!!!")
    }
}
