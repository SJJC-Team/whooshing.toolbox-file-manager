import AsyncAlgorithms
import Foundation
import Cryptos
import NIOAdvanced

enum ChunkHelpers {
    @frozen
    public enum IndexErrcase: String, ErrList {
        case intersectionFailed = "落点计算失败"
    }
    
    @frozen
    public enum RangeErrcase: String, ErrList {
        case rangeBeginIndexNotFound = "Range 起始边界未找到"
        case rangeSizeExceed = "Range 结束边界未找到，其大小过大"
        case rangeSizeTooSmall = "Range 结束边界过早结束"
        case rangeSizeInvalid = "Range 大小无效"
    }
}

extension ChunkHelpers {
    /// 用于记录数据落点分析的结果
    @usableFromInline
    struct IntersectionResult: Equatable, CustomStringConvertible, Loggerable {
        @usableFromInline let rangeOffset: Int64
        @usableFromInline let rangeInIntersection: Bool
        @usableFromInline let chunkIndex: Int
        @usableFromInline let chunkBegin: Int64
        @usableFromInline let chunks: BufferSpace
        
        var json: [String: AnyCodable] {[
            "range_offset": AnyCodable(rangeOffset),
            "range_in_intersection": AnyCodable(rangeInIntersection),
            "chunk_index": AnyCodable(chunkIndex),
            "chunk_begin": AnyCodable(chunkBegin),
            "chunks": AnyCodable(chunks.map { String($0) })
        ]}
        
