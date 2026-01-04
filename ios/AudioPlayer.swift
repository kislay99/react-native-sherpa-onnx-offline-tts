//  AudioPlayer.swift
//
//  Updated: 26-Apr-2025
//
//  Changes
//  --------
//  • setupAudioSession(): removed .defaultToSpeaker, added .allowBluetooth / .allowBluetoothA2DP
//  • Added buffer-completion handler that sends –1 when the queue is empty and playback stops
//  • Guard to send that completion flag only once per playback run
//

import Foundation
import AVFoundation
import Accelerate

class AudioPlayer: NSObject {
    // MARK: - Properties

    private let audioEngine = AVAudioEngine()
    private let audioPlayerNode = AVAudioPlayerNode()
    private let audioFormat: AVAudioFormat
    private var audioQueue: [Data] = []
    private let queueLock = NSLock()
    private var isProcessing = false

    private var playbackId: Int = 0
    private var enqueueClosed: Bool = true
    private var pendingScheduled: Int = 0
    private var didSignalFinish: Bool = false

    // Volume Monitoring
    private var volumeTimer: Timer?
    private var currentVolume: Float = 0.0
    private let volumeUpdateInterval: TimeInterval = 0.2

    // End-of-playback tracking
    private var sentCompletion = false

    // Delegate
    weak var delegate: AudioPlayerDelegate?

    // MARK: - Initialization

    init(sampleRate: Double, channels: AVAudioChannelCount) {
        self.audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        )!

        super.init()

        setupAudioSession()
        setupAudioEngine()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        DispatchQueue.global(qos: .background).async { self.processAudioQueue() }
        DispatchQueue.main.async { self.startVolumeTimer() }
    }

    deinit {
        stop()
        audioEngine.mainMixerNode.removeTap(onBus: 0)
        NotificationCenter.default.removeObserver(self)
        deactivateAudioSession()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP] // ← no .defaultToSpeaker
            )
            try session.setActive(true, options: [])
            print("Audio session set up for Bluetooth or speaker")
        } catch {
            print("Failed to set up AVAudioSession: \(error)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate AVAudioSession: \(error)")
        }
    }

    // MARK: - Engine

    private func setupAudioEngine() {
        audioEngine.attach(audioPlayerNode)
        audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        addAudioTap()

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start AVAudioEngine: \(error)")
        }
    }

    // MARK: - Public play API

    func playAudioData(from audio: SherpaOnnxGeneratedAudioWrapper) {
        let sampleCount = Int(audio.n)
        let data = Data(bytes: audio.samples, count: sampleCount * MemoryLayout<Float>.size)

        queueLock.lock()
        audioQueue.append(data)
        sentCompletion = false                 // reset “finished” flag for this run
        queueLock.unlock()
    }

    // MARK: - Processing loop

    private func processAudioQueue() {
        isProcessing = true
        while isProcessing {
            queueLock.lock()
            if !audioQueue.isEmpty {
                let data = audioQueue.removeFirst()
                queueLock.unlock()

                guard let pcmBuf = AVAudioPCMBuffer(
                    pcmFormat: audioFormat,
                    frameCapacity: AVAudioFrameCount(data.count) / audioFormat.streamDescription.pointee.mBytesPerFrame
                ) else {
                    continue
                }
                pcmBuf.frameLength = pcmBuf.frameCapacity

                // copy bytes
                data.withUnsafeBytes { rbp in
                    pcmBuf.floatChannelData!.pointee.assign(
                        from: rbp.baseAddress!.assumingMemoryBound(to: Float.self),
                        count: Int(pcmBuf.frameLength)
                    )
                }

                // schedule with completion handler
                audioPlayerNode.scheduleBuffer(pcmBuf, at: nil, options: []) { [weak self] in
                    guard let self = self else { return }
                    self.checkForPlaybackEnd()
                }

                if !audioPlayerNode.isPlaying { audioPlayerNode.play() }
            } else {
                queueLock.unlock()
                usleep(10_000)
            }
        }
    }

    // Called from every buffer’s completion handler
    private func checkForPlaybackEnd() {
        queueLock.lock()
        let finished = enqueueClosed && audioQueue.isEmpty && pendingScheduled == 0
        let shouldSignal = finished && !didSignalFinish
        if shouldSignal { didSignalFinish = true }
        queueLock.unlock()

        if shouldSignal {
            DispatchQueue.main.async {
                self.audioPlayerNode.stop()
                self.delegate?.didUpdateVolume(-1.0) // <-- this will now resolve the promise
            }
        }
    }


    // MARK: - Volume metering

    private func addAudioTap() {
        let mixer = audioEngine.mainMixerNode
        mixer.installTap(onBus: 0, bufferSize: 1024, format: mixer.outputFormat(forBus: 0)) { [weak self] buf, _ in
            guard let self else { return }
            let channels = Int(buf.format.channelCount)
            var rms: Float = 0
            if let chData = buf.floatChannelData {
                let frames = Int(buf.frameLength)
                for c in 0..<channels {
                    var sum: Float = 0
                    vDSP_rmsqv(chData[c], 1, &sum, vDSP_Length(frames))
                    rms += sum
                }
                self.currentVolume = rms / Float(channels)
            }
        }
    }

    private func startVolumeTimer() {
        volumeTimer = Timer.scheduledTimer(withTimeInterval: volumeUpdateInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.delegate?.didUpdateVolume(self.currentVolume)
            }
        }
    }

    // MARK: - Interruptions

    @objc private func handleInterruption(notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type {
        case .began:
            audioPlayerNode.pause()

        case .ended:
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(
                    .playback,
                    mode: .default,
                    options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP]
                )
                try session.setActive(true, options: [])
                if !audioEngine.isRunning { try audioEngine.start() }
                if !audioPlayerNode.isPlaying && !audioQueue.isEmpty { audioPlayerNode.play() }
            } catch {
                print("Could not resume after interruption: \(error)")
            }

        @unknown default: break
        }
    }

    func beginPlayback(playbackId: Int) {
        queueLock.lock()
        self.playbackId = playbackId
        self.enqueueClosed = false
        self.didSignalFinish = false
        self.pendingScheduled = 0
        self.audioQueue.removeAll()
        self.currentVolume = 0
        queueLock.unlock()

        DispatchQueue.main.async {
            if !self.audioEngine.isRunning {
                try? self.audioEngine.start()
            }
            self.audioPlayerNode.stop()
            self.audioPlayerNode.reset()
        }
    }

    func endEnqueue() {
        queueLock.lock()
        enqueueClosed = true
        queueLock.unlock()
        checkForPlaybackEnd()
    }

    // MARK: - Stop

    func stopAndTearDown() {
        isProcessing = false

        queueLock.lock()
        audioQueue.removeAll()
        enqueueClosed = true
        pendingScheduled = 0
        queueLock.unlock()

        DispatchQueue.main.async {
            self.volumeTimer?.invalidate()
            self.volumeTimer = nil

            self.audioPlayerNode.stop()
            self.audioPlayerNode.reset()

            self.audioEngine.stop()
            self.audioEngine.reset()

            self.audioEngine.mainMixerNode.removeTap(onBus: 0)

            self.deactivateAudioSession()

            self.delegate?.didUpdateVolume(-1.0)
        }
    }


    func stop() {
        isProcessing = false
        volumeTimer?.invalidate()
        audioEngine.stop()
        audioPlayerNode.stop()
        delegate?.didUpdateVolume(-1.0)        // also inform on manual stop
    }
}
