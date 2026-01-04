// TTSManager.swift

import Foundation
import AVFoundation
import React

// Define a protocol for volume updates
protocol AudioPlayerDelegate: AnyObject {
    func didUpdateVolume(_ volume: Float)
    func didFinishPlayback(_ playbackId: Int)
}

@objc(TTSManager)
class TTSManager: RCTEventEmitter, AudioPlayerDelegate {
    private var tts: SherpaOnnxOfflineTtsWrapper?
    private var realTimeAudioPlayer: AudioPlayer?
    private var playbackSeq: Int = 0
    private var activePlaybackId: Int = 0
    private var pendingPromises: [Int: (resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock)] = [:]
    private var currentSampleRate: Double = 22050
    private var currentChannels: Int = 1

    override init() {
        super.init()
        // Optionally, initialize AudioPlayer here if needed
    }
    
    // Required for RCTEventEmitter
    override static func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    // Specify the events that can be emitted
    override func supportedEvents() -> [String]! {
        return ["VolumeUpdate"]
    }
    
    // Initialize TTS and Audio Player
    @objc(initializeTTS:channels:modelId:)
    func initializeTTS(_ sampleRate: Double, channels: Int, modelId: String) {
        self.currentSampleRate = sampleRate
        self.currentChannels = channels
        self.realTimeAudioPlayer = AudioPlayer(sampleRate: sampleRate, channels: AVAudioChannelCount(channels))
        self.realTimeAudioPlayer?.delegate = self // Set delegate to receive volume updates
        self.tts = createOfflineTts(modelId: modelId)
    }

    // Generate audio and play in real-time
    @objc(generateAndPlay:sid:speed:resolver:rejecter:)
    func generateAndPlay(_ text: String, sid: Int, speed: Double,
                        resolver: @escaping RCTPromiseResolveBlock,
                        rejecter: @escaping RCTPromiseRejectBlock) {

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            rejecter("EMPTY_TEXT", "Input text is empty", nil)
            return
        }

        guard tts != nil, let player = realTimeAudioPlayer else {
            rejecter("NOT_INITIALIZED", "TTS is not initialized", nil)
            return
        }

        // new playback id
        playbackSeq += 1
        let playbackId = playbackSeq
        activePlaybackId = playbackId
        pendingPromises[playbackId] = (resolve: resolver, reject: rejecter)

        // IMPORTANT: this sets the same playbackId inside AudioPlayer
        player.beginPlayback(playbackId: playbackId)

        let sentences = splitText(trimmedText, maxWords: 15)
        for sentence in sentences {
            let processedSentence = sentence.hasSuffix(".") ? sentence : "\(sentence)."
            generateAudio(for: processedSentence, sid: sid, speed: speed)
        }

