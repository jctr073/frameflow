import Foundation
import ImageIO

enum AnimatedWebPMuxer {
    struct Canvas: Sendable {
        let width: Int
        let height: Int
    }

    struct Frame: Sendable {
        var x: Int
        var y: Int
        let width: Int
        let height: Int
        var durationMS: Int
        var flags: UInt8
        let payload: Data
        let hasAlpha: Bool

        var duration: TimeInterval {
            TimeInterval(durationMS) / 1000
        }
    }

    struct ClipFrames: Sendable {
        let canvas: Canvas
        let frames: [Frame]
    }

    struct Document: Sendable {
        let canvas: Canvas
        let frames: [Frame]

        var duration: TimeInterval {
            frames.reduce(TimeInterval(0)) { $0 + $1.duration }
        }

        init(url: URL) throws {
            let data = try Data(contentsOf: url)
            let parsed = try AnimatedWebPMuxer.parse(data: data, url: url)
            canvas = parsed.canvas
            frames = parsed.frames
        }

        func frames(overlappingStart trimStart: TimeInterval, end trimEnd: TimeInterval) -> [Frame] {
            var selected: [Frame] = []
            var frameStart = TimeInterval(0)

            for frame in frames {
                let frameDuration = frame.duration
                let frameEnd = frameStart + frameDuration
                defer { frameStart = frameEnd }

                guard frameEnd > trimStart, frameStart < trimEnd else {
                    continue
                }

                let clippedDuration = min(frameEnd, trimEnd) - max(frameStart, trimStart)
                guard clippedDuration > 0 else {
                    continue
                }

                var clippedFrame = frame
                clippedFrame.durationMS = max(20, Int((clippedDuration * 1000).rounded()))
                selected.append(clippedFrame)
            }

            return selected
        }
    }

    private struct Chunk {
        let type: String
        let payload: Data
    }

    static func write(_ clips: [ClipFrames], to destinationURL: URL) throws {
        let clips = clips.filter { !$0.frames.isEmpty }
        guard !clips.isEmpty else {
            throw MediaExportError.emptyTimeline
        }

        let outputCanvas = Canvas(
            width: clips.map(\.canvas.width).max() ?? 0,
            height: clips.map(\.canvas.height).max() ?? 0
        )
        guard outputCanvas.width > 0, outputCanvas.height > 0 else {
            throw MediaExportError.cannotCreateDestination
        }

        let hasAlpha = clips.flatMap(\.frames).contains { $0.hasAlpha }
        var body = Data()

        var vp8x = Data()
        vp8x.appendUInt8((hasAlpha ? 0x10 : 0) | 0x02)
        vp8x.append(contentsOf: [0, 0, 0])
        vp8x.appendUInt24LE(outputCanvas.width - 1)
        vp8x.appendUInt24LE(outputCanvas.height - 1)
        body.appendWebPChunk(type: "VP8X", payload: vp8x)

        var anim = Data()
        anim.append(contentsOf: [0, 0, 0, 255])
        anim.appendUInt16LE(0)
        body.appendWebPChunk(type: "ANIM", payload: anim)

        for clip in clips {
            let baseX = evenOffset(forContent: clip.canvas.width, in: outputCanvas.width)
            let baseY = evenOffset(forContent: clip.canvas.height, in: outputCanvas.height)

            for (index, frame) in clip.frames.enumerated() {
                let isFirstFrameInClip = index == clip.frames.startIndex
                let isLastFrameInClip = index == clip.frames.index(before: clip.frames.endIndex)
                var flags = frame.flags
                if isFirstFrameInClip {
                    flags |= 0x02
                }
                if isLastFrameInClip {
                    flags |= 0x01
                }

                var payload = Data()
                payload.appendUInt24LE((frame.x + baseX) / 2)
                payload.appendUInt24LE((frame.y + baseY) / 2)
                payload.appendUInt24LE(frame.width - 1)
                payload.appendUInt24LE(frame.height - 1)
                payload.appendUInt24LE(frame.durationMS)
                payload.appendUInt8(flags)
                payload.append(frame.payload)
                body.appendWebPChunk(type: "ANMF", payload: payload)
            }
        }

        var output = Data()
        output.appendASCII("RIFF")
        output.appendUInt32LE(body.count + 4)
        output.appendASCII("WEBP")
        output.append(body)
        try output.write(to: destinationURL, options: .atomic)
    }

