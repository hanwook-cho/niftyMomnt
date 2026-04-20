// Apps/Piqd/Piqd/UI/Capture/FilmCounterView.swift
// Piqd v0.2 — Roll mode shot counter. Mimics a physical film camera's frame counter
// window with monospaced digits. Visible only in Roll mode; reads from RollCounterRepository
// via a parent-supplied integer pair (used / limit).

import SwiftUI

struct FilmCounterView: View {

    let used: Int
    let limit: Int

    var body: some View {
        // Single Text (with concatenated subtext styles) so SwiftUI exposes one
        // accessibility element whose label refreshes when `used` / `limit` change.
        (
            Text(String(format: "%02d", min(used, 99)))
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            +
            Text(" /\(limit)")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(.black.opacity(0.55))
                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
        )
        .accessibilityIdentifier("piqd-film-counter")
        .accessibilityLabel("Film counter \(used) of \(limit)")
    }
}
