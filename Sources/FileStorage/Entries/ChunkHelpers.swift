import NIOCore
import NIOAdvanced
import Foundation
import ErrorHandle

/// 查看同级 Diagrams 文件夹中的图片以理解原理
/// - [1.文件覆盖写入算法.png](./Diagrams/1.文件覆盖写入算法.png)
/// - [2.文件插入数据算法.png](./Diagrams/2.文件插入数据算法.png)
enum ChunkHelpers {
    
    public enum IndexErrcase: String, ErrList {
        case intersectionFailed = "落点计算失败"
    }
    
    public enum RangeErrcase: String, ErrList {
        case rangeBeginIndexNotFound = "Range 起始边界未找到"
        case rangeSizeExceed = "Range 结束边界未找到，其大小过大"
        case rangeSizeTooSmall = "Range 结束边界过早结束"
        case rangeSizeInvalid = "Range 大小无效"
    }
}

extension ChunkHelpers {
    /// 用于记录数据落点分析的结果
    struct IntersectionResult: Equatable, CustomStringConvertible {
        let rangeOffset: Int64
        let chunkIndex: Int
        let chunkBegin: Int64
        let chunks: [Int64]
        
        var description: String {
            "(rangeOffset: \(rangeOffset), chunkIndex: \(chunkIndex), chunkBegin: \(chunkBegin), chunks: [\(chunks.map { String($0) }.joined(separator: ", "))])"
        }
    }
    
    /// 数据落点分析算法
    ///
    /// 判断字节 range 具体落在哪些实际 buffers
    ///
    /// - Parameters:
    ///     - range: 字节范围
    ///     - chunks: 所有块大小
    ///     - offset: 块大小的大小偏移量，即 `offsetChunks = [chunks].map { $0 + offset }`
    ///
    /// - Returns:
    ///     - **`rangeOffset`**: range 的起始偏移地址，相对于 `chunkBegin`
    ///     - **`chunkIndex`**: chunks 的起始索引
    ///     - **`chunkBegin`**: chunks 的起始字节位
    ///     - **`chunks`**: 需要处理的 chunks
    ///
    /// -----------
    /// ### 输入参数:
    /// ```
    ///               [-------------------------]                           : range
    /// [----   |--------   |----   |------   |----   |------   |---   ]    : chunks
    /// [-------|-----------|-------|---------|-------|---------|------]
    ///      |  |        |  |    |  |      |  |    |  |      |  |   |  |
    ///      <-->        <-->    <-->      <-->    <-->      <-->   <-->    : offset
    /// ```
    ///
    /// ### 返回参数:
    /// ```
    ///               [-------------------------]                           : range
    /// [----   |--------   |----   |------   |----   |------   |---   ]    : chunks
    /// [-------|-----------|-------|---------|-------|---------|------]
    /// |       |     |                               |
    /// |       <----->                               |                     : rangeOffset
    /// <------->                                     |                     : chunkIndex(Index)
    /// <------->                                     |                     : chunkBegin
    ///         <------------------------------------->                     : chunks
    /// ```
    ///
    static func rangeIntersection(_ range: Range<Int64>, in chunks: BufferSpace, offset: Int64) throws(BscError<RangeErrcase>) -> IntersectionResult {
        
        guard chunks.count > 0 || range.lowerBound > 0 else {
            return .init(rangeOffset: 0, chunkIndex: 0, chunkBegin: 0, chunks: [])
        }
        
        var res: [Int64] = []
        var record = false
        var curChunkIndex = Int64(0)
        var rangeBegin = Int64(-1)
        var chunkBegin = Int64(-1)
        var chunkIndex = -1
        for (i, chunk) in chunks.enumerated() {
            let curChunkRange = curChunkIndex..<(curChunkIndex + chunk)
            
            if curChunkRange.contains(range.lowerBound) {
                // 开始记录
                rangeBegin = range.lowerBound - curChunkRange.lowerBound
                chunkBegin = curChunkRange.lowerBound + Int64(i) * offset
                chunkIndex = i
                
                // 如果 range 是空的，在此处退出，保证 rangeBegin 与 chunkBegin 正确设置
                guard !range.isEmpty else { break }
                
                record = true
            }
            
            if record {
                res.append(chunk + Int64(offset))
            }
            
            // 若查到 range 到头，则终止记录
            guard range.isEmpty || !curChunkRange.contains(range.upperBound - 1) else { record = false; break }
            
            curChunkIndex += chunk
        }
        
        guard record == false else { throw .init(.rangeSizeExceed, "预期的结束边界为 \(chunks.reduce(0, +))，却得到 \(range.upperBound)") }
        guard rangeBegin != -1 else { throw .init(.rangeBeginIndexNotFound, "预期的最大起始边界为 \(chunks.reduce(0, +))，却得到 \(range.lowerBound)") }
        
        return .init(rangeOffset: rangeBegin, chunkIndex: chunkIndex, chunkBegin: chunkBegin, chunks: res)
    }
    
