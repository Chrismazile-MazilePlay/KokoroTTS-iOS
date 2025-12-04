//
//  AudioPlayer.swift
//  Example
//
//  Created by Marat Zainullin on 10/07/2025.
//

import AVFoundation
import SwiftUI

class AudioPlayer: NSObject, ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    private var audioBuffer: AVAudioPCMBuffer?
    private var displayLink: CADisplayLink?
    
    override init() {
        super.init()
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        
        // Don't connect yet - we'll do it when we know the format
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    func loadAudio(samples: [Float], sampleRate: Double) {
        // Disconnect any existing connection
        audioEngine.disconnectNodeOutput(playerNode)
        
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        
        // Connect with the correct format
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            print("Failed to create audio buffer")
            return
        }
        
        buffer.frameLength = AVAudioFrameCount(samples.count)
        
        // Copy samples to buffer
        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { samplesPointer in
                channelData[0].update(from: samplesPointer.baseAddress!, count: samples.count)
            }
        }
        
        audioBuffer = buffer
        duration = Double(samples.count) / sampleRate
        currentTime = 0
    }
    
    func play() {
        guard let buffer = audioBuffer else { return }
        
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("Failed to start audio engine: \(error)")
                return
            }
        }
        
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                self?.isPlaying = false
                self?.currentTime = 0
                self?.stopDisplayLink()
            }
        }
        
        playerNode.play()
        isPlaying = true
        startDisplayLink()
    }
    
    func pause() {
        playerNode.pause()
        isPlaying = false
        stopDisplayLink()
    }
    
    func stop() {
        playerNode.stop()
        isPlaying = false
        currentTime = 0
        stopDisplayLink()
    }
    
    func seek(to time: TimeInterval) {
        guard let buffer = audioBuffer else { return }
        
        let wasPlaying = isPlaying
        stop()
        
        let sampleTime = AVAudioFramePosition(time * buffer.format.sampleRate)
        let framesToPlay = buffer.frameLength - AVAudioFrameCount(sampleTime)
        
        if framesToPlay > 0 {
            // Create a new buffer with the remaining audio
            let format = buffer.format
            guard let newBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToPlay) else { return }
            newBuffer.frameLength = framesToPlay
            
            // Copy the audio data starting from the seek position
            if let originalData = buffer.floatChannelData,
               let newData = newBuffer.floatChannelData {
                let startSample = Int(sampleTime)
                for channel in 0..<Int(format.channelCount) {
                    for frame in 0..<Int(framesToPlay) {
                        newData[channel][frame] = originalData[channel][startSample + frame]
                    }
                }
            }
            
            playerNode.scheduleBuffer(newBuffer, at: nil, options: []) { [weak self] in
                DispatchQueue.main.async {
                    self?.isPlaying = false
                    self?.currentTime = 0
                    self?.stopDisplayLink()
                }
            }
            
            if wasPlaying {
                playerNode.play()
                isPlaying = true
                startDisplayLink()
            }
        }
        
        currentTime = time
    }
    
    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateTime))
        displayLink?.add(to: .current, forMode: .common)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func updateTime() {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              let buffer = audioBuffer else { return }
        
        currentTime = Double(playerTime.sampleTime) / buffer.format.sampleRate
    }
}