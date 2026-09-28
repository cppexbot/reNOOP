import SwiftUI
import Foundation
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

// MARK: - Marker editor (manual entry)
//
// The Lab Book's "Add Reading" sheet, a native form with ✕ and ✓ as Health's own entry sheets: the marker
// (picked from MarkerCatalog on a searchable page, or a custom name + unit), the value (the marker's
// canonical unit, with a unit switcher where sensible, e.g. mmol/L↔mg/dL, converted on save), the date,
// an optional note and an OPTIONAL range typed from the user's own report — NEVER a NOOP-shipped range.
// Blood pressure is a PAIRED marker (systolic + diastolic entered together, stored as two keys).
//
// On save it hands the caller `[LabMarkerRow]` drafts (one row, or two for BP) under the strap device id;
// the caller persists + refreshes. NON-CLINICAL: this only captures what the user types.

struct MarkerEditorView: View {
    /// Persist the validated draft row(s). Async so the caller can write + refresh.
    let onSave: (_ drafts: [LabMarkerRow]) async -> Void

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss

    // Marker selection.
    @State private var selection: MarkerDefinition?
    @State private var customName = ""
    @State private var customUnit = ""
    @State private var addingCustom = false

    // Reading inputs.
    @State private var valueText = ""
    @State private var diastolicText = ""   // only used for the paired BP marker
    @State private var unit = ""
    @State private var unitChoice = 0       // index into the active unit options (the switcher)
    @State private var takenAt = Date()
    @State private var note = ""
    @State private var referenceText = ""

    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        MarkerPickerPage(onPick: choose, onCustom: {
                            selection = nil
                            addingCustom = true
                        })
                    } label: {
                        LabeledContent("Lab Test") {
                            Text(verbatim: selection.map(LabBookFormat.name)
                                 ?? (addingCustom ? String(localized: "Custom") : ""))
                        }
                    }
                    if addingCustom {
                        TextField("Name", text: $customName)
                        TextField("Unit", text: $customUnit)
                    }
                }
                if selection != nil || addingCustom {
                    readingSection
                }
            }
            .settingsForm()
            .navigationTitle(Text("Add Reading"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(tint: StrandPalette.settingsBlue) { save() }
                        .disabled(drafts.isEmpty || saving)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    // MARK: - Reading inputs

    private var readingSection: some View {
        Section {
            if isBloodPressure {
                numberRow("Systolic", text: $valueText, unit: "mmHg")
                numberRow("Diastolic", text: $diastolicText, unit: "mmHg")
            } else {
                numberRow("Value", text: $valueText, unit: activeUnit)
                if unitOptions.count > 1 {
                    // The transparent unit switcher (e.g. mmol/L ↔ mg/dL); stored in the canonical unit.
                    Picker("Unit", selection: $unitChoice) {
                        ForEach(unitOptions.indices, id: \.self) { Text(verbatim: unitOptions[$0]).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            DatePicker("Date", selection: $takenAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            TextField("Note", text: $note)
            TextField("Range on Report", text: $referenceText)
        } footer: {
            if !conversionNote.isEmpty {
                Text(verbatim: conversionNote)
            }
        }
    }

    private func numberRow(_ title: LocalizedStringKey, text: Binding<String>, unit: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, text: text)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .numericKeyboard()
                Text(verbatim: unit)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    // MARK: - Selection + units

    private func choose(_ def: MarkerDefinition) {
        selection = def
        addingCustom = false
        unit = def.canonicalUnit
        unitChoice = 0
        valueText = ""
        diastolicText = ""
    }

    /// The active marker key (catalog key, or a slug of the custom name).
    private var markerKey: String {
        if let selection { return selection.key }
        return MarkerUnits.slug(customName)
    }

    private var category: LabMarkerCategory {
        if let selection { return selection.category }
        return .other
    }

    private var isBloodPressure: Bool { markerKey == LabBookProjection.bpSystolicKey }

    /// The unit options for the active marker — a switcher list only for markers that have a
    /// well-known dual unit (lipids/glucose: mmol/L↔mg/dL). Everything else has one canonical unit.
    private var unitOptions: [String] {
        if addingCustom { return [customUnit] }
        return MarkerUnits.options(for: markerKey, canonical: unit)
    }

    private var activeUnit: String {
        guard unitOptions.indices.contains(unitChoice) else { return unit }
        return unitOptions[unitChoice]
    }

    /// "Stored in mmol/L (× 0.02586)." when the switcher is off the canonical unit.
    private var conversionNote: String {
        let canonical = MarkerUnits.canonicalUnit(for: markerKey, fallback: unit)
        guard unitOptions.count > 1, activeUnit != canonical,
              let factor = MarkerUnits.factorToCanonical(markerKey: markerKey, from: activeUnit) else {
            return ""
        }
        return String(localized: "Stored in \(canonical) (× \(MarkerUnits.factorLabel(factor))).")
    }

    // MARK: - Build the draft rows

    /// The validated draft row(s): two for BP, one otherwise. Empty when inputs aren't usable yet.
    private var drafts: [LabMarkerRow] {
        // Custom marker needs a name + unit.
        if addingCustom {
            guard !customName.trimmingCharacters(in: .whitespaces).isEmpty,
                  !customUnit.trimmingCharacters(in: .whitespaces).isEmpty,
                  let v = parsed(valueText) else { return [] }
            return [row(key: markerKey, category: .other, value: v, unit: customUnit)]
        }
        guard selection != nil else { return [] }
        if isBloodPressure {
            guard let sys = parsed(valueText), let dia = parsed(diastolicText) else { return [] }
            return [
                row(key: LabBookProjection.bpSystolicKey, category: .bloodPressure, value: sys, unit: "mmHg"),
                row(key: LabBookProjection.bpDiastolicKey, category: .bloodPressure, value: dia, unit: "mmHg"),
            ]
        }
        guard let raw = parsed(valueText) else { return [] }
        // Convert the entered value to the canonical stored unit if a switcher is in use.
        let canonical = MarkerUnits.canonicalUnit(for: markerKey, fallback: unit)
        let stored = MarkerUnits.toCanonical(markerKey: markerKey, value: raw, from: activeUnit)
        return [row(key: markerKey, category: category, value: stored, unit: canonical)]
    }

    private func row(key: String, category: LabMarkerCategory, value: Double, unit: String) -> LabMarkerRow {
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let trimmedRef = referenceText.trimmingCharacters(in: .whitespaces)
        let epoch = Int(takenAt.timeIntervalSince1970)
        return LabMarkerRow(
            id: "\(key)-\(epoch)-\(UUID().uuidString.prefix(8))",
            deviceId: repo.deviceId,
            markerKey: key,
            category: category.rawValue,
            day: LabBookFormat.dayKey(takenAt),
            takenAt: epoch,
            value: value,
            valueText: nil,
            unit: unit,
            source: "manual",
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            referenceText: trimmedRef.isEmpty ? nil : trimmedRef
        )
    }

    private func parsed(_ s: String) -> Double? {
        // A decimal pad in a comma locale types "3,1".
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        let rows = drafts
        guard !rows.isEmpty else { return }
        saving = true
        Task {
            await onSave(rows)
            dismiss()
        }
    }
}

/// The marker catalog as a searchable list, and a custom marker at the foot.
private struct MarkerPickerPage: View {
    let onPick: (MarkerDefinition) -> Void
    let onCustom: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [MarkerDefinition] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return MarkerCatalog.builtIn }
        return MarkerCatalog.builtIn.filter {
            LabBookFormat.name($0).lowercased().contains(q) || $0.displayName.lowercased().contains(q) || $0.key.contains(q)
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(filtered, id: \.key) { def in
                    Button {
                        onPick(def)
                        dismiss()
                    } label: {
                        LabeledContent {
                            Text(verbatim: def.canonicalUnit)
                        } label: {
                            Text(verbatim: LabBookFormat.name(def)).foregroundStyle(StrandPalette.textPrimary)
                        }
                    }
                }
            }
            Section {
                Button("Custom Marker") {
                    onCustom()
                    dismiss()
                }
            }
        }
        .settingsPage("Lab Test")
        .searchable(text: $search)
    }
}

// MARK: - Unit handling (transparent mmol/L ↔ mg/dL switcher for lipids/glucose)
//
// Only the markers with a well-known dual unit get a switcher; everything else keeps its
// single canonical unit. Conversions are exact and reversible. The stored value is always
// the canonical unit, so the daily projection + correlation stay consistent regardless of
// what the user typed in.

enum MarkerUnits {
    /// Markers whose mg/dL → mmol/L factor we know (molar-mass derived, standard clinical factors).
    /// Lipids share 38.67; glucose uses 18.0.
    private static let mgdlToMmol: [String: Double] = [
        "total_cholesterol": 1.0 / 38.67,
        "ldl":               1.0 / 38.67,
        "hdl":               1.0 / 38.67,
        "triglycerides":     1.0 / 88.57,   // triglyceride molar conversion
        "fasting_glucose":   1.0 / 18.0,
    ]

    /// The canonical (stored) unit for a marker — the catalog's, or a fallback.
    static func canonicalUnit(for key: String, fallback: String) -> String {
        MarkerCatalog.definition(for: key)?.canonicalUnit ?? fallback
    }

    /// The unit options shown in the switcher. Two entries (canonical + mg/dL) for the dual-unit
    /// markers; otherwise just the single canonical unit.
    static func options(for key: String, canonical: String) -> [String] {
        if mgdlToMmol[key] != nil { return [canonicalUnit(for: key, fallback: canonical), "mg/dL"] }
        return [canonical]
    }

    /// Multiplicative factor turning a value in `from` into the canonical unit, or nil if no conversion.
    static func factorToCanonical(markerKey: String, from unit: String) -> Double? {
        guard unit == "mg/dL", let f = mgdlToMmol[markerKey] else { return nil }
        return f
    }

    /// Convert a typed value (in `from`) to the canonical stored unit. Identity when no conversion applies.
    static func toCanonical(markerKey: String, value: Double, from unit: String) -> Double {
        guard let f = factorToCanonical(markerKey: markerKey, from: unit) else { return value }
        return value * f
    }

    /// A short label for the conversion factor (4 sig figs), e.g. "0.02586".
    static func factorLabel(_ f: Double) -> String { String(format: "%.5g", f) }

    /// A lower-cased, underscored slug for a custom marker name → its stable key. Delegates to the CSV
    /// importer's `customKey` so a hand-added custom marker and an imported one always share one key.
    static func slug(_ name: String) -> String {
        let key = LabMarkerCsvImport.customKey(name)
        return key.isEmpty ? "custom_" : key
    }
}
