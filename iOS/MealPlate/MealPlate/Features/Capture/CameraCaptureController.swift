import AVFoundation
import SwiftUI
import UIKit

enum CameraCaptureError: LocalizedError {
    case unavailable
    case configurationFailed
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: "当前设备无法使用相机"
        case .configurationFailed: "相机暂时无法启动"
        case .captureFailed: "照片拍摄失败，请重试"
        }
    }
}

@MainActor
final class CameraCaptureController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?

    private let photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((Result<Data, Error>) -> Void)?
    private var isConfigured = false

    var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAccessAndStart() async -> Bool {
        let granted: Bool
        switch authorizationStatus {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            granted = false
        @unknown default:
            granted = false
        }

        guard granted else {
            stop()
            return false
        }

        do {
            try configureIfNeeded()
            if !session.isRunning {
                session.startRunning()
            }
            isReady = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            isReady = false
            return false
        }
    }

    func start() {
        guard isConfigured, !session.isRunning else { return }
        session.startRunning()
        isReady = true
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
        isReady = false
    }

    func capturePhoto() async throws -> Data {
        guard isConfigured, session.isRunning else {
            throw CameraCaptureError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            captureCompletion = { result in
                continuation.resume(with: result)
            }

            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CameraCaptureError.unavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw CameraCaptureError.configurationFailed
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        isConfigured = true
    }
}

extension CameraCaptureController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let result: Result<Data, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(CameraCaptureError.captureFailed)
        }

        Task { @MainActor [weak self] in
            self?.captureCompletion?(result)
            self?.captureCompletion = nil
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
