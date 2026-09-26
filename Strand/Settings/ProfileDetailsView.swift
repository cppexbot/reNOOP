//  ProfileDetailsView.swift
//  NOOP · the profile, as Health's "Health Details" page draws it: a large photo, then plain rows whose
//  values sit on the right. A row opens its wheel in place, as Health's edit mode does. The same
//  `ProfileStore` fields the old Settings card wrote; stored values stay SI.
//
//  Also here: the account sheet the Summary avatar opens (Health's profile sheet), and the heart-rate
//  zones page.

import SwiftUI
import PhotosUI
import StrandDesign
import StrandAnalytics

// MARK: - Account sheet

/// Health's profile sheet: the photo and name, then the pages behind them.
struct ProfileSheet: View {
    @EnvironmentObject private var profile: ProfileStore
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        SummaryAvatar(imageData: profile.avatarImageData, initials: profile.initials, size: 90)
                        if !profile.displayName.isEmpty {
                            Text(profile.displayName)
                                .font(StrandFont.pro(28, weight: .bold))
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section {
                    NavigationLink("Health Details", value: SettingsPage.profile)
                }
                Section {
                    NavigationLink("Devices", value: SettingsPage.devices)
                    NavigationLink("Data Sources", value: SettingsPage.dataSources)
                }
                Section {
                    NavigationLink("Settings", value: SettingsPage.settings)
                }
            }
            .settingsForm()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
            .settingsDestinations()
        }
    }
}

// MARK: - Health Details

struct ProfileDetailsView: View {
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    /// Profile-photo picker selection (PhotosUI). Cleared once the bytes are loaded.
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showPhotoOptions = false
    /// The row whose wheel is open, as Health's edit mode opens one field at a time.
    @State private var open: Field?

    private enum Field { case birth, height, weight, waist, hrMax }

    private var imperial: Bool { UnitSystem(rawValue: unitSystemRaw) == .imperial }

