//
//  QRScannerView.swift
//  Easy Schedule
//
//  Camera QR scanner used to read a partner's invitation code. The decoded
//  string is fed straight into the existing add-partner flow (resolveUid).
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - SwiftUI sheet (permission + viewfinder)

struct QRScannerSheet: View {

    /// Called with the decoded string (the partner's invitation code).
    let onScanned: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch status {
            case .authorized:
                scanner
            case .notDetermined:
                ProgressView()
                    .tint(.white)
                    .onAppear(perform: requestAccess)
            default:
                permissionDenied
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding()
        }
    }

    // MARK: Authorized – live camera + viewfinder

    private var scanner: some View {
        ZStack {
            QRScannerView { code in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onScanned(code)
                dismiss()
            }
            .ignoresSafeArea()

            // Viewfinder frame + hint
            VStack(spacing: 20) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 240, height: 240)
                    .shadow(color: .black.opacity(0.4), radius: 8)

                Text(String(localized: "partner.scan_hint"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .shadow(radius: 4)
            }
        }
    }

    // MARK: Denied / restricted

    private var permissionDenied: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
            Text(String(localized: "partner.camera_denied"))
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button(String(localized: "open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }

    private func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                status = granted ? .authorized : .denied
            }
        }
    }
}

// MARK: - AVFoundation camera bridge

struct QRScannerView: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> QRScannerController {
        let vc = QRScannerController()
        vc.onFound = { context.coordinator.handle($0) }
        return vc
    }

    func updateUIViewController(_ vc: QRScannerController, context: Context) {}

    final class Coordinator {
        let onFound: (String) -> Void
        private var didEmit = false
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func handle(_ code: String) {
            guard !didEmit else { return }   // fire once
            didEmit = true
            onFound(code)
        }
    }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onFound: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.layer.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        startSession()
    }

    private func startSession() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    private func stopSession() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue, !value.isEmpty else { return }
        stopSession()
        onFound?(value)
    }
}
