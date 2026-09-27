//  DeviceArtwork.swift
//  NOOP · Devices — the product picture a row, a device page and a pairing card lead with, as Apple
//  leads with a photo of the watch or the AirPods. Drawn with shapes (no brand art): a band with its
//  sensor pod, a ring, a chest strap; a glyph for everything else.

import SwiftUI
import StrandDesign
import WhoopStore

/// The drawn shapes the Devices screens have.
enum DeviceArtworkKind: Equatable {
    case band, ring, chestStrap
    case symbol(String)

    /// The art for a registered device.
    @MainActor static func of(_ d: PairedDevice) -> DeviceArtworkKind {
        switch d.sourceKind {
        case .oura: return .ring
        case .ftms: return .symbol("figure.run.treadmill")
        case .liveAppleWatch: return .symbol("applewatch")
        case .huami: return .band
        default: break
        }
        if d.isImportSource { return .symbol("square.and.arrow.down") }
        return SourceCoordinator.isWhoop(d) ? .band : .chestStrap
    }
}

struct DeviceArtwork: View {
    let kind: DeviceArtworkKind
    /// The height the art fills; width follows the shape.
    let size: CGFloat

    var body: some View {
        Group {
            switch kind {
            case .band: band
            case .ring: ring
            case .chestStrap: chestStrap
            case .symbol(let name):
                Image(systemName: name)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.light)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .frame(width: size * 0.62, height: size * 0.62)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var bandFill: LinearGradient {
        LinearGradient(colors: [StrandPalette.deviceBandTop, StrandPalette.deviceBandBottom],
                       startPoint: .leading, endPoint: .trailing)
    }

    private var podFill: LinearGradient {
        LinearGradient(colors: [StrandPalette.devicePodTop, StrandPalette.devicePodBottom],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A strap seen from above: the woven band running top to bottom, the sensor pod across its middle.
    private var band: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(bandFill)
                .frame(width: size * 0.40, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                        .strokeBorder(StrandPalette.deviceEdge, lineWidth: max(0.5, size * 0.006))
                )
            RoundedRectangle(cornerRadius: size * 0.11, style: .continuous)
                .fill(podFill)
                .frame(width: size * 0.54, height: size * 0.38)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(StrandPalette.deviceSheen)
                        .frame(width: size * 0.34, height: max(1, size * 0.02))
                        .padding(.top, size * 0.035)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.11, style: .continuous)
                        .strokeBorder(StrandPalette.deviceEdge, lineWidth: max(0.5, size * 0.008))
                )
                .shadow(color: .black.opacity(0.35), radius: size * 0.03, y: size * 0.015)
        }
    }

    /// A ring at a slight tilt: a thick titanium band with a lit upper edge.
    private var ring: some View {
        ZStack {
            Ellipse()
                .strokeBorder(
                    AngularGradient(colors: [StrandPalette.devicePodTop, StrandPalette.deviceBandBottom,
                                             StrandPalette.devicePodBottom, StrandPalette.devicePodTop],
                                    center: .center),
                    lineWidth: size * 0.15)
                .frame(width: size * 0.86, height: size * 0.70)
            Ellipse()
                .trim(from: 0.58, to: 0.92)
                .stroke(StrandPalette.deviceSheen, style: StrokeStyle(lineWidth: max(1, size * 0.02), lineCap: .round))
                .frame(width: size * 0.78, height: size * 0.62)
        }
    }

    /// A chest strap from the front: an elastic band with the sensor module in the middle.
    private var chestStrap: some View {
        ZStack {
            Capsule()
                .fill(bandFill)
                .frame(width: size, height: size * 0.18)
                .overlay(Capsule().strokeBorder(StrandPalette.deviceEdge, lineWidth: max(0.5, size * 0.006)))
            Capsule()
                .fill(podFill)
                .frame(width: size * 0.46, height: size * 0.34)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(StrandPalette.deviceSheen)
                        .frame(width: size * 0.26, height: max(1, size * 0.02))
                        .padding(.top, size * 0.04)
                }
                .shadow(color: .black.opacity(0.35), radius: size * 0.03, y: size * 0.015)
        }
    }
}