    /// 数据落点分析算法
    static func rangeIntersection(_ range: ClosedRange<Int64>, in chunks: BufferSpace, offset: Int64) throws(BscError<RangeErrcase>) -> IntersectionResult {
        try rangeIntersection(.init(range), in: chunks, offset: offset)
    }
    
    /// 从数据块寻址算法
    static func index(_ index: Int64, in buffer: BufferSpace, offset: Int64) throws(BscError<IndexErrcase>) -> (rangeOffset: Int64, chunkIndex: Int, chunkBegin: Int64) {
        let intersection = try required(throws: BscError<IndexErrcase>(.intersectionFailed)) {
            try rangeIntersection(index..<index, in: buffer, offset: offset)
        }
        return (intersection.rangeOffset, intersection.chunkIndex, intersection.chunkBegin)
    }
}

extension ChunkHelpers {
    
    static var minChunkSize: Int64 { 8192 }
    
    struct ReseparationResult: Sendable, Equatable, CustomStringConvertible {
        
        enum HeadCombine: CustomStringConvertible {
            case none
            case separate
            case combine
            
            var description: String {
                switch self {
                case .none: return "none"
                case .separate: return "separate"
                case .combine: return "combine"
                }
            }
        }
        
        enum TailCombine: Equatable, CustomStringConvertible {
            case none
            case separate(tailLength: Int64, chunkIndex: Int, byteIndex: Int64)
            case combine(tailLength: Int64, chunkIndex: Int, byteIndex: Int64)
            
            var description: String {
                switch self {
                case .none: return "none"
                case .separate(tailLength: let length, let chunkIndex, let byteIndex):
                    return "separate(tailLength: \(length), chunkIndex: \(chunkIndex), byteIndex: \(byteIndex))"
                case .combine(tailLength: let length, let chunkIndex, let byteIndex):
                    return "combine(tailLength: \(length), chunkIndex: \(chunkIndex), byteIndex: \(byteIndex))"
                }
            }
        }
        
        let headCombine: HeadCombine
        let tailCombine: TailCombine
        
        var description: String {
            "(head: \(headCombine), tail: \(tailCombine))"
        }
    }
    
    /// 小数据合并算法
    static func shouldMerge(_ chunk1: Int64, chunk2: Int64) -> Bool {
        chunk1 <= minChunkSize || chunk2 <= minChunkSize
    }
    
    /// 数据重分割算法-覆写
    static func replacementReseparation(_ chunks: BufferSpace, at begin: Int64, in originChunks: BufferSpace) throws(BscError<RangeErrcase>) -> ReseparationResult {
        guard begin >= 0 else {
            throw .init(.rangeSizeInvalid, "起始索引值无效，预期 >= 0，但得到 \(begin)")
        }
        
        guard originChunks.count > 0 || begin > 0 else {
            return .init(headCombine: .none, tailCombine: .none)
        }
        
        guard chunks.first == nil || begin <= chunks.first!, begin >= 0 else {
            throw .init(.rangeBeginIndexNotFound, "预期的最大起始边界为 0..<\(chunks.first!)，却得到 \(begin)")
        }
        
        var stackedLength = begin
        var stackIndex = 0
        var tailParas: (size: Int64, chunkIndex: Int, byteIndex: Int64) = (-1, -1, -1)
        for (i, originChunk) in originChunks.enumerated() {
            
            if i == originChunks.count - 1 {
                if stackIndex == chunks.count {
                    tailParas = (originChunk - stackedLength, i, stackedLength)
                }
                break
            }
            
            var curOriginChunk = originChunk
            while stackedLength <= curOriginChunk {
                curOriginChunk -= stackedLength
                
                guard stackIndex < chunks.count else {
                    throw .init(.rangeSizeTooSmall)
                }
                
                stackedLength = chunks[stackIndex]
                stackIndex += 1
            }
            
            stackedLength -= curOriginChunk
        }
        
        var headCombine: ReseparationResult.HeadCombine = .none
        var tailCombine: ReseparationResult.TailCombine = .none
        
        if begin > 0 {
            headCombine = (chunks.first != nil && shouldMerge(chunks.first!, chunk2: begin)) ? .combine : .separate
        }
        
        if tailParas.size > 0 {
            if chunks.last != nil && shouldMerge(chunks.last!, chunk2: tailParas.size) {
                tailCombine = .combine(tailLength: tailParas.size, chunkIndex: tailParas.chunkIndex, byteIndex: tailParas.byteIndex)
            } else {
                tailCombine = .separate(tailLength: tailParas.size, chunkIndex: tailParas.chunkIndex, byteIndex: tailParas.byteIndex)
            }
        }
        
        return .init(headCombine: headCombine, tailCombine: tailCombine)
    }
    
