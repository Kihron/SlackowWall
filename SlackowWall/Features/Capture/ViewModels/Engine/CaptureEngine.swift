//
//  CaptureEngine.swift
//  SlackowWall
//
//  Created by Kihron on 1/12/23.
//

import AVFAudio
import Combine
import Foundation
import OSLog
import ScreenCaptureKit

/// A structure that contains the video data to render.
struct CapturedFrame {
    static let invalid = CapturedFrame(
        surface: nil, contentRect: .zero, contentScale: 0, scaleFactor: 0)

    let surface: IOSurface?
    let contentRect: CGRect
    let contentScale: CGFloat
    let scaleFactor: CGFloat
    var size: CGSize { contentRect.size }
}

/// An object that wraps an instance of `SCStream`, and returns its results as an `AsyncThrowingStream`.
class CaptureEngine: NSObject, @unchecked Sendable {

    private let logger = Logger()

    private var streams: [SCStream] = []
    private let videoSampleBufferQueue = DispatchQueue(label: "slackowWall.VideoSampleBufferQueue")

    // Store the the startCapture continuation, so that you can cancel it when you call stopCapture().
    private var continuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?

    private var streamOutputs = [CaptureEngineStreamOutput]()

    /// - Tag: StartCapture
    func startCapture(configuration: SCStreamConfiguration, filter: SCContentFilter)
        -> AsyncThrowingStream<CapturedFrame, Error>
    {
        AsyncThrowingStream<CapturedFrame, Error> { continuation in
            // The stream output object.
            let streamOutput = CaptureEngineStreamOutput(continuation: continuation)
            streamOutputs.append(streamOutput)
            streamOutput.capturedFrameHandler = { continuation.yield($0) }

            do {
                let stream = SCStream(
                    filter: filter, configuration: configuration, delegate: streamOutput)

                // Add a stream output to capture screen content.
                try stream.addStreamOutput(
                    streamOutput, type: .screen, sampleHandlerQueue: videoSampleBufferQueue)
                stream.startCapture()
                streams.append(stream)
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func stopCapture(removeStreams: Bool = false) async {
        for stream in streams {
            try? await stream.stopCapture()
        }

        if removeStreams {
            streams.removeAll()
        }

        continuation?.finish()
    }

    func resumeCapture() async {
        for stream in streams {
            do {
                try await stream.startCapture()
                continuation?.finish()
            } catch {
                streams.removeAll(where: { $0 == stream })
                continuation?.finish(throwing: error)
            }
        }
    }

    /// - Tag: UpdateStreamConfiguration
    func update(configuration: SCStreamConfiguration, filter: SCContentFilter) async {
        do {
            for stream in streams {
                try await stream.updateConfiguration(configuration)
                try await stream.updateContentFilter(filter)
            }
        } catch {
            logger.error("Failed to update the stream sessions: \(String(describing: error))")
        }
    }
}

/// A class that handles output from an SCStream, and handles stream errors.
private class CaptureEngineStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {

    var pcmBufferHandler: ((AVAudioPCMBuffer) -> Void)?
    var capturedFrameHandler: ((CapturedFrame) -> Void)?

    // Store the the startCapture continuation, so you can cancel it if an error occurs.
    private var continuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?

    init(continuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?) {
        self.continuation = continuation
    }

    /// - Tag: DidOutputSampleBuffer
    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {

        // Return early if the sample buffer is invalid.
        guard sampleBuffer.isValid else { return }

        // Determine which type of data the sample buffer contains.
        switch outputType {
            case .screen:
                // Create a CapturedFrame structure for a video sample buffer.
                guard let frame = createFrame(for: sampleBuffer) else { return }
                capturedFrameHandler?(frame)
            case .audio:
                // Create an AVAudioPCMBuffer from an audio sample buffer.
                //            guard let samples = createPCMBuffer(for: sampleBuffer) else { return }
                //            pcmBufferHandler?(samples)
                return
            case .microphone:
                return
            @unknown default:
                fatalError("Encountered unknown stream output type: \(outputType)")
        }
    }

    /// Create a `CapturedFrame` for the video sample buffer.
    private func createFrame(for sampleBuffer: CMSampleBuffer) -> CapturedFrame? {

        // Retrieve the array of metadata attachments from the sample buffer.
        guard
            let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let attachments = attachmentsArray.first
        else { return nil }

        // Validate the status of the frame. If it isn't `.complete`, return nil.
        guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
            let status = SCFrameStatus(rawValue: statusRawValue),
            status == .complete
        else { return nil }

        // Get the pixel buffer that contains the image data.
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return nil }

        // Get the backing IOSurface.
        guard let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
            return nil
        }
        let surface = unsafeBitCast(surfaceRef, to: IOSurface.self)

        // Retrieve the content rectangle, scale, and scale factor.
        guard let contentRectDict = attachments[.contentRect],
            let contentRect = CGRect(dictionaryRepresentation: contentRectDict as! CFDictionary),
            let contentScale = attachments[.contentScale] as? CGFloat,
            let scaleFactor = attachments[.scaleFactor] as? CGFloat
        else { return nil }

        // Create a new frame with the relevant data.
        let frame = CapturedFrame(
            surface: surface,
            contentRect: contentRect,
            contentScale: contentScale,
            scaleFactor: scaleFactor)
        return frame
    }

    // Creates an AVAudioPCMBuffer instance on which to perform an average and peak audio level calculation.
    private func createPCMBuffer(for sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        var ablPointer: UnsafePointer<AudioBufferList>?
        try? sampleBuffer.withAudioBufferList { audioBufferList, blockBuffer in
            ablPointer = audioBufferList.unsafePointer
        }
        guard let audioBufferList = ablPointer,
            let absd = sampleBuffer.formatDescription?.audioStreamBasicDescription,
            let format = AVAudioFormat(
                standardFormatWithSampleRate: absd.mSampleRate, channels: absd.mChannelsPerFrame)
        else { return nil }
        return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        continuation?.finish(throwing: error)
    }
}