        @inlinable
        var description: String {
            formatJson(json)
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
    ///     - **`chunkTotalLength`**: chunks 的总大小
    ///
    /// -----------
    /// ### 输入参数:
    /// ```
    ///               [-------------------------]                           : range(without offset)
    /// [----   |--------   |----   |------   |----   |------   |---   ]    : chunks
    /// [-------|-----------|-------|---------|-------|---------|------]
    ///      |  |        |  |    |  |      |  |    |  |      |  |   |  |
    ///      <-->        <-->    <-->      <-->    <-->      <-->   <-->    : offset
    /// ```
    ///
    /// ### 返回参数:
    /// ```
    ///               [-------------------------]                           : range(without offset)
    /// [----   |--------   |----   |------   |----   |------   |---   ]    : chunks
    /// [-------|-----------|-------|---------|-------|---------|------]
    /// |       |     |                               |
    /// |       <----->                               |                     : rangeOffset
    /// <------->                                     |                     : chunkIndex(Index)
    /// <------->                                     |                     : chunkBegin
    ///         <------------------------------------->                     : chunks
    /// ```
    ///
    @inlinable
    static func rangeIntersection(_ range: Range<Int64>, in chunks: BufferSpace, offset: Int64) throws(BscError<RangeErrcase>) -> IntersectionResult {
        
        guard chunks.count > 0 || range.lowerBound > 0 else {
            return .init(rangeOffset: 0, rangeInIntersection: true, chunkIndex: 0, chunkBegin: 0, chunks: [])
        }
        
        if let (chunkSize, total) = chunks.unifiedChunk {
            guard total >= range.lowerBound, 0 <= range.lowerBound else { throw .init(.rangeBeginIndexNotFound, "预期的最大起始边界为 \(total)，却得到 \(range.lowerBound)") }
            guard total >= range.upperBound, 0 <= range.upperBound else { throw .init(.rangeSizeExceed, "预期的结束边界为 \(total)，却得到 \(range.upperBound)") }
            
            if range.lowerBound == total {
                // 表示起点正好在结束位置，表示追加
                return .init(
                    rangeOffset: 0,
                    rangeInIntersection: true,
                    chunkIndex: chunks.count,
                    chunkBegin: total + offset * Int64(chunks.count),
                    chunks: []
                )
            }
            
            let chunkIndex = Int(range.lowerBound / chunkSize)
            let prefixChunkSize = chunks.sum(in: 0..<chunkIndex)
            let rangeOffset = range.lowerBound - prefixChunkSize
            let chunkBegin = prefixChunkSize + Int64(chunkIndex) * offset
            
            if range.isEmpty {
                return .init(
                    rangeOffset: rangeOffset,
                    rangeInIntersection: rangeOffset == 0,
                    chunkIndex: chunkIndex,
                    chunkBegin: chunkBegin,
                    chunks: [chunks[chunkIndex] + offset]
                )
            }
            
            let chunkEndIndex = Int(ceilf(Float(range.upperBound) / Float(chunkSize)))
            let chunkTotalLength = chunks.sum(in: chunkIndex..<chunkEndIndex) + Int64(chunkEndIndex - chunkIndex) * offset
            
            return .init(
                rangeOffset: rangeOffset,
                rangeInIntersection: false,
                chunkIndex: chunkIndex,
                chunkBegin: chunkBegin,
                chunks: .init(.chunk(chunkSize + offset, total: chunkTotalLength))
            )
        }
        
        var res: [Int64] = []
        var record = false
        var curChunkIndex: Int64 = 0
        var rangeBegin: Int64 = -1
        var chunkBegin: Int64 = 0
        var chunkIndex = 0
        var rangeInIntersection = false
        for chunk in chunks {
            
            let curChunkRange = curChunkIndex..<(curChunkIndex + chunk)
            
            if curChunkRange.contains(range.lowerBound) {
                // 开始记录
                rangeBegin = range.lowerBound - curChunkRange.lowerBound
                
                if range.isEmpty {
                    // 如果 range 是空的，在此处退出，保证 rangeBegin, chunkBegin 与 chunks 正确设置
                    res.append(chunk + Int64(offset))
                    if range.lowerBound == curChunkRange.lowerBound {
                        // 仅当 index 在 buffer 的交界线时才会置为 true
                        rangeInIntersection = true
                    }
                    break
                }
                
                record = true
            }
            
            if record {
                res.append(chunk + Int64(offset))
            }
            
            // 若查到 range 到头，则终止记录
            if !range.isEmpty && curChunkRange.contains(range.upperBound - 1) { record = false; break }
            
            curChunkIndex += chunk
            if !record {
                chunkIndex += 1
                chunkBegin += chunk + offset
            }
        }
        
        guard record == false else { throw .init(.rangeSizeExceed, "预期的结束边界为 \(chunks.reduce(0, +))，却得到 \(range.upperBound)") }
        
        if rangeBegin == -1 && curChunkIndex == range.lowerBound && range.isEmpty {
            // 表示起点正好在结束位置，表示追加
            return .init(
                rangeOffset: 0,
                rangeInIntersection: true,
                chunkIndex: chunks.count,
                chunkBegin: chunkBegin,
                chunks: []
            )
        }
        
        guard rangeBegin != -1 else { throw .init(.rangeBeginIndexNotFound, "预期的最大起始边界为 \(chunks.reduce(0, +))，却得到 \(range.lowerBound)") }
        
        return .init(
            rangeOffset: rangeBegin,
            rangeInIntersection: rangeInIntersection,
            chunkIndex: chunkIndex,
            chunkBegin: chunkBegin,
            chunks: .init(.array(res))
        )
    }
    
    /// 数据落点分析算法
    @inlinable
    static func rangeIntersection(_ range: ClosedRange<Int64>, in chunks: BufferSpace, offset: Int64) throws(BscError<RangeErrcase>) -> IntersectionResult {
        try rangeIntersection(.init(range), in: chunks, offset: offset)
    }
    
    /// 从数据块寻址算法
    @inlinable
    static func index(_ index: Int64, in buffer: BufferSpace, offset: Int64) throws(BscError<IndexErrcase>) -> IntersectionResult {
        let intersection = try required(throws: BscError<IndexErrcase>(.intersectionFailed)) {
            try rangeIntersection(index..<index, in: buffer, offset: offset)
        }
        return intersection
    }
}

extension ChunkHelpers {
    
