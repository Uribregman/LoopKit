//
//  TherapyProfilesSection.swift
//  LoopKitUI
//
//  Profiles, shown as the first card of the Therapy Settings screen.
//  Based on Loop and Learn's Profiles customization (Jonas Björkert); restyled
//  to this fork's design language (docs/DESIGN_SYSTEM.md): capsule pills,
//  controls that expand on press, native alerts, haptics.
//

import SwiftUI
import LoopKit

struct TherapyProfilesSection: View {
    @StateObject private var viewModel: ProfileViewModel
    let therapySettingsViewModel: TherapySettingsViewModel

    @State private var isNamingNewProfile = false
    @State private var newProfileName = ""
    @State private var nameToConfirmReplacing: String?
    @State private var renaming: ProfileReference?
    @State private var renameText = ""
    @State private var deleting: ProfileReference?
    @State private var errorMessage: String?
    @State private var savedCount = 0

    init(therapySettingsViewModel: TherapySettingsViewModel) {
        self.therapySettingsViewModel = therapySettingsViewModel
        _viewModel = StateObject(wrappedValue: ProfileViewModel(therapySettingsViewModel: therapySettingsViewModel))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !viewModel.profiles.isEmpty {
                ProfilesDivider()
                VStack(spacing: 0) {
                    ForEach(viewModel.profiles, id: \.fileName) { reference in
                        if reference != viewModel.profiles.first {
                            Divider().padding(.leading, 40)
                        }
                        row(for: reference)
                    }
                }
            }

            if let active = viewModel.currentProfileName, viewModel.isActiveProfileEdited {
                editedNotice(for: active)
            }

            saveButton
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: viewModel.profiles)
        .profileSuccessHaptic(trigger: savedCount)
        .onAppear { viewModel.attach(therapySettingsViewModel) }
        .onChange(of: ObjectIdentifier(therapySettingsViewModel)) { _ in viewModel.attach(therapySettingsViewModel) }
        .alert(LocalizedString("New Profile", comment: "Title of the alert that names a new profile"),
               isPresented: $isNamingNewProfile) {
            TextField(LocalizedString("Name", comment: "Placeholder for a profile name"), text: $newProfileName)
            Button(LocalizedString("Cancel", comment: "Cancel button title"), role: .cancel) {}
            Button(LocalizedString("Save", comment: "Save button title")) { requestSave(named: newProfileName) }
                .disabled(viewModel.sanitizeProfileName(newProfileName).isEmpty)
        } message: {
            Text(LocalizedString("Saves all of your current therapy settings below under this name.", comment: "Message of the alert that names a new profile"))
        }
        .alert(replaceTitle, isPresented: profileAlertBinding($nameToConfirmReplacing)) {
            Button(LocalizedString("Cancel", comment: "Cancel button title"), role: .cancel) {}
            Button(LocalizedString("Replace", comment: "Button that overwrites an existing profile"), role: .destructive) {
                if let name = nameToConfirmReplacing { save(named: name) }
            }
        } message: {
            Text(LocalizedString("A profile with this name already exists. Replace it with your current settings?", comment: "Message when saving over an existing profile"))
        }
        .alert(LocalizedString("Rename Profile", comment: "Title of the rename profile alert"),
               isPresented: profileAlertBinding($renaming)) {
            TextField(LocalizedString("Name", comment: "Placeholder for a profile name"), text: $renameText)
            Button(LocalizedString("Cancel", comment: "Cancel button title"), role: .cancel) {}
            Button(LocalizedString("Rename", comment: "Rename button title")) {
                if let reference = renaming { viewModel.renameProfile(oldName: reference.name, newName: renameText) }
            }
            .disabled(viewModel.sanitizeProfileName(renameText).isEmpty)
        }
        .alert(deleteTitle, isPresented: profileAlertBinding($deleting)) {
            Button(LocalizedString("Cancel", comment: "Cancel button title"), role: .cancel) {}
            Button(LocalizedString("Delete", comment: "Delete button title"), role: .destructive) {
                if let reference = deleting, let profile = viewModel.profile(for: reference) {
                    viewModel.removeProfile(profile: profile)
                }
            }
        } message: {
            Text(LocalizedString("Your current therapy settings don't change.", comment: "Message when deleting a profile"))
        }
        .alert(LocalizedString("Couldn't Save Profile", comment: "Title when saving a profile fails"),
               isPresented: profileAlertBinding($errorMessage)) {
            Button(LocalizedString("OK", comment: "OK button title"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedString("Profiles", comment: "Title of the profiles card in Therapy Settings"))
                .bold()
            DescriptiveText(label: LocalizedString("Save all of the therapy settings below under a name, and switch between them for different routines.", comment: "Description of profiles in Therapy Settings"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(for reference: ProfileReference) -> some View {
        let isActive = reference.name == viewModel.currentProfileName
        let isEdited = isActive && viewModel.isActiveProfileEdited
        return NavigationLink(destination: ProfilePreviewView(viewModel: viewModel, fileName: reference.fileName)) {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isActive ? .accentColor : Color(.tertiaryLabel))
                    .accessibilityHidden(true)
                Text(reference.name)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if isActive {
                    ProfileStatusPill(isEdited: isEdited)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .opacity(0.5)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProfilePressStyle())
        .accessibilityLabel(isActive ? String(format: LocalizedString("%@, active profile", comment: "Accessibility label of the active profile row (1: name)"), reference.name) : reference.name)
        .contextMenu {
            if reference != viewModel.profiles.first {
                Button { viewModel.moveProfile(reference, by: -1) } label: {
                    Label(LocalizedString("Move Up", comment: "Move a profile up the list"), systemImage: "arrow.up")
                }
            }
            if reference != viewModel.profiles.last {
                Button { viewModel.moveProfile(reference, by: 1) } label: {
                    Label(LocalizedString("Move Down", comment: "Move a profile down the list"), systemImage: "arrow.down")
                }
            }
            Button {
                renameText = reference.name
                renaming = reference
            } label: {
                Label(LocalizedString("Rename", comment: "Rename button title"), systemImage: "pencil")
            }
            Button(role: .destructive) { deleting = reference } label: {
                Label(LocalizedString("Delete", comment: "Delete button title"), systemImage: "trash")
            }
        }
    }

    private func editedNotice(for name: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: LocalizedString("These settings no longer match “%@”.", comment: "Notice when therapy settings were edited after loading a profile (1: name)"), name))
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    save(named: name)
                } label: {
                    Text(String(format: LocalizedString("Update “%@”", comment: "Button that saves the current settings into the active profile (1: name)"), name))
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(ProfilePressStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.12)))
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }

