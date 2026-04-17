// Apps/Piqd/Piqd/UI/Capture/PiqdCaptureView.swift
// v0.1 Snap-Still capture screen. Single responsibility: show preview, shutter button, confirm
// that a tap persisted an asset. No mode switching, no presets, no grain, no Sound Stamp.

import AVFoundation
import NiftyCore
import SwiftUI

struct PiqdCaptureView: View {
    let container: PiqdAppContainer

    @State private var isCapturing = false
    @State private var flashAssetID: String?
    @State private var errorText: String?
    @State private var cameraAuthorized = true

    var body: some View {
        ZStack {
            CameraPreviewView(session: container.captureSession)
                .ignoresSafeArea()
                .accessibilityIdentifier("piqd.capture")

            if flashAssetID != nil {
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityElement()
                    .accessibilityIdentifier("piqd.captureIndicator")
            }

            if !cameraAuthorized {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                    Text("Camera access needed in Settings")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("piqd.cameraDeniedHint")
            }

            VStack {
                Spacer()
                shutterButton
                    .padding(.bottom, 48)
            }

            if let errorText {
                VStack {
                    Spacer()
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.red.opacity(0.8), in: .rect(cornerRadius: 8))
                        .padding(.bottom, 140)
                }
            }
        }
        .background(.black)
        .task {
            await startPreview()
        }
    }

    private var shutterButton: some View {
        Button {
            Task { await handleShutter() }
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(.white)
                    .frame(width: 64, height: 64)
                    .scaleEffect(isCapturing ? 0.85 : 1.0)
            }
        }
        .disabled(isCapturing)
        .accessibilityIdentifier("piqd.shutter")
    }

    private func startPreview() async {
        // UI6: explicit override so XCUITest can assert the denied-state hint without toggling
        // system privacy settings.
        if ProcessInfo.processInfo.environment["PIQD_FORCE_CAMERA_DENIED"] == "1" {
            cameraAuthorized = false
            return
        }
        // Check current camera auth so UI6 can surface the denied-state hint without relying on
        // the AVCaptureSession error path (which would just leave a black preview).
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted {
            cameraAuthorized = false
            return
        }
        do {
            try await container.captureUseCase.startPreview(mode: .still, config: container.config)
            cameraAuthorized = true
        } catch {
            errorText = "preview failed: \(error.localizedDescription)"
        }
    }

    private func handleShutter() async {
        isCapturing = true
        defer { isCapturing = false }
        errorText = nil

        // UI-test short-circuit: simulator has no real camera, so the AVFoundation pipeline
        // fails silently. Persist a stub asset + moment directly through the Managers so UI2–UI5
        // can verify flash, debug list, and cross-launch persistence deterministically.
        if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" {
            // Show flash first and leave it up — XCUITest's wait-for-idle can outlast a
            // brief animated overlay, so the indicator must be sticky for deterministic polling.
            flashAssetID = UUID().uuidString
            await persistTestStub()
            return
        }

        do {
            let asset = try await container.captureUseCase.captureAsset()
            withAnimation(.easeOut(duration: 0.15)) {
                flashAssetID = asset.id.uuidString
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeIn(duration: 0.15)) {
                flashAssetID = nil
            }
        } catch {
            errorText = "capture failed: \(error.localizedDescription)"
        }
    }

    /// Writes a 1×1 JPEG + a single-asset Moment so the debug feed reflects UI-test taps.
    /// Real-device capture runs through CaptureMomentUseCase; this path is only hit when the
    /// PIQD test harness sets UI_TEST_MODE=1.
    private func persistTestStub() async {
        let asset = Asset(type: .still, capturedAt: Date())
        let data = PiqdCaptureView.onePixelJPEG
        try? await container.vaultManager.save(asset, data: data)
        let moment = Moment(
            id: UUID(),
            label: "UI Test",
            assets: [asset],
            centroid: GPSCoordinate(latitude: 0, longitude: 0),
            startTime: asset.capturedAt,
            endTime: asset.capturedAt,
            dominantVibes: [],
            moodPoint: nil,
            isStarred: false,
            heroAssetID: asset.id
        )
        try? await container.graphManager.saveMoment(moment)
    }

    // Minimal valid JPEG (1×1 black pixel) — just enough bytes for VaultRepository.save to
    // succeed and for the thumbnail path to decode to something.
    private static let onePixelJPEG: Data = Data([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
        0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
        0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
        0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
        0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
        0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
        0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
        0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
        0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
        0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06,
        0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
        0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72,
        0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45,
        0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
        0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75,
        0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3,
        0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
        0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9,
        0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
        0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4,
        0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01,
        0x00, 0x00, 0x3F, 0x00, 0xFB, 0xD0, 0xFF, 0xD9
    ])
}