    @inlinable
    static var minChunkSize: Int64 { 8192 }
    
    @usableFromInline
    struct ReseparationResult: Sendable, Equatable, CustomStringConvertible {
        
        @usableFromInline
        enum HeadCombine: CustomStringConvertible {
            case none
            case separate
            case combine
            
            @inlinable
            var description: String {
                switch self {
                case .none: return "none"
                case .separate: return "separate"
                case .combine: return "combine"
                }
            }
        }
        
        @usableFromInline
        enum TailCombine: Equatable, CustomStringConvertible {
            
            @usableFromInline
            struct TailParas: Equatable, CustomStringConvertible {
                let length: Int64
                let chunkIndex: Int
                let chunkBegin: Int64
                let byteOffset: Int64
                
                @inlinable
                var description: String {
                    "tailLength: \(length), tailChunkIndex: \(chunkIndex), tailChunkBegin: \(chunkBegin), tailByteIndex: \(byteOffset)"
                }
            }
            
            case none
            case separate(_ tailPara: TailParas)
            case combine(_ tailPara: TailParas)
            
            @inlinable
            var tail: TailParas? {
                switch self {
                case .none: return nil
                case .separate(let tail): return tail
                case .combine(let tail): return tail
                }
            }
            
            @inlinable
            var description: String {
                switch self {
                case .none: return "none"
                case .separate(let tail): return "separate(\(tail))"
                case .combine(let tail): return "combine(\(tail))"
                }
            }
        }
        
        let headCombine: HeadCombine
        let tailCombine: TailCombine
        
        @inlinable
        var description: String {
            "(head: \(headCombine), tail: \(tailCombine))"
        }
    }
    
    /// 小数据合并算法
    @inlinable
    static func shouldMerge(_ chunk1: Int64, chunk2: Int64) -> Bool {
        chunk1 <= minChunkSize || chunk2 <= minChunkSize
    }
    