    private var saveButton: some View {
        Button {
            newProfileName = ""
            isNamingNewProfile = true
        } label: {
            Label(LocalizedString("Save as New Profile", comment: "Button that saves the current therapy settings as a profile"), systemImage: "plus")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .profileAccentCapsule()
        }
        .buttonStyle(ProfilePressStyle(scale: 1.03))
        .padding(.top, 4)
    }

    // MARK: Actions

    private func requestSave(named name: String) {
        if viewModel.doesProfileExist(withName: name) {
            // Let the naming alert finish closing before the next one opens.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                nameToConfirmReplacing = viewModel.sanitizeProfileName(name)
            }
        } else {
            save(named: name)
        }
    }

    private func save(named name: String) {
        if let error = viewModel.saveProfile(withName: name) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                errorMessage = error.localizedDescription
            }
        } else {
            savedCount += 1
        }
    }

    private var replaceTitle: String {
        String(format: LocalizedString("Replace “%@”?", comment: "Title when saving over an existing profile (1: name)"), nameToConfirmReplacing ?? "")
    }

    private var deleteTitle: String {
        String(format: LocalizedString("Delete “%@”?", comment: "Title when deleting a profile (1: name)"), deleting?.name ?? "")
    }
}

// MARK: - Shared profile styling

/// "Active" (accent) or "Edited" (orange) capsule next to the active profile.
struct ProfileStatusPill: View {
    let isEdited: Bool

    var body: some View {
        let color: Color = isEdited ? .orange : .accentColor
        Text(isEdited
             ? LocalizedString("Edited", comment: "Pill on the active profile when settings changed since it was loaded")
             : LocalizedString("Active", comment: "Pill on the active profile"))
            .font(.caption.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// The app-wide press feedback: controls expand on press and never dim
/// (same spring as `loopPressAnimation`; LoopKitUI can't import the app's GlassStyles).
struct ProfilePressStyle: ButtonStyle {
    var scale: CGFloat = 1.05

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

private struct ProfilesDivider: View {
    var body: some View {
        Divider().padding(.trailing, -16)
    }
}

extension View {
    /// Accent-tinted capsule: Liquid Glass on iOS 26, a filled capsule before that.
    @ViewBuilder
    func profileAccentCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(.accentColor).interactive(), in: Capsule())
        } else {
            self.background(Capsule().fill(Color.accentColor))
        }
    }

    /// `.success` haptic whenever `trigger` changes (iOS 17+).
    @ViewBuilder
    func profileSuccessHaptic<T: Equatable>(trigger: T) -> some View {
        if #available(iOS 17.0, *) {
            self.sensoryFeedback(.success, trigger: trigger)
        } else {
            self
        }
    }
}

/// A Bool binding that is true while `value` is non-nil, and clears it when set to false.
func profileAlertBinding<T>(_ value: Binding<T?>) -> Binding<Bool> {
    Binding(get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } })
}