    private static func parse(data: Data, url: URL) throws -> (canvas: Canvas, frames: [Frame]) {
        let bytes = [UInt8](data)
        guard bytes.count >= 12,
              ascii(bytes, 0, 4) == "RIFF",
              ascii(bytes, 8, 4) == "WEBP"
        else {
            throw MediaExportError.cannotLoadSource
        }

        var chunks: [Chunk] = []
        var offset = 12
        while offset + 8 <= bytes.count {
            let type = ascii(bytes, offset, 4)
            let size = Int(readUInt32LE(bytes, offset + 4))
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + size
            guard payloadEnd <= bytes.count else {
                throw MediaExportError.cannotLoadSource
            }
            chunks.append(Chunk(type: type, payload: Data(bytes[payloadStart..<payloadEnd])))
            offset = payloadEnd + (size & 1)
        }

        let vp8x = chunks.first { $0.type == "VP8X" }
        let vp8xBytes = vp8x.map { [UInt8]($0.payload) }
        let canvasFromHeader: Canvas? = vp8xBytes.flatMap { payload in
            guard payload.count >= 10 else { return nil }
            return Canvas(width: readUInt24LE(payload, 4) + 1, height: readUInt24LE(payload, 7) + 1)
        }
        let sourceHasAlpha = (vp8xBytes?.first ?? 0) & 0x10 != 0

        let animatedFrames = chunks.filter { $0.type == "ANMF" }.compactMap { chunk -> Frame? in
            let payload = [UInt8](chunk.payload)
            guard payload.count >= 16 else { return nil }
            let imagePayload = chunk.payload.dropFirst(16)
            return Frame(
                x: readUInt24LE(payload, 0) * 2,
                y: readUInt24LE(payload, 3) * 2,
                width: readUInt24LE(payload, 6) + 1,
                height: readUInt24LE(payload, 9) + 1,
                durationMS: max(20, readUInt24LE(payload, 12)),
                flags: payload[15],
                payload: Data(imagePayload),
                hasAlpha: sourceHasAlpha || containsAlphaChunk(Data(imagePayload))
            )
        }

        if !animatedFrames.isEmpty {
            guard let canvas = canvasFromHeader else {
                throw MediaExportError.cannotLoadSource
            }
            return (canvas, animatedFrames)
        }

        let frameChunks = chunks.filter { $0.type == "ALPH" || $0.type == "VP8 " || $0.type == "VP8L" }
        guard let imageChunk = frameChunks.last(where: { $0.type == "VP8 " || $0.type == "VP8L" }) else {
            throw MediaExportError.cannotLoadSource
        }

        let canvas = canvasFromHeader
            ?? imageCanvas(from: imageChunk)
            ?? imageCanvas(from: url)
        guard let canvas else {
            throw MediaExportError.cannotLoadSource
        }

        var payload = Data()
        for chunk in frameChunks {
            payload.appendWebPChunk(type: chunk.type, payload: chunk.payload)
        }

        let frame = Frame(
            x: 0,
            y: 0,
            width: canvas.width,
            height: canvas.height,
            durationMS: 1000,
            flags: 0x02,
            payload: payload,
            hasAlpha: sourceHasAlpha || frameChunks.contains { $0.type == "ALPH" || $0.type == "VP8L" }
        )
        return (canvas, [frame])
    }

    private static func imageCanvas(from chunk: Chunk) -> Canvas? {
        let bytes = [UInt8](chunk.payload)
        switch chunk.type {
        case "VP8 ":
            guard bytes.count >= 10 else { return nil }
            return Canvas(
                width: Int(readUInt16LE(bytes, 6) & 0x3fff),
                height: Int(readUInt16LE(bytes, 8) & 0x3fff)
            )
        case "VP8L":
            guard bytes.count >= 5, bytes[0] == 0x2f else { return nil }
            let b1 = Int(bytes[1])
            let b2 = Int(bytes[2])
            let b3 = Int(bytes[3])
            let b4 = Int(bytes[4])
            let width = 1 + (((b2 & 0x3f) << 8) | b1)
            let height = 1 + (((b4 & 0x0f) << 10) | (b3 << 2) | ((b2 & 0xc0) >> 6))
            return Canvas(width: width, height: height)
        default:
            return nil
        }
    }

    private static func imageCanvas(from url: URL) -> Canvas? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return Canvas(width: width, height: height)
    }

    private static func containsAlphaChunk(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var offset = 0
        while offset + 8 <= bytes.count {
            let type = ascii(bytes, offset, 4)
            if type == "ALPH" || type == "VP8L" {
                return true
            }
            let size = Int(readUInt32LE(bytes, offset + 4))
            let nextOffset = offset + 8 + size + (size & 1)
            guard nextOffset > offset, nextOffset <= bytes.count else {
                return false
            }
            offset = nextOffset
        }
        return false
    }

    private static func evenOffset(forContent contentSize: Int, in canvasSize: Int) -> Int {
        let offset = max(0, (canvasSize - contentSize) / 2)
        return offset - (offset % 2)
    }

    private static func ascii(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> String {
        String(bytes: bytes[offset..<(offset + count)], encoding: .ascii) ?? ""
    }

    private static func readUInt16LE(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt24LE(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8) | (Int(bytes[offset + 2]) << 16)
    }

    private static func readUInt32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(contentsOf: value.utf8)
    }

    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt16LE(_ value: Int) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt24LE(_ value: Int) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
    }

    mutating func appendUInt32LE(_ value: Int) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    mutating func appendWebPChunk(type: String, payload: Data) {
        appendASCII(type)
        appendUInt32LE(payload.count)
        append(payload)
        if payload.count.isMultiple(of: 2) == false {
            appendUInt8(0)
        }
    }
}