    /// 数据重分割算法-覆写
    ///
    /// 重新划分加密 chunk 大小
    ///
    /// - Parameters:
    ///     - chunks: 表示要新插入的数据大小
    ///     - begin:
    ///     - originChunks: 原数据的所有 chunk 大小
    ///     - offset: 块大小的偏移量，即 `offsetChunks = [chunks].map { $0 + offset }`
    ///
    /// - Returns:
    ///     - **`headerCombine`**:
    ///         - **`.none`**: 数据头不存在
    ///         - **`.separate`**: 数据头应当单独作为第一块
    ///         - **`.combine`**: 数据头应当与第一块新数据合并
    ///     - **`tailCombine`**:
    ///         - **`.none`**: 数据尾不存在
    ///         - **`.separate`**: 数据尾应当单独作为最后一块
    ///         - **`.combine`**: 数据尾应当与第一块新数据合并
    ///     - **`tailParas`**:
    ///         - **`length`**: 数据尾的长度
    ///         - **`chunkIndex`**: 数据尾所在的 originChunks 的数组索引值
    ///         - **`chunkBegin`**: 数据尾所在的 originChunks 的起始字节索引值
    ///         - **`byteOffset`**: 数据尾在其 chunk 上的偏移量
    ///
    /// -----------
    /// ### 输入参数:
    /// ```
    ///       [---------|------|-------------]                  : chunks
    /// [-------   |------------   |-------------------   ]
    /// [----------|---------------|----------------------]     : originChunks
    /// |     | |  |            |  |                   |  |
    /// |     | <-->            <-->                   <-->     : offset
    /// <----->                                                 : begin
    ///
    /// ```
    ///
    /// -----------
    /// ### 返回参数:
    /// ```
    ///       [---------|------|-------------]                  : chunks
    /// [-------   |------------   |-------------------   ]     : originChunks
    /// [----------|---------------|----------------------]
    /// |                          |         |        |
    /// |                          |         <-------->         : tail.length
    /// <-------------------------->         |                  : tail.chunkIndex(Index)
    /// <-------------------------->         |                  : tail.chunkBegin
    ///                            <--------->                  : tail.byteOffset
    ///
    /// ```
    @inlinable
    static func replacementReseparation(_ chunks: BufferSpace, at begin: Int64, in originChunks: BufferSpace, offset: Int64) throws(BscError<RangeErrcase>) -> ReseparationResult {
        guard begin >= 0 else {
            throw .init(.rangeSizeInvalid, "起始索引值无效，预期 >= 0，但得到 \(begin)")
        }
        
        guard originChunks.count > 0 || begin > 0 else {
            return .init(headCombine: .none, tailCombine: .none)
        }
        
        guard originChunks.first == nil || begin <= (originChunks.first! - offset), begin >= 0 else {
            throw .init(.rangeBeginIndexNotFound, "预期的最大起始边界为 0..<\(originChunks.first! - offset)，却得到 \(begin)")
        }
        
        var stackedLength = begin
        var stackIndex = 0
        var tailParas = ReseparationResult.TailCombine.TailParas(length: -1, chunkIndex: -1, chunkBegin: -1, byteOffset: -1)
        var curOriginChunkLength: Int64 = 0
        for (i, oc) in originChunks.enumerated() {
            let originChunk = oc - offset
            var curOriginChunk = originChunk
            var curStack = stackedLength
            while stackedLength <= curOriginChunk {
                curOriginChunk -= stackedLength
                
                guard stackIndex < chunks.count else {
                    if i == originChunks.count - 1 {
                        break
                    } else {
                        throw .init(.rangeSizeTooSmall)
                    }
                }
                
                stackedLength = chunks[stackIndex]
                curStack += stackedLength
                stackIndex += 1
            }
            
            if i == originChunks.count - 1 {
                if stackIndex == chunks.count {
                    tailParas = ReseparationResult.TailCombine.TailParas(
                        length: originChunk - curStack,
                        chunkIndex: i,
                        chunkBegin: curOriginChunkLength + Int64(i) * offset,
                        byteOffset: curStack
                    )
                }
                break
            }
            
            stackedLength -= curOriginChunk
            curOriginChunkLength += originChunk
        }
        
        var headCombine: ReseparationResult.HeadCombine = .none
        var tailCombine: ReseparationResult.TailCombine = .none
        
        if begin > 0 {
            headCombine = (chunks.first != nil && shouldMerge(chunks.first! + offset, chunk2: begin)) ? .combine : .separate
        }
        
        if tailParas.length > 0 {
            if chunks.last != nil && shouldMerge(chunks.last! + offset, chunk2: tailParas.length) {
                tailCombine = .combine(tailParas)
            } else {
                tailCombine = .separate(tailParas)
            }
        }
        
        return .init(headCombine: headCombine, tailCombine: tailCombine)
    }
    
