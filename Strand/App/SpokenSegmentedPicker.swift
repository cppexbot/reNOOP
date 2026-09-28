//  SpokenSegmentedPicker.swift
//  NOOP · Health's range control: letters on screen (Н·М·6М·Г), whole words for VoiceOver (CR-3).
//  A segmented control reads its segments' own text and ignores a label set on it, so VoiceOver gets
//  a twin control with the spoken names instead.

import SwiftUI

struct SpokenSegmentedPicker<Option: Hashable & Identifiable>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String
    let spoken: (Option) -> String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options) { Text(verbatim: label($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityRepresentation {
            Picker("", selection: $selection) {
                ForEach(options) { Text(verbatim: spoken($0)).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}
