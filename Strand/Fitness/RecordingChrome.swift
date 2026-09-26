//  RecordingChrome.swift
//  NOOP · the pieces every "something is running" screen shares, so a workout, a gym session and an interval
//  timer look like one app: the Fitness recording screen's large figures, its page dots, and the dark panel
//  at the bottom — grabber, activity glyph, green clock, a trailing accessory, and three round buttons.

import SwiftUI
import StrandDesign

/// One live figure: a large rounded numeral with its small-caps label beside it, as Fitness stacks them.
struct LiveFigure: View {
    static let numeral = Font.system(size: 88, weight: .regular, design: .rounded)

    let value: String
    var unit: String = ""
    /// Already localized; set in capitals here, as Fitness sets its labels.
    let label: String
    var tint: Color = .white

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            (Text(value).font(Self.numeral)
             + Text(unit.uppercased()).font(.system(size: 40, weight: .medium, design: .rounded)))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
                .padding(.top, 14)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The small caption over a recording page ("SET 2 OF 4", "WORK") in the stage's hue, with the title under it.
struct RecordingHeading: View {
    let caption: String
    var tint: Color = .white.opacity(0.6)
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(.system(size: 15, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Fitness's page dots under the figures.
struct RecordingPageDots: View {
    let count: Int
    let selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(.white.opacity(i == selection ? 1 : 0.35)).frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A round control in the panel. `prominent` fills it Exercise green with a black glyph (the main action).
struct RecordingButton: View {
    let symbol: String
    var size: CGFloat = 76
    var prominent = false
    var tint: Color = .white
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size >= 100 ? 40 : 24, weight: .semibold))
                .foregroundStyle(prominent ? StrandPalette.fitnessOnAccent : tint)
                .frame(width: size, height: size)
                .background(Circle().fill(prominent ? StrandPalette.activityExerciseText : Color(white: 0.2)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// The recording panel: grabber, the activity glyph, a clock, a trailing accessory, then three buttons
/// with the main one in the middle. Sits flush with the bottom edge like a sheet, as in Fitness.
struct RecordingPanel<Clock: View, Trailing: View, Leading: View, Center: View, Right: View>: View {
    let glyph: AnyView
    @ViewBuilder let clock: () -> Clock
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let center: () -> Center
    @ViewBuilder let right: () -> Right

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            HStack {
                glyph
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(StrandPalette.fitnessCard))
                Spacer()
                clock()
                Spacer()
                trailing().frame(width: 44, height: 44)
            }
            HStack {
                leading()
                Spacer()
                center()
                Spacer()
                right()
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38, style: .continuous)
                .fill(Color(white: 0.11))
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// The panel's clock face: large rounded digits in Exercise green (or the rest yellow).
struct RecordingClockText: View {
    let text: String
    var tint: Color = StrandPalette.activityExerciseText

    var body: some View {
        Text(text)
            .font(.system(size: 42, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// The top row of a recording screen: ⌄ to put the screen away while what it records keeps running.
struct RecordingTopBar: View {
    let onMinimize: () -> Void

    var body: some View {
        HStack {
            RecordingButton(symbol: "chevron.down", size: 44, label: "Minimize", action: onMinimize)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
