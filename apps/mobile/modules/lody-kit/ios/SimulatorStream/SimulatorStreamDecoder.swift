import CoreMedia
import UIKit

/// baguette's `avcc` stream: `[type][payload]` per WebSocket message, where
/// 0x01 is an avcC record, 0x02/0x03 are length-prefixed key/delta frames and
/// 0x04 is a JPEG shown until the first keyframe decodes.
@MainActor final class SimulatorStreamDecoder {
  enum Output {
    case seed(UIImage)
    case frame(CMSampleBuffer)
  }

  private var format: CMVideoFormatDescription?
  private var awaitingKeyFrame = true
  var onOutput: ((Output) -> Void)?

  func reset() {
    format = nil
    awaitingKeyFrame = true
  }

  func handle(_ data: Data) {
    guard data.count > 1 else { return }
    let type = data[data.startIndex]
    let payload = data.dropFirst()
    switch type {
    case 0x01:
      format = Self.format(avcC: [UInt8](payload))
      awaitingKeyFrame = true
    case 0x02, 0x03:
      // Keyframes arrive about every five seconds, so a delta is never dropped
      // once decoding has started: skipping one corrupts every frame until the next.
      if type == 0x02 { awaitingKeyFrame = false }
      guard !awaitingKeyFrame, let format, let sample = Self.sample(Data(payload), format: format) else { return }
      onOutput?(.frame(sample))
    case 0x04:
      if let image = UIImage(data: Data(payload)) { onOutput?(.seed(image)) }
    default:
      break
    }
  }

  static func format(avcC bytes: [UInt8]) -> CMVideoFormatDescription? {
    guard bytes.count > 7, bytes[0] == 1 else { return nil }
    let lengthSize = Int32(bytes[4] & 0x03) + 1
    var cursor = 6
    var sets: [[UInt8]] = []
    func readSets(count: Int) -> Bool {
      for _ in 0..<count {
        guard cursor + 2 <= bytes.count else { return false }
        let length = Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1])
        cursor += 2
        guard length > 0, cursor + length <= bytes.count else { return false }
        sets.append(Array(bytes[cursor..<cursor + length]))
        cursor += length
      }
      return true
    }
    guard readSets(count: Int(bytes[5] & 0x1F)), !sets.isEmpty, cursor < bytes.count else { return nil }
    let ppsCount = Int(bytes[cursor])
    cursor += 1
    guard readSets(count: ppsCount), sets.count >= 2 else { return nil }
    var format: CMVideoFormatDescription?
    let status = sets.withUnsafeParameterPointers { pointers, sizes in
      CMVideoFormatDescriptionCreateFromH264ParameterSets(
        allocator: kCFAllocatorDefault, parameterSetCount: sets.count,
        parameterSetPointers: pointers, parameterSetSizes: sizes,
        nalUnitHeaderLength: lengthSize, formatDescriptionOut: &format)
    }
    return status == noErr ? format : nil
  }

  static func sample(_ payload: Data, format: CMVideoFormatDescription) -> CMSampleBuffer? {
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: payload.count,
      blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
      dataLength: payload.count, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
      let block else { return nil }
    let copied = payload.withUnsafeBytes { raw in
      CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: payload.count)
    }
    guard copied == noErr else { return nil }
    var sample: CMSampleBuffer?
    var size = payload.count
    guard CMSampleBufferCreateReady(
      allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
      sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
      sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
      let sample else { return nil }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
       CFArrayGetCount(attachments) > 0 {
      let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(
        dictionary,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
    return sample
  }
}

private extension Array where Element == [UInt8] {
  func withUnsafeParameterPointers<R>(_ body: ([UnsafePointer<UInt8>], [Int]) -> R) -> R {
    let buffers = map { set -> UnsafeMutablePointer<UInt8> in
      let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count)
      pointer.update(from: set, count: set.count)
      return pointer
    }
    defer { buffers.forEach { $0.deallocate() } }
    return body(buffers.map { UnsafePointer($0) }, map(\.count))
  }
}
