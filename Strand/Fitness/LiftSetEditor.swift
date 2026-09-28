//  LiftSetEditor.swift
//  NOOP · one set of a gym session, edited the way Clock edits an alarm: weight and reps on wheels, RPE and
//  warm-up below, ✕ and ✓ in the toolbar. Opens from a row of the session's set list.

import SwiftUI
import StrandDesign

struct LiftSetEditor: View {
    let title: String
    let exercise: String
    let system: UnitSystem
    /// Last session's numbers for this set ("75 × 10"), shown under the wheels.
    let lastTime: String?
    /// False while this set is the one being performed — there is nothing to start.
    let canStart: Bool
    let isDone: Bool
    /// Weight in kilograms (nil = none), reps, RPE, warm-up.
    let onSave: (Double?, Int?, Double?, Bool) -> Void
    let onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// Weight in the reader's unit, on the wheel's steps.
    @State private var weight: Double
    @State private var reps: Int
    @State private var rpe: Double?
    @State private var warmup: Bool

    init(title: String, exercise: String, system: UnitSystem, weightKg: Double?, reps: Int?, rpe: Double?,
         warmup: Bool, lastTime: String?, canStart: Bool, isDone: Bool,
         onSave: @escaping (Double?, Int?, Double?, Bool) -> Void, onStart: @escaping () -> Void) {
        self.title = title
        self.exercise = exercise
        self.system = system
        self.lastTime = lastTime
        self.canStart = canStart
        self.isDone = isDone
        self.onSave = onSave
        self.onStart = onStart
        let step = Self.step(system)
        let shown = weightKg.map { LiftFormat.display(fromKilograms: $0, system: system) } ?? 0
        _weight = State(initialValue: min(Self.maxWeight(system), (shown / step).rounded() * step))
        _reps = State(initialValue: min(Self.maxReps, reps ?? 0))
        _rpe = State(initialValue: rpe.map { ($0 * 2).rounded() / 2 })
        _warmup = State(initialValue: warmup)
    }

    private static func step(_ system: UnitSystem) -> Double { system == .imperial ? 1 : 0.5 }
    private static func maxWeight(_ system: UnitSystem) -> Double { system == .imperial ? 660 : 300 }
    private static let maxReps = 100

    private var weightValues: [Double] {
        Array(stride(from: 0, through: Self.maxWeight(system), by: Self.step(system)))
    }

    private var unitSymbol: String {
        let f = MeasurementFormatter()
        f.unitStyle = .short
        return f.string(from: system == .imperial ? UnitMass.pounds : UnitMass.kilograms)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Picker("Weight", selection: $weight) {
                            ForEach(weightValues, id: \.self) { Text(LiftFormat.trim($0)).tag($0) }
                        }
                        .wheel()
                        Text(unitSymbol).foregroundStyle(StrandPalette.textSecondary)
                        Picker("Reps", selection: $reps) {
                            ForEach(0...Self.maxReps, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .wheel()
                        Text("reps").foregroundStyle(StrandPalette.textSecondary)
                    }
                    .labelsHidden()
                } header: {
                    Text(exercise).textCase(nil)
                } footer: {
                    if let lastTime { Text("Last time: \(lastTime)") }
                }

                Section {
                    Picker("RPE", selection: $rpe) {
                        Text(verbatim: "—").tag(Double?.none)
                        ForEach(Array(stride(from: 5.0, through: 10.0, by: 0.5)), id: \.self) {
                            Text(LiftFormat.trim($0)).tag(Double?.some($0))
                        }
                    }
                    Toggle("Warm-up", isOn: $warmup)
                        .tint(StrandPalette.activityExerciseText)
                }

                if canStart {
                    Section {
                        Button(isDone ? "Redo Set" : "Start Set") {
                            save()
                            onStart()
                            dismiss()
                        }
                        .foregroundStyle(StrandPalette.activityExerciseText)
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton {
                        save()
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 420, minHeight: 460)
        #endif
        .preferredColorScheme(.dark)
    }

    private func save() {
        let kg = weight > 0 ? LiftFormat.kilograms(fromDisplay: weight, system: system) : nil
        onSave(kg, reps > 0 ? reps : nil, rpe, warmup)
    }
}

private extension Picker {
    /// The Clock-style wheel on iPhone; macOS has no wheel and keeps its default picker.
    @ViewBuilder
    func wheel() -> some View {
        #if os(iOS)
        self.pickerStyle(.wheel)
        #else
        self
        #endif
    }
}