    /// 数据重分割算法-覆写
    ///
    /// 重新划分加密 chunk 大小
    ///
    /// - Parameters:
    ///     - chunks: 表示要新插入的数据大小
    ///     - begin:
    ///     - originChunk: 原数据的 chunk 大小
    ///     - offset: 块大小的偏移量，即 `offsetChunks = [chunks].map { $0 + offset }`
    ///
    /// - Returns:
    ///     - **`headerCombine`**:
    ///         - **`.none`**: 数据头不存在
    ///         - **`.separate`**: 数据头应当单独作为第一块
    ///         - **`.combine`**: 数据头应当与第一块新数据合并
    ///     - **`tailCombine`**:
    ///         - **`.none`**: 数据尾不存在
    ///         - **`.separate`**: 数据尾应当单独作为最后一块
    ///         - **`.combine`**: 数据尾应当与第一块新数据合并
    ///     - **`tailParas`**:
    ///         - **`length`**: 数据尾的长度
    ///         - **`chunkIndex`**: 数据尾所在的 originChunks 的数组索引值，一定为 0
    ///         - **`chunkBegin`**: 数据尾所在的 originChunks 的起始字节索引值，一定为 0
    ///         - **`byteOffset`**: 数据尾在其 chunk 上的偏移量
    ///
    /// -----------
    /// ### 输入参数:
    /// ```
    ///       [---------|------|-------------]                  : chunks(without offset)
    /// [----------------------------------------------   ]
    /// [-------------------------------------------------]     : originChunk
    /// |     |                                        |  |
    /// |     |                                        <-->     : offset
    /// <----->                                                 : begin
    ///
    /// ```
    ///
    /// -----------
    /// ### 返回参数:
    /// ```
    ///       [---------|------|-------------]                  : chunks(without offset)
    /// [----------------------------------------------   ]     : originChunk
    /// [-------------------------------------------------]
    /// |     |                                       |
    /// |     <--------------------------------------->         : tail.length
    /// <----->                                                 : tail.byteOffset
    ///
    /// ```
    @inlinable
    static func insertionReseparation(_ chunks: BufferSpace, at begin: Int64, in originChunk: Int64, offset: Int64) throws(BscError<RangeErrcase>) -> ReseparationResult {
        
        guard begin >= 0, originChunk >= 0 else {
            throw .init(.rangeSizeInvalid, "输入参数无效，预期 >= 0，但得到 \(begin) 与 \(originChunk)")
        }
        
        guard originChunk > 0 || begin > 0 else {
            return .init(headCombine: .none, tailCombine: .none)
        }
        
        guard begin <= (originChunk - offset), begin >= 0 else {
            throw .init(.rangeBeginIndexNotFound, "预期的最大起始边界为 0..<\(originChunk - offset)，却得到 \(begin)")
        }
        
        let tailSize = originChunk - offset - begin
        
        var headCombine: ReseparationResult.HeadCombine = .none
        var tailCombine: ReseparationResult.TailCombine = .none
        
        if begin > 0 {
            headCombine = (chunks.first != nil && shouldMerge(chunks.first! + offset, chunk2: begin)) ? .combine : .separate
        }
        
        if tailSize > 0 {
            if chunks.last != nil && shouldMerge(chunks.last! + offset, chunk2: tailSize) {
                tailCombine = .combine(.init(length: tailSize, chunkIndex: 0, chunkBegin: 0, byteOffset: begin))
            } else {
                tailCombine = .separate(.init(length: tailSize, chunkIndex: 0, chunkBegin: 0, byteOffset: begin))
            }
        }
        
        return .init(headCombine: headCombine, tailCombine: tailCombine)
    }
}

extension ChunkHelpers {
    /// 将一个 FilePart 数据库记录照指定的 indexResult 进行分割，产生新实例，不进行任何数据库操作
    ///
    /// - Parameters:
    ///     - part: 要进行分割的 FilePart 实例(一条数据库表记录)
    ///     - fileCrypto: 该分割的 FilePart 的加密分割信息
    ///     - indexResult: 该次分割的详细描述
    /// - Returns: 修改原 part 中的参数的同时，返回新的分割出来的 filePart, 若无法进行分割则返回 nil
    @inlinable
    static func filePartSeparate(
        in part: FilePart,
        fileCrypto: FileCrypto,
        indexResult: ChunkHelpers.IntersectionResult
    ) throws(BscError<FileWriterError>) -> FilePart? {
        if indexResult.rangeInIntersection && indexResult.chunkIndex == 0 && indexResult.rangeOffset == 0 {
            return nil
        }
        
        guard let chunkSize = indexResult.chunks.first else {
            throw FileWriterError.separateFilePartFailed.d("落点判断失败，没有得到 chunk 位置")
        }
        
        let fileId = try required(throws: FileWriterError.separateFilePartFailed, "取得文件 ID 失败") {
            try fileCrypto.requireID()
        }
        
        let newPartByteSize = Int64(indexResult.chunkIndex) * fileCrypto.chunkSize + indexResult.rangeOffset - part.byteHeadIgnore
        
        guard newPartByteSize > 0 else {
            return nil
        }
        
        let newPartEncryptedSize = Int64(indexResult.chunkIndex) * (fileCrypto.chunkSize + Crypto.Symm.Stream.cipherExtraLength)
        
        let newPart = FilePart(
            fileIndexId: fileId,
            tagStart: part.tagStart,
            byteStart: part.byteStart,
            byteEnd: part.byteStart + newPartByteSize,
            byteHeadIgnore: part.byteHeadIgnore,
            byteTailIgnore: indexResult.rangeInIntersection ? 0 : (chunkSize - Crypto.Symm.Stream.cipherExtraLength - indexResult.rangeOffset),
            encryptedStart: part.encryptedStart,
            encryptedEnd: part.encryptedStart + newPartEncryptedSize + (indexResult.rangeInIntersection ? 0 : chunkSize)
        )
        
        part.tagStart += indexResult.chunkIndex
        part.byteStart += newPartByteSize
        part.byteHeadIgnore = indexResult.rangeInIntersection ? 0 : indexResult.rangeOffset
        part.encryptedStart += newPartEncryptedSize
        
        return newPart
    }
}

@usableFromInline
struct BufferSpace: ExpressibleByArrayLiteral, Sendable {
    