    var body: some View {
        Form {
            Section {
                photoHeader
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Name") {
                    TextField("Name", text: $profile.displayName, prompt: Text("Not set"))
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .textContentType(.name)
                        #endif
                }
                // #146: age derives from the date of birth, so it advances on its own.
                wheelRow(.birth, "Date of birth", value: birthText) {
                    DatePicker("Date of birth", selection: $profile.dateOfBirth,
                               in: ProfileStore.dateOfBirthRange, displayedComponents: .date)
                }
                Picker("Sex", selection: $profile.sex) {
                    Text("Male").tag("male")
                    Text("Female").tag("female")
                    Text("Non-binary").tag("nonbinary")
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #endif
            }

            Section {
                wheelRow(.height, "Height", value: heightText) { heightPicker }
                wheelRow(.weight, "Weight", value: weightText) { weightPicker }
                wheelRow(.waist, "Waist", value: waistText) { waistPicker }
            }

            Section {
                wheelRow(.hrMax, "Max heart rate", value: hrMaxText) { hrMaxPicker }
                NavigationLink(value: SettingsPage.heartRateZones) {
                    LabeledContent("Heart rate zones",
                                   value: profile.hasCustomHRZones ? String(localized: "Manual")
                                                                   : String(localized: "Automatic"))
                }
            } footer: {
                Text("These power your heart-rate zones, calorie estimates and recovery baselines.")
            }
        }
        .settingsPage("Health Details")
        .photosPicker(isPresented: $showPhotoPicker, selection: $avatarPickerItem, matching: .images)
        .confirmationDialog("Photo", isPresented: $showPhotoOptions) {
            Button("Choose photo") { showPhotoPicker = true }
            Button("Remove photo", role: .destructive) { profile.clearAvatar() }
            Button("Cancel", role: .cancel) { }
        }
        // Hand the picked bytes to the store (which downscales + persists), then clear the selection so the
        // same photo can be picked again.
        .onChange(of: avatarPickerItem) { newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data { profile.setAvatar(data) }
                    avatarPickerItem = nil
                }
            }
        }
    }

    // MARK: Photo

    private var photoHeader: some View {
        Button {
            if profile.hasAvatar { showPhotoOptions = true } else { showPhotoPicker = true }
        } label: {
            VStack(spacing: 8) {
                SummaryAvatar(imageData: profile.avatarImageData, initials: profile.initials, size: 110)
                Text(profile.hasAvatar ? "Change photo" : "Add photo")
                    .font(StrandFont.pro(15))
                    .foregroundStyle(StrandPalette.accent)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(profile.hasAvatar ? "Change photo" : "Add photo")
    }

    // MARK: Rows

    /// A value row that opens its picker in place underneath (iOS wheel); macOS shows the control inline.
    @ViewBuilder
    private func wheelRow<P: View>(_ field: Field, _ title: LocalizedStringKey, value: String,
                                   @ViewBuilder picker: () -> P) -> some View {
        #if os(iOS)
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { open = open == field ? nil : field }
        } label: {
            LabeledContent {
                Text(value).foregroundStyle(open == field ? StrandPalette.accent : StrandPalette.textSecondary)
            } label: {
                Text(title).foregroundStyle(StrandPalette.textPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if open == field {
            picker()
                .labelsHidden()
                .pickerStyle(.wheel)
                .datePickerStyle(.wheel)
                .frame(maxWidth: .infinity)
        }
        #else
        LabeledContent(title) {
            picker().labelsHidden()
        }
        #endif
    }

    // MARK: Values

    private var birthText: String {
        let date = profile.dateOfBirth.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(date) (\(profile.age))"
    }

    private var heightText: String {
        if imperial {
            let parts = UnitFormatter.cmToFeetInches(profile.heightCm)
            return "\(parts.feet)′ \(parts.inches)″"
        }
        return "\(Int(profile.heightCm.rounded())) \(String(localized: "cm"))"
    }

    private var weightText: String {
        if imperial {
            return "\(Int(UnitFormatter.kgToPounds(profile.weightKg).rounded())) \(String(localized: "lb"))"
        }
        return "\(profile.weightKg.formatted(.number.precision(.fractionLength(0...1)))) \(String(localized: "kg"))"
    }

    private var waistText: String {
        guard profile.waistCm > 0 else { return String(localized: "Not set") }
        if imperial {
            return "\(Int(UnitFormatter.cmToInches(profile.waistCm).rounded())) \(String(localized: "in"))"
        }
        return "\(Int(profile.waistCm.rounded())) \(String(localized: "cm"))"
    }

    private var hrMaxText: String {
        profile.hrMaxOverride > 0
            ? "\(profile.hrMaxOverride) \(String(localized: "bpm"))"
            : String(localized: "Auto · \(profile.hrMax) bpm")
    }

    // MARK: Pickers (SI stored; imperial pickers write the cm/kg equivalent back)

    @ViewBuilder private var heightPicker: some View {
        if imperial {
            Picker("Height", selection: Binding(
                get: { Int(UnitFormatter.cmToInches(profile.heightCm).rounded()) },
                set: { profile.heightCm = Double($0) * UnitFormatter.centimetersPerInch }
            )) {
                ForEach(47...91, id: \.self) { inches in
                    Text(verbatim: "\(inches / 12)′ \(inches % 12)″").tag(inches)
                }
            }
        } else {
            Picker("Height", selection: Binding(
                get: { Int(profile.heightCm.rounded()) },
                set: { profile.heightCm = Double($0) }
            )) {
                ForEach(120...230, id: \.self) { cm in
                    Text(verbatim: "\(cm) \(String(localized: "cm"))").tag(cm)
                }
            }
        }
    }

    @ViewBuilder private var weightPicker: some View {
        if imperial {
            Picker("Weight", selection: Binding(
                get: { Int(UnitFormatter.kgToPounds(profile.weightKg).rounded()) },
                set: { profile.weightKg = Double($0) / UnitFormatter.poundsPerKilogram }
            )) {
                ForEach(66...551, id: \.self) { lb in
                    Text(verbatim: "\(lb) \(String(localized: "lb"))").tag(lb)
                }
            }
        } else {
            // Half-kilogram steps, 30…250 kg, carried as tenths so the tag is an exact Int.
            Picker("Weight", selection: Binding(
                get: { Int((profile.weightKg * 2).rounded()) * 5 },
                set: { profile.weightKg = Double($0) / 10 }
            )) {
                ForEach(Array(stride(from: 300, through: 2500, by: 5)), id: \.self) { tenths in
                    Text(verbatim: "\((Double(tenths) / 10).formatted(.number.precision(.fractionLength(0...1)))) \(String(localized: "kg"))")
                        .tag(tenths)
                }
            }
        }
    }

    /// 0 = not set (optional); VO₂max works without it, a waist makes it more accurate.
    @ViewBuilder private var waistPicker: some View {
        if imperial {
            Picker("Waist", selection: Binding(
                get: { profile.waistCm > 0 ? Int(UnitFormatter.cmToInches(profile.waistCm).rounded()) : 0 },
                set: { profile.waistCm = $0 == 0 ? 0 : Double($0) * UnitFormatter.centimetersPerInch }
            )) {
                Text("Not set").tag(0)
                ForEach(24...63, id: \.self) { inches in
                    Text(verbatim: "\(inches) \(String(localized: "in"))").tag(inches)
                }
            }
        } else {
            Picker("Waist", selection: Binding(
                get: { profile.waistCm > 0 ? Int(profile.waistCm.rounded()) : 0 },
                set: { profile.waistCm = Double($0) }
            )) {
                Text("Not set").tag(0)
                ForEach(60...160, id: \.self) { cm in
                    Text(verbatim: "\(cm) \(String(localized: "cm"))").tag(cm)
                }
            }
        }
    }

    /// 0 = automatic (Tanaka from age).
    private var hrMaxPicker: some View {
        Picker("Max heart rate", selection: $profile.hrMaxOverride) {
            Text("Auto · \(profile.hrMax) bpm").tag(0)
            ForEach(100...230, id: \.self) { bpm in
                Text(verbatim: "\(bpm) \(String(localized: "bpm"))").tag(bpm)
            }
        }
    }
}

// MARK: - Heart rate zones

/// Automatic zones from max heart rate, or five personalised lower bounds (#531).
struct HeartRateZonesPage: View {
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        Form {
            Section {
                Picker("Heart rate zones", selection: Binding(
                    get: { profile.hasCustomHRZones },
                    set: { profile.setCustomHRZonesEnabled($0) }
                )) {
                    Text("Automatic").tag(false)
                    Text("Manual").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                ForEach(profile.hrZoneSet.zones, id: \.number) { zone in
                    zoneRow(zone)
                }
            } footer: {
                Text("Max heart rate: \(profile.hrMax) bpm")
            }
        }
        .settingsPage("Heart rate zones")
    }

    @ViewBuilder private func zoneRow(_ zone: HRZone) -> some View {
        let index = zone.number - 1
        HStack(spacing: 12) {
            Circle()
                .fill(StrandPalette.fitnessZone(zone.number))
                .frame(width: 10, height: 10)
            Text("Zone \(zone.number)")
            Spacer(minLength: 8)
            Text(verbatim: rangeText(zone))
                .monospacedDigit()
                .foregroundStyle(StrandPalette.textSecondary)
            if profile.hasCustomHRZones, profile.hrZoneThresholds.indices.contains(index) {
                Stepper("",
                        onIncrement: { profile.stepHRZoneThreshold(at: index, up: true) },
                        onDecrement: { profile.stepHRZoneThreshold(at: index, up: false) })
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Zone \(zone.number) starts at \(Int(zone.lower)) beats per minute")
            }
        }
    }

    /// "134–144 bpm", or "165+ bpm" for the top zone.
    private func rangeText(_ zone: HRZone) -> String {
        let bpm = String(localized: "bpm")
        let lower = Int(zone.lower.rounded())
        if zone.number == 5 { return "\(lower)+ \(bpm)" }
        return "\(lower)–\(Int(zone.upper.rounded()) - 1) \(bpm)"
    }
}
