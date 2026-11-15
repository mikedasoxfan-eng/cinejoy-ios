import AVFoundation
import CoreVideo

// Tiny, entirely synthetic movie for deterministic native caption QA.
let target = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: target)
let writer = try AVAssetWriter(outputURL: target, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: 640, AVVideoHeightKey: 360
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 360
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
for frame in 0..<120 {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    var buffer: CVPixelBuffer?
    precondition(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess)
    let pixels = buffer!
    CVPixelBufferLockBaseAddress(pixels, [])
    let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(pixels)
    for y in 0..<360 {
        for x in 0..<640 {
            let index = y * stride + x * 4
            base[index] = 255; base[index + 1] = UInt8(18 + (x + frame) % 30)
            base[index + 2] = UInt8(40 + y % 40); base[index + 3] = 80
        }
    }
    CVPixelBufferUnlockBaseAddress(pixels, [])
    precondition(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 2)))
}
input.markAsFinished()
let complete = DispatchSemaphore(value: 0)
writer.finishWriting { complete.signal() }
complete.wait()
precondition(writer.status == .completed, "Fixture encoding failed: \(String(describing: writer.error))")