        // IMPORTANT: tells AudioPlayer no more buffers are coming
        player.endEnqueue()
    }

    @objc(generateAndSave:path:fileType:resolver:rejecter:)
    func generateAndSave(_ text: String,
                        path: String?,
                        fileType: String?,
                        resolver: @escaping RCTPromiseResolveBlock,
                        rejecter: @escaping RCTPromiseRejectBlock) {

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            rejecter("EMPTY_TEXT", "Input text is empty", nil)
            return
        }
        guard let tts = self.tts else {
            rejecter("NOT_INITIALIZED", "TTS is not initialized", nil)
            return
        }

        let ft = (fileType ?? "wav").lowercased()
        guard ft == "wav" else {
            rejecter("UNSUPPORTED_FILETYPE", "Only wav is supported right now", nil)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let sentences = self.splitText(trimmedText, maxWords: 15)

            var allSamples: [Float] = []
            allSamples.reserveCapacity(22050 * 10)

            for s in sentences {
                let processed = s.hasSuffix(".") ? s : "\(s)."
                let audio = tts.generate(text: processed, sid: 0, speed: 1.0)
                allSamples.append(contentsOf: audio.samples)
            }

            do {
                let outURL = try self.resolveOutputURL(path: path, fileExt: "wav")
                try self.writeWavPCM16(url: outURL,
                                    floatSamples: allSamples,
                                    sampleRate: Int(self.currentSampleRate),
                                    channels: self.currentChannels)
                DispatchQueue.main.async { resolver(outURL.path) }
            } catch {
                DispatchQueue.main.async { rejecter("SAVE_ERROR", error.localizedDescription, error) }
            }
        }
    }



    /// Splits the input text into sentences with a maximum of `maxWords` words.
    /// It prefers to split at a period (.), then a comma (,), and finally forcibly after `maxWords`.
    ///
    /// - Parameters:
    ///   - text: The input text to split.
    ///   - maxWords: The maximum number of words per sentence.
    /// - Returns: An array of sentence strings.
    func splitText(_ text: String, maxWords: Int) -> [String] {
        var sentences: [String] = []
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var currentIndex = 0
        let totalWords = words.count
        
        while currentIndex < totalWords {
            // Determine the range for the current chunk
            let endIndex = min(currentIndex + maxWords, totalWords)
            var chunk = words[currentIndex..<endIndex].joined(separator: " ")
            
            // Search for the last period within the chunk
            if let periodRange = chunk.range(of: ".", options: .backwards) {
                let sentence = String(chunk[..<periodRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                sentences.append(sentence)
                currentIndex += sentence.components(separatedBy: .whitespacesAndNewlines).count
            }
            // If no period, search for the last comma
            else if let commaRange = chunk.range(of: ",", options: .backwards) {
                let sentence = String(chunk[..<commaRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                sentences.append(sentence)
                currentIndex += sentence.components(separatedBy: .whitespacesAndNewlines).count
            }
            // If neither, forcibly break after maxWords
            else {
                sentences.append(chunk.trimmingCharacters(in: .whitespacesAndNewlines))
                currentIndex += maxWords
            }
        }
        
        return sentences
    }
    
    // Helper function to generate and play audio
    private func generateAudio(for text: String, sid: Int, speed: Double) {
        print("Generating audio for \(text)")
        let startTime = Date()
        guard let audio = tts?.generate(text: text, sid: sid, speed: Float(speed)) else {
            print("Error: TTS was never initialised")
            return
        }
        let endTime = Date()
        let generationTime = endTime.timeIntervalSince(startTime)
        print("Time taken for TTS generation: \(generationTime) seconds")
        
        realTimeAudioPlayer?.playAudioData(from: audio)
    }
    
    // Clean up resources
    @objc func deinitialize() {
        for (_, p) in pendingPromises {
            p.reject("STOPPED", "Playback stopped by deinitialize()", nil)
        }
        pendingPromises.removeAll()

        self.realTimeAudioPlayer?.stopAndTearDown()
        self.realTimeAudioPlayer = nil
        self.tts = nil
    }
    
    func didFinishPlayback(_ playbackId: Int) {
        if let p = pendingPromises.removeValue(forKey: playbackId) {
            p.resolve("Playback finished")
        }
    }

    // MARK: - AudioPlayerDelegate Method
    
    func didUpdateVolume(_ volume: Float) {
        // send to JS
        sendEvent(withName: "VolumeUpdate", body: ["volume": volume])

        // fallback: -1 means playback finished
        if volume == -1.0 {
            let id = activePlaybackId
            if let p = pendingPromises.removeValue(forKey: id) {
                p.resolve("Playback finished")
            }
        }
    }

    private func resolveOutputURL(path: String?, fileExt: String) throws -> URL {
        let fm = FileManager.default

        func defaultURL() throws -> URL {
            let dir = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return dir.appendingPathComponent("tts_\(Int(Date().timeIntervalSince1970)).\(fileExt)")
        }

        guard let path, !path.isEmpty else { return try defaultURL() }

        let isAbs = path.hasPrefix("/")
        let base: URL
        if isAbs {
            base = URL(fileURLWithPath: path)
        } else {
            let doc = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            base = doc.appendingPathComponent(path)
        }

        if base.pathExtension.lowercased() == fileExt.lowercased() {
            try fm.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
            return base
        } else {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            return base.appendingPathComponent("tts_\(Int(Date().timeIntervalSince1970)).\(fileExt)")
        }
    }

    private func writeWavPCM16(url: URL, floatSamples: [Float], sampleRate: Int, channels: Int) throws {
        var pcm = Data(capacity: floatSamples.count * 2)

        for f in floatSamples {
            let clamped = max(-1.0 as Float, min(1.0 as Float, f))
            let s = Int16((clamped * 32767.0).rounded())
            var le = s.littleEndian
            withUnsafeBytes(of: &le) { pcm.append(contentsOf: $0) }
        }

        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * channels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(channels) * (bitsPerSample / 8)
        let dataSize = UInt32(pcm.count)
        let riffSize = UInt32(36) + dataSize

        var header = Data()
        header.append(contentsOf: [0x52,0x49,0x46,0x46])                // RIFF
        header.append(contentsOf: leBytes(riffSize))
        header.append(contentsOf: [0x57,0x41,0x56,0x45])                // WAVE
        header.append(contentsOf: [0x66,0x6D,0x74,0x20])                // fmt
        header.append(contentsOf: leBytes(UInt32(16)))                  // fmt size
        header.append(contentsOf: leBytes(UInt16(1)))                   // PCM
        header.append(contentsOf: leBytes(UInt16(channels)))
        header.append(contentsOf: leBytes(UInt32(sampleRate)))
        header.append(contentsOf: leBytes(byteRate))
        header.append(contentsOf: leBytes(blockAlign))
        header.append(contentsOf: leBytes(bitsPerSample))
        header.append(contentsOf: [0x64,0x61,0x74,0x61])                // data
        header.append(contentsOf: leBytes(dataSize))

        var out = Data()
        out.append(header)
        out.append(pcm)

        try out.write(to: url, options: .atomic)
    }

    private func leBytes<T: FixedWidthInteger>(_ v: T) -> [UInt8] {
        var x = v.littleEndian
        return withUnsafeBytes(of: &x) { Array($0) }
    }

}