    /// 数据重分割算法-插入
    static func insertionReseparation(_ chunks: BufferSpace, at begin: Int64, in chunk: Int64) throws(BscError<RangeErrcase>) -> ReseparationResult {
        
        guard begin >= 0, chunk >= 0 else {
            throw .init(.rangeSizeInvalid, "输入参数无效，预期 >= 0，但得到 \(begin) 与 \(chunk)")
        }
        
        guard chunk > 0 || begin > 0 else {
            return .init(headCombine: .none, tailCombine: .none)
        }
        
        guard begin <= chunk, begin >= 0 else {
            throw .init(.rangeBeginIndexNotFound, "预期的最大起始边界为 0..<\(chunk)，却得到 \(begin)")
        }
        
        let tailSize = chunk - begin
        
        var headCombine: ReseparationResult.HeadCombine = .none
        var tailCombine: ReseparationResult.TailCombine = .none
        
        if begin > 0 {
            headCombine = (chunks.first != nil && shouldMerge(chunks.first!, chunk2: begin)) ? .combine : .separate
        }
        
        if tailSize > 0 {
            if chunks.last != nil && shouldMerge(chunks.last!, chunk2: tailSize) {
                tailCombine = .combine(tailLength: tailSize, chunkIndex: 0, byteIndex: begin)
            } else {
                tailCombine = .separate(tailLength: tailSize, chunkIndex: 0, byteIndex: begin)
            }
        }
        
        return .init(headCombine: headCombine, tailCombine: tailCombine)
    }
}

struct BufferSpace: Collection, ExpressibleByArrayLiteral {
    
    typealias ArrayLiteralElement = Int64
    typealias Index = Int
    typealias Element = Int64
    
    private var contents: Contents
    
    enum Contents {
        case array(_ array: [Element])
        case chunk(_ chunkSize: Element, total: Element)
        case buffers(_ buffers: [ByteBuffer])
    }
    
    init(_ contents: Contents) {
        if case let .chunk(chunk, total: _) = contents {
            guard chunk > 0 else {
                preconditionFailure("chunk 大小不能为零或小于零，得到 \(chunk)")
            }
        }
        self.contents = contents
    }
    
    init(arrayLiteral elements: Int64...) {
        self.contents = .array(elements)
    }
    
    let startIndex: Int = 0
    
    var endIndex: Int {
        switch contents {
        case .array(let buffers): return buffers.endIndex
        case .buffers(let buffers): return buffers.endIndex
        case .chunk(let chunkSize, total: let total):
            if total % chunkSize == 0 {
                return Int(total / chunkSize)
            } else {
                return Int(total / chunkSize) + 1
            }
        }
    }
    
    var last: Int64? {
        switch contents {
        case .array(let buffers): return buffers.last
        case .buffers(let buffers): return buffers.last != nil ? Int64(buffers.last!.readableBytes) : nil
        case .chunk(let chunkSize, total: let total):
            guard total > 0 else { return nil }
            if total % chunkSize == 0 {
                return chunkSize
            } else {
                return total % chunkSize
            }
        }
    }
    
    func index(after i: Int) -> Int {
        switch contents {
        case .array(let buffers): return buffers.index(after: i)
        case .buffers(let buffers): return buffers.index(after: i)
        case .chunk: return i + 1
        }
    }
    
    subscript(position: Int) -> Int64 {
        switch contents {
        case .array(let buffers): return buffers[position]
        case .buffers(let buffers): return Int64(buffers[position].readableBytes)
        case .chunk(let chunkSize, total: let total):
            guard position < self.count else { fatalError("Buffer 读取越界，总长度为 \(self.count)，却尝试取得索引 \(position)") }
            if position == self.count - 1 {
                let last = total % chunkSize
                return last == 0 ? chunkSize : last
            } else {
                return chunkSize
            }
        }
    }
}
