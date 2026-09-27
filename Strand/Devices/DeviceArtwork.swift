//  DeviceArtwork.swift
//  NOOP · Devices — the picture a device row, a device page, a pairing card and first-run setup lead
//  with. No product art: each kind of device is one SF Symbol, drawn the way iOS 26 setup screens draw
//  their header glyph (OnBoardingKit: 46 pt Light, large scale, system blue, gradient colour).

import SwiftUI
import StrandDesign
import WhoopStore
import WhoopProtocol

/// What kind of device a picture stands for.
enum DeviceArtworkKind: Equatable {
    /// A WHOOP strap of one generation.
    case strap(DeviceFamily)
    case ring
    case heartRateStrap
    case gymMachine
    case appleWatch
    /// A band with a screen (Amazfit, Mi Band).
    case wristband
    /// A sports watch broadcasting heart rate (Garmin).
    case sportsWatch
    case importSource

    /// The art for a registered device.
    @MainActor static func of(_ d: PairedDevice) -> DeviceArtworkKind {
        switch d.sourceKind {
        case .oura: return .ring
        case .ftms: return .gymMachine
        case .liveAppleWatch: return .appleWatch
        case .huami: return .wristband
        default: break
        }
        if d.isImportSource { return .importSource }
        if SourceCoordinator.isWhoop(d), let family = DeviceFamily.forRegistryDevice(model: d.model, brand: d.brand) {
            return .strap(family)
        }
        return .heartRateStrap
    }

    /// A WHOOP strap from a registry model label or a `WhoopModel` raw value — read through the one resolver
    /// allowed to interpret those labels.
    static func whoop(registryModel: String?) -> DeviceArtworkKind {
        .strap(DeviceFamily.forRegistryModel(registryModel))
    }

    var systemName: String {
        switch self {
        case .strap:          return "applewatch.side.right"
        case .ring:
            if #available(iOS 26.0, macOS 26.0, *) { return "ring" }
            return "circle.circle"
        case .heartRateStrap: return "heart.circle"
        case .gymMachine:
            if #available(iOS 18.0, macOS 15.0, *) { return "figure.run.treadmill" }
            return "figure.indoor.cycle"
        case .appleWatch:     return "applewatch"
        case .wristband:      return "applewatch.side.right"
        case .sportsWatch:    return "applewatch"
        case .importSource:   return "square.and.arrow.down"
        }
    }
}

struct DeviceArtwork: View {
    let kind: DeviceArtworkKind
    /// The square the glyph sits in; 82 is the setup header's slot.
    let size: CGFloat

    var body: some View {
        SetupGlyph(systemName: kind.systemName, size: size)
            .accessibilityHidden(true)
    }
}

/// An SF Symbol as the iOS 26 setup header draws one: Light weight at the large scale, in system blue with
/// the gradient colour rendering. 46 pt in the 82 pt slot; other slots scale from that.
struct SetupGlyph: View {
    let systemName: String
    var size: CGFloat = 82
    var tint: Color = StrandPalette.settingsBlue

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 46 / 82, weight: .light))
            .imageScale(.large)
            .foregroundStyle(tint)
            .setupGradientRendering()
            .frame(width: size, height: size)
    }
}

extension View {
    @ViewBuilder
    fileprivate func setupGradientRendering() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.symbolColorRenderingMode(.gradient)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
