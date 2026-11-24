import AVFoundation
import SwiftUI

struct SpeechFrame {
    let low, high, pitch, intensity: Float
    let formants: [Float]
    let pulses: [Int32]
}

struct SpeechClip {
    static let rate = 16000
    static let limit = 120
    let samples: [Float]
    let frames: [SpeechFrame]
    let spectrum: CGImage
    let limited: Bool
    var duration: Double { Double(samples.count) / Double(Self.rate) }

    static func read(url: URL, channel: Int) throws -> Self {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat, inputRate = Int(format.sampleRate.rounded())
        guard channel >= 0, channel < Int(format.channelCount), inputRate > 0,
              let block = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw SpeechError.empty }
        var pcm = [Float](), weight = 0, sum: Float = 0
        let maxSamples = rate * limit
        while file.framePosition < file.length && pcm.count < maxSamples {
            try Task.checkCancellation()
            try file.read(into: block)
            guard block.frameLength > 0, let input = block.floatChannelData?[channel] else { break }
            for i in 0..<Int(block.frameLength) {
                let sample = input[i].isFinite ? min(1, max(-1, input[i])) : 0
                var remaining = rate
                while remaining > 0 && pcm.count < maxSamples {
                    let overlap = min(remaining, inputRate - weight)
                    sum += sample * Float(overlap)
                    weight += overlap; remaining -= overlap
                    if weight == inputRate { pcm.append(sum / Float(weight)); weight = 0; sum = 0 }
                }
            }
        }
        if weight > 0 && pcm.count < maxSamples { pcm.append(sum / Float(weight)) }
        return try analyze(pcm, limited: Double(file.length)/format.sampleRate > Double(limit))
    }

    // Read only the newest second while the PCM recorder is still writing its WAV file.
    // The final data length in the RIFF header is only reliable after stop().
    static func liveWindow(_ url: URL) throws -> Self? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        try handle.seek(toOffset: 12)
        while try handle.offset() + 8 <= length {
            guard let header = try handle.read(upToCount: 8), header.count == 8 else { return nil }
            let start = try handle.offset()
            if header.prefix(4).elementsEqual("data".utf8) {
                let count = min(Int(length-start)/2, rate)
                guard count >= 1024 else { return nil }
                try handle.seek(toOffset: start + (length-start)/2*2 - UInt64(count*2))
                guard let bytes = try handle.read(upToCount: count*2), bytes.count == count*2 else { return nil }
                let samples: [Float] = bytes.withUnsafeBytes { raw in
                    (0..<count).map { Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $0*2, as: Int16.self))) / 32768 }
                }
                return try analyze(samples)
            }
            let size = header.suffix(4).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset*8) }
            try handle.seek(toOffset: start + size + size%2)
        }
        return nil
    }

    static func analyze(_ pcm: [Float], limited: Bool = false) throws -> Self {
        guard !pcm.isEmpty, pcm.count <= rate * limit else { throw SpeechError.empty }
        let width = (pcm.count + 63) / 64
        var pixels = Data(count: width * 161), frames = [SpeechFrame]()
        var last: Int32 = -1, polarity = 0.0
        var shades = [UInt8](repeating: 0, count: 644), peaks = [Float](repeating: 0, count: 5)
        var pulses = [Int32](repeating: 0, count: 16)
        try pixels.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for start in stride(from: 0, to: pcm.count, by: 256) {
                try Task.checkCancellation()
                let end = min(start + 256, pcm.count)
                var pitch: Float = 0, intensity: Float = 0, count: Int32 = 0
                mcp_measure(pcm, Int32(start), Int32(end), &pitch, &intensity, &peaks, &pulses, &count, &last, &polarity, &shades)
                let chunk = pcm[start..<end]
                frames.append(SpeechFrame(low: chunk.min()!, high: chunk.max()!, pitch: pitch, intensity: intensity,
                                          formants: peaks.filter(\.isFinite), pulses: Array(pulses.prefix(Int(count)))))
                for x in 0..<((end-start+63)/64) {
                    for y in 0..<161 { bytes[(160-y)*width+start/64+x] = shades[x*161+y] }
                }
            }
        }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: width, height: 161, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw SpeechError.empty }
        return Self(samples: pcm, frames: frames, spectrum: image, limited: limited)
    }
}

