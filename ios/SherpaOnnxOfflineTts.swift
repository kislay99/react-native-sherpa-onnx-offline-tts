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
}
