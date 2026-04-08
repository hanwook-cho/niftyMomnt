// Apps/niftyMomnt/UI/CaptureHub/StripPreviewSheet.swift
// Shown after all 4 shots are captured.
// Displays the composited strip, lets user change border colour live,
// then Save & Share or Retake.

import NiftyCore
import SwiftUI
import UIKit

struct StripPreviewSheet: View {
    let container: AppContainer
    let shots: [(Asset, Data)]
    let initialFrame: FeaturedFrame
    let onSaved: (L4CRecord) -> Void
    let onRetake: () -> Void

    @State private var selectedBorder: L4CBorderColor = .white
    @State private var selectedFrame: FeaturedFrame
    @State private var previewImage: UIImage? = nil
    @State private var isCompositing: Bool = false
    @State private var isSaving: Bool = false
    @State private var shareItem: UIImage? = nil
    @State private var showShareSheet: Bool = false
    @State private var errorMessage: String? = nil

    private let photoDatas: [Data]

    init(container: AppContainer, shots: [(Asset, Data)],
         initialFrame: FeaturedFrame,
         onSaved: @escaping (L4CRecord) -> Void,
         onRetake: @escaping () -> Void) {
        self.container = container
        self.shots = shots
        self.initialFrame = initialFrame
        self.onSaved = onSaved
        self.onRetake = onRetake
        self._selectedFrame = State(initialValue: initialFrame)
        self.photoDatas = shots.map(\.1)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Strip preview
                    stripPreview
                        .padding(.top, 8)

                    Spacer()

                    // Border colour picker
                    borderPicker
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)

                    // Action buttons
                    actionButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Retake", action: onRetake)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = shareItem {
                ActivityViewController(activityItems: [img])
            }
        }
        .task { await recomposite() }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Strip Preview

    private var stripPreview: some View {
        ZStack {
            if let img = previewImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 460)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .white.opacity(0.08), radius: 12)
                    .transition(.opacity)
            } else {
                // Placeholder while compositing
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 180, height: 320)
                    .overlay(
                        ProgressView()
                            .tint(.white.opacity(0.6))
                    )
            }

            if isCompositing {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: previewImage == nil)
    }

    // MARK: - Border Picker

    private var borderPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BORDER")
                .font(.system(size: 10, weight: .heavy))
                .kerning(1.5)
                .foregroundStyle(.white.opacity(0.4))

            HStack(spacing: 16) {
                ForEach(L4CBorderColor.allCases, id: \.rawValue) { color in
                    borderSwatch(color)
                }
                Spacer()
            }
        }
    }

    private func borderSwatch(_ color: L4CBorderColor) -> some View {
        let isSelected = color == selectedBorder
        return Button {
            selectedBorder = color
            Task { await recomposite() }
        } label: {
            Circle()
                .fill(color.swatchColor)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.white : .white.opacity(0.2),
                        lineWidth: isSelected ? 2.5 : 0.5
                    )
                )
                .scaleEffect(isSelected ? 1.12 : 1)
                .animation(.spring(response: 0.25), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Save & Share — primary
            Button(action: saveAndShare) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Save & Share")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white)
                .clipShape(Capsule())
            }
            .disabled(isSaving || isCompositing)

            // Save to Photos — secondary chip
            Button(action: saveToPhotos) {
                Label("Save to Photos", systemImage: "photo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .disabled(isSaving || isCompositing)
        }
    }

    // MARK: - Actions

    private func recomposite() async {
        guard !photoDatas.isEmpty else { return }
        isCompositing = true
        do {
            let data = try await container.lifeFourCutsUseCase.recomposite(
                photos: photoDatas,
                frame: selectedFrame,
                borderColor: selectedBorder
            )
            previewImage = UIImage(data: data)
        } catch {
            #if DEBUG
            print("[StripPreview] recomposite failed: \(error)")
            #endif
        }
        isCompositing = false
    }

    private func saveAndShare() {
        isSaving = true
        Task {
            do {
                let record = try await container.lifeFourCutsUseCase.buildAndSave(
                    shots: shots,
                    frame: selectedFrame,
                    borderColor: selectedBorder,
                    config: container.config
                )
                if let img = previewImage {
                    shareItem = img
                    showShareSheet = true
                }
                onSaved(record)
            } catch {
                errorMessage = "Could not save: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }

    private func saveToPhotos() {
        guard let img = previewImage else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
    }
}

// MARK: - L4CBorderColor → SwiftUI Color (for swatch UI only)

private extension L4CBorderColor {
    var swatchColor: Color {
        switch self {
        case .white:      return .white
        case .black:      return Color(white: 0.08)
        case .pastelPink: return Color(red: 1,    green: 0.84, blue: 0.88)
        case .skyBlue:    return Color(red: 0.53, green: 0.81, blue: 0.98)
        }
    }
}