    @usableFromInline typealias ArrayLiteralElement = Int64
    @usableFromInline typealias Index = Int
    @usableFromInline typealias Element = Int64
    
    @usableFromInline
    private(set) var contents: Contents
    
    @usableFromInline
    enum Contents: Equatable, Sendable {
        case array(_ array: [Element])
        case chunk(_ chunkSize: Element, total: Element)
        case buffers(_ buffers: [ByteBuffer])
    }
    
    @inlinable
    init(_ contents: Contents) {
        if case let .chunk(chunk, total: _) = contents {
            guard chunk > 0 else {
                preconditionFailure("chunk 大小不能为零或小于零，得到 \(chunk)")
            }
        }
        self.contents = contents
    }
    
    @inlinable
    init(arrayLiteral elements: Int64...) {
        self.contents = .array(elements)
    }
}

extension BufferSpace: Equatable {
    @inlinable
    static func == (lhs: Self, rhs: Self) -> Bool {
        for (i, buffer) in lhs.enumerated() {
            guard rhs[i] == buffer else { return false }
        }
        return true
    }
}

extension BufferSpace {
    @inlinable
    var unifiedChunk: (size: Int64, total: Int64)? {
        switch contents {
        case .array(let buffers):
            return getSum(buffers) { $0 }
        case .buffers(let buffers):
            return getSum(buffers) { Int64($0.readableBytes) }
        case .chunk(let chunkSize, total: let total):
            return (chunkSize, total)
        }
        
        func getSum<T>(_ array: [T], getByte: (T) -> Int64) -> (size: Int64, total: Int64)? {
            guard let first = array.first else { return nil }
            var total: Int64 = 0
            let last = getByte(first)
            for (i, buffer) in array.enumerated() {
                if i != (array.count - 1) && last != getByte(buffer) { return nil }
                total += getByte(buffer)
            }
            return (size: last, total: total)
        }
    }
    
    @inlinable
    func sum(in range: ClosedRange<Int>) -> Int64 {
        precondition(range.lowerBound >= 0, "指定的数组 sum 起始边界无效")
        precondition(range.upperBound < self.count, "指定的数组 sum 结束边界无效，预期在范围 \"\(range.lowerBound)..<\(self.count)\"，却得到 \(range.upperBound)")
        return sum(in: Range<Int>(range))
    }
    