enum SpeechError: LocalizedError {
    case empty, microphone
    var errorDescription: String? { ui(self == .empty ? "沒有可分析的音訊" : "請允許麥克風權限後再錄音") }
}

@MainActor final class SpeechSession: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published var clip: SpeechClip?
    @Published var recording = false, busy = false, playing = false
    @Published var channels = 0, error: String?
    @Published var permissionPending = false
    private var liveTask: Task<Void, Never>?
    private var channelURL: URL?, temporary: URL?, recorder: AVAudioRecorder?, player: AVAudioPlayer?
    private var worker: Task<SpeechClip, Error>?, generation = 0
    func choose(_ url: URL) {
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let count = try AVAudioFile(forReading: url).processingFormat.channelCount
            if count > 1 { channelURL = url; channels = Int(count) } else { load(url, channel: 0) }
        } catch { self.error = error.localizedDescription }
    }
    func chooseChannel(_ channel: Int) {
        if let url = channelURL { load(url, channel: channel) }
        channels = 0; channelURL = nil
    }
    func cancel() { generation += 1; worker?.cancel(); worker = nil; busy = false }
    func load(_ url: URL, channel: Int) {
        cancel(); stopPlayback(); busy = true
        let token = generation
        let job = Task.detached(priority: .userInitiated) { try SpeechClip.read(url: url, channel: channel) }
        worker = job
        Task {
            let result = await job.result
            guard token == generation else { return }
            busy = false; worker = nil
            switch result {
            case .success(let value): clip = value
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
    func record() async {
        guard !permissionPending && !recording else { return }
        let token = generation
        permissionPending = true
        defer { permissionPending = false }
        let permitted = await AVAudioApplication.requestRecordPermission()
        guard generation == token else { return }
        do {
            guard permitted else { throw SpeechError.microphone }
            stopPlayback()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
            if let temporary { try? FileManager.default.removeItem(at: temporary) }
            temporary = url
            let rec = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
            rec.delegate = self
            guard rec.record(forDuration: Double(SpeechClip.limit)) else { throw SpeechError.empty }
            recorder = rec; recording = true
            liveTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    let preview = await Task.detached { try? SpeechClip.liveWindow(url) }.value
                    guard !Task.isCancelled, recording else { return }
                    if let preview { clip = preview }
                }
            }
        } catch { deactivate(); self.error = error.localizedDescription }
    }
    var elapsed: Double { recorder?.currentTime ?? 0 }
    func stopRecording() { recorder?.stop() }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            self.liveTask?.cancel(); self.liveTask = nil
            self.recording = false; self.recorder = nil; self.deactivate()
            if flag { self.load(recorder.url, channel: 0) } else { self.error = SpeechError.empty.localizedDescription }
        }
    }
    func stopPlayback() { player?.stop(); player = nil; if playing { playing = false; deactivate() } }
    private func deactivate() { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    func play(_ range: ClosedRange<Double>?) {
        guard let clip else { return }
        stopPlayback()
        let lo = max(0, Int((range?.lowerBound ?? 0)*16000)), hi = min(clip.samples.count, Int(((range?.upperBound ?? clip.duration)*16000).rounded()))
        guard hi > lo else { return }
        var data = Data()
        func field<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        data.append(contentsOf: "RIFF".utf8); field(UInt32(36+(hi-lo)*2)); data.append(contentsOf: "WAVEfmt ".utf8)
        field(UInt32(16)); field(UInt16(1)); field(UInt16(1)); field(UInt32(16000)); field(UInt32(32000)); field(UInt16(2)); field(UInt16(16))
        data.append(contentsOf: "data".utf8); field(UInt32((hi-lo)*2))
        let pcm = clip.samples[lo..<hi].map { Int16(clamping: Int(($0*32767).rounded())).littleEndian }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback); try session.setActive(true)
            let p = try AVAudioPlayer(data: data); p.delegate = self
            guard p.play() else { throw SpeechError.empty }
            player = p; playing = true
        } catch { deactivate(); self.error = error.localizedDescription }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if self.player === player { self.stopPlayback() } }
    }
    func close() {
        cancel(); stopPlayback()
        liveTask?.cancel(); liveTask = nil
        recorder?.delegate = nil; recorder?.stop(); recorder = nil
        if recording { recording = false; deactivate() }
        if let temporary { try? FileManager.default.removeItem(at: temporary); self.temporary = nil }
    }
}
