import CoreGraphics
import Darwin
import Foundation
import os

/// Recognizes text through AccurateOCRHelper using AccurateOCRConnection.
/// Keeping accurate model initialization in that process lets fast OCR remain available in the app.
actor AccurateOCR: OCRPreparing, TextRecognizing {
    private var connection: AccurateOCRConnection?

    func prepare() async throws {
        try Task.checkCancellation()
        if self.connection != nil {
            return
        }

        let connection = try AccurateOCRConnection()
        do {
            try await withTaskCancellationHandler {
                try connection.start()
                try Task.checkCancellation()
            } onCancel: {
                connection.stop()
            }
            self.connection = connection
        } catch {
            connection.stop()
            throw error
        }
    }

    func recognizeText(from image: CGImage) async throws -> String {
        try Task.checkCancellation()
        guard let connection = self.connection else { throw OCRError.recognitionFailed }

        do {
            let text = try await withTaskCancellationHandler {
                try connection.recognizeText(from: image)
            } onCancel: {
                connection.stop()
            }
            try Task.checkCancellation()
            return text
        } catch {
            connection.stop()
            self.connection = nil
            try Task.checkCancellation()
            throw error
        }
    }

    deinit { connection?.stop() }
}

/// Exchanges recognition requests and responses over pipes with the bundled AccurateOCRHelper.
/// Owns that process's launch, readiness handshake, and shutdown.
private struct AccurateOCRConnection: Sendable {
    private let process: Process
    private let reader: FileHandle
    private let writer: FileHandle
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    init() throws {
        guard let executable = Bundle.main.executableURL?
            .deletingLastPathComponent().appendingPathComponent("AccurateOCRHelper")
        else { throw OCRError.recognitionFailed }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.qualityOfService = .utility
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        self.process = process
        self.reader = output.fileHandleForReading
        self.writer = input.fileHandleForWriting
        // A stopped helper must produce a recoverable write error, not SIGPIPE.
        guard fcntl(self.writer.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { throw OCRError.recognitionFailed }
    }

    func start() throws {
        try self.stopped.withLock { stopped in
            guard !stopped else { throw CancellationError() }
            try self.process.run()
        }
        guard try AccurateOCRProtocol.read(from: self.reader) == Data([0]) else {
            throw OCRError.recognitionFailed
        }
    }

    func recognizeText(from image: CGImage) throws -> String {
        let data = try AccurateOCRProtocol.encode(image)
        try AccurateOCRProtocol.write(data, to: self.writer)
        guard let response = try AccurateOCRProtocol.read(from: self.reader), response.first == 0,
              let text = String(data: response.dropFirst(), encoding: .utf8)
        else { throw OCRError.recognitionFailed }
        return text
    }

    func stop() {
        self.stopped.withLock { stopped in
            guard !stopped else { return }
            stopped = true
            if self.process.isRunning {
                self.process.terminate()
            }
            try? self.writer.close()
            try? self.reader.close()
        }
    }
}