    @inlinable
    func sum(in range: Range<Int>) -> Int64 {
        precondition(range.lowerBound >= 0, "指定的数组 sum 起始边界无效")
        precondition(range.upperBound <= self.count, "指定的数组 sum 结束边界无效，预期在范围 \"\(range.lowerBound)...\(self.count)\"，却得到 \(range.upperBound)")
        
        switch contents {
        case .array(let buffers):
            var result: Int64 = 0
            for i in range {
                result += buffers[i]
            }
            return result
        case .buffers(let buffers):
            var result: Int64 = 0
            for i in range {
                result += Int64(buffers[i].readableBytes)
            }
            return result
        case .chunk(let chunkSize, total: _):
            if range.upperBound == self.count {
                return Int64(range.count - 1) * chunkSize + (self.last ?? 0)
            } else {
                return Int64(range.count) * chunkSize
            }
        }
    }
}

extension BufferSpace: Collection {
    @inlinable
    var startIndex: Int { 0 }
    
    @inlinable
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
    
    @inlinable
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
    
    @inlinable
    func index(after i: Int) -> Int {
        switch contents {
        case .array(let buffers): return buffers.index(after: i)
        case .buffers(let buffers): return buffers.index(after: i)
        case .chunk: return i + 1
        }
    }
    
    @inlinable
    subscript(position: Int) -> Int64 {
        switch contents {
        case .array(let buffers): return buffers[position]
        case .buffers(let buffers): return Int64(buffers[position].readableBytes)
        case .chunk(let chunkSize, total: let total):
            precondition(position < self.count, "Buffer 读取越界，总长度为 \(self.count)，却尝试取得索引 \(position)")
            if position == self.count - 1 {
                let last = total % chunkSize
                return last == 0 ? chunkSize : last
            } else {
                return chunkSize
            }
        }
    }
}

extension AsyncSequence where Element == ByteBuffer, Element: Sendable, Self: Sendable {
    /// 从 AsyncSequence<ByteBuffer> 中按指定大小分块输出
    @inlinable
    func chunkedChannel(_ chunkSize: Int64) -> AsyncThrowingChannel<ByteBuffer, Error> {
        let channel = AsyncThrowingChannel<ByteBuffer, Error>()
        Task {
            do {
                var curChunk = ByteBuffer()
                for try await var chunk in self {
                    curChunk.writeBuffer(&chunk)
                    while curChunk.readableBytes >= chunkSize {
                        let data = curChunk.readSlice(length: Int(chunkSize))!
                        await channel.send(data.cloned)
                    }
                }
                if curChunk.readableBytes > 0 {
                    await channel.send(curChunk.cloned)
                }
                channel.finish()
            } catch {
                channel.fail(error)
            }
        }
        return channel
    }
}
extension AsyncSequence where Element == Data, Element: Sendable, Self: Sendable {
    /// 从 AsyncSequence<Data> 中按指定大小分块输出
    @inlinable
    func chunkedChannel(_ chunkSize: Int64) -> AsyncThrowingChannel<Data, Error> {
        let channel = AsyncThrowingChannel<Data, Error>()
        Task {
            do {
                var curChunk = Data()
                for try await chunk in self {
                    curChunk.append(chunk)

                    while curChunk.count >= chunkSize {
                        let size = Int(chunkSize)
                        let part = curChunk.prefix(size)
                        await channel.send(part)
                        curChunk.removeFirst(size)
                    }
                }

                if !curChunk.isEmpty {
                    await channel.send(curChunk)
                }

                channel.finish()
            } catch {
                channel.fail(error)
            }
        }

        return channel
    }
}

extension ByteBuffer {
    @inlinable
    public var cloned: ByteBuffer {
        var new = ByteBufferAllocator().buffer(capacity: self.readableBytes)
        new.writeBytes(self.readableBytesView)
        return new
    }
}
