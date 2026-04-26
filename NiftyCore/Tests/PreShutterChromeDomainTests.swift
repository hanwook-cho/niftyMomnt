// NiftyCore/Tests/PreShutterChromeDomainTests.swift
// Piqd v0.4 — domain types for pre-shutter Layer 1 chrome.

import XCTest
@testable import NiftyCore

final class PreShutterChromeDomainTests: XCTestCase {

    // MARK: - LayerChromeState

    func test_layerChromeState_hasThreeCases() {
        XCTAssertEqual(Set(LayerChromeState.allCases), Set([.rest, .revealed, .formatSelector]))
    }

    func test_layerChromeState_rawValuesAreStable() {
        // Persisted in dev settings; renaming would invalidate stored state.
        XCTAssertEqual(LayerChromeState.rest.rawValue, "rest")
        XCTAssertEqual(LayerChromeState.revealed.rawValue, "revealed")
        XCTAssertEqual(LayerChromeState.formatSelector.rawValue, "formatSelector")
    }

    // MARK: - ZoomLevel

    func test_zoomLevel_factors() {
        XCTAssertEqual(ZoomLevel.ultraWide.factor, 0.5, accuracy: 0.0001)
        XCTAssertEqual(ZoomLevel.wide.factor, 1.0, accuracy: 0.0001)
        XCTAssertEqual(ZoomLevel.telephoto.factor, 2.0, accuracy: 0.0001)
    }

    func test_zoomLevel_availableForBack_isAllThree() {
        XCTAssertEqual(ZoomLevel.available(for: .back), [.ultraWide, .wide, .telephoto])
    }

    func test_zoomLevel_availableForFront_isWideOnly() {
        XCTAssertEqual(ZoomLevel.available(for: .front), [.wide])
    }

    // MARK: - VibeSignal

    func test_vibeSignal_hasThreeCases() {
        XCTAssertEqual(Set(VibeSignal.allCases), Set([.quiet, .neutral, .social]))
    }

    // MARK: - FaceFramingSignal

    func test_faceFramingSignal_okEqualsOk() {
        XCTAssertEqual(FaceFramingSignal.ok, FaceFramingSignal.ok)
    }

    func test_faceFramingSignal_edgeProximity_distinguishesSides() {
        XCTAssertEqual(FaceFramingSignal.edgeProximity(side: .top), .edgeProximity(side: .top))
        XCTAssertNotEqual(FaceFramingSignal.edgeProximity(side: .top), .edgeProximity(side: .leading))
        XCTAssertNotEqual(FaceFramingSignal.ok, .edgeProximity(side: .top))
    }

    // MARK: - AspectRatio Snap-cycle (extension)

    func test_aspectRatio_snapAllowed_isNineSixteenAndOneOne() {
        XCTAssertEqual(AspectRatio.snapAllowed, [.nineSixteen, .oneOne])
    }

    func test_aspectRatio_nextSnapRatio_cycles() {
        XCTAssertEqual(AspectRatio.nineSixteen.nextSnapRatio(), .oneOne)
        XCTAssertEqual(AspectRatio.oneOne.nextSnapRatio(), .nineSixteen)
    }

    func test_aspectRatio_nextSnapRatio_fromUnsupported_returnsDefault() {
        // 4:3 isn't in Snap's allowed set — cycling from it returns the Snap default.
        XCTAssertEqual(AspectRatio.fourThree.nextSnapRatio(), .nineSixteen)
    }
}
