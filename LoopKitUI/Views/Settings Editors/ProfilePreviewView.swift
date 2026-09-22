//
//  ProfilePreviewView.swift
//  LoopKitUI
//
//  Created by Jonas Björkert on 2023-05-23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//
//  Restyled for this fork: a saved profile shown with the same cards and editors
//  as Therapy Settings. Editing here changes ONLY the profile file — nothing is
//  sent to the pump and Loop's live settings are untouched until "Load Profile".
//

import Foundation
import SwiftUI
import HealthKit
import LoopKit

/// Routes the Therapy Settings editors to a profile file instead of the pump and Loop.
final class ProfileEditingDelegate: TherapySettingsViewModelDelegate {
    private weak var profiles: ProfileViewModel?
    private let fileName: String
    /// Called after an edit is written to the profile.
    var didSave: (() -> Void)?

    init(profiles: ProfileViewModel, fileName: String) {
        self.profiles = profiles
        self.fileName = fileName
    }

    func syncBasalRateSchedule(items: [RepeatingScheduleValue<Double>], completion: @escaping (Result<BasalRateSchedule, Error>) -> Void) {
        // Not sent to the pump: that happens when the profile is loaded.
        let timeZone = profiles?.therapySettings.basalRateSchedule?.timeZone ?? .currentFixed
        guard let schedule = BasalRateSchedule(dailyItems: items, timeZone: timeZone) else {
            completion(.failure(ProfileValidationError.basalRateError))
            return
        }
        completion(.success(schedule))
    }

    func syncDeliveryLimits(deliveryLimits: DeliveryLimits, completion: @escaping (Result<DeliveryLimits, Error>) -> Void) {
        // Not sent to the pump: that happens when the profile is loaded.
        completion(.success(deliveryLimits))
    }

    func saveCompletion(therapySettings: TherapySettings) {
        DispatchQueue.main.async {
            if self.profiles?.updateProfile(fileName: self.fileName, with: therapySettings) == true {
                self.didSave?()
            }
        }
    }

    func pumpSupportedIncrements() -> PumpSupportedIncrements? {
        profiles?.pumpSupportedIncrements()
    }
}

/// Owns the editor's view model and its delegate (the view model only holds the delegate weakly).
final class ProfileEditorModel: ObservableObject {
    let delegate: ProfileEditingDelegate
    let therapySettingsViewModel: TherapySettingsViewModel

    init(profiles: ProfileViewModel, fileName: String) {
        delegate = ProfileEditingDelegate(profiles: profiles, fileName: fileName)
        let settings = profiles.cachedProfiles[fileName].flatMap { profiles.therapySettings(applying: $0) }
            ?? profiles.therapySettings
        therapySettingsViewModel = TherapySettingsViewModel(therapySettings: settings, delegate: delegate)
    }
}

struct ProfilePreviewView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @StateObject private var editor: ProfileEditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.authenticate) private var authenticate

    /// Identifies the profile; unlike the name it survives a rename.
    let fileName: String

    @State private var isConfirmingLoad = false
    @State private var isLoading = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isConfirmingDelete = false
    @State private var isOfferingToApplyEdit = false
    @State private var errorMessage: String?
    @State private var loadedCount = 0
    @State private var editedCount = 0

    init(viewModel: ProfileViewModel, fileName: String) {
        self.viewModel = viewModel
        self.fileName = fileName
        _editor = StateObject(wrappedValue: ProfileEditorModel(profiles: viewModel, fileName: fileName))
    }

    private var profile: Profile? { viewModel.cachedProfiles[fileName] }

    private var isActive: Bool { profile?.name == viewModel.currentProfileName }

    private var isActiveAndUnchanged: Bool { isActive && !viewModel.isActiveProfileEdited }

    var body: some View {
        Group {
            if let profile {
                TherapySettingsView(profileTitle: profile.name,
                                    viewModel: editor.therapySettingsViewModel,
                                    header: AnyView(summary))
                    .safeAreaInset(edge: .bottom) { loadButton }
            } else {
                // Deleted from under us: go back to Therapy Settings.
                Color(.systemGroupedBackground).onAppear { dismiss() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editor.delegate.didSave = {
                editedCount += 1
                if isActive {
                    // Let the editor finish closing before asking.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        isOfferingToApplyEdit = true
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        renameText = profile?.name ?? ""
                        isRenaming = true
                    } label: {
                        Label(LocalizedString("Rename", comment: "Rename button title"), systemImage: "pencil")
                    }
                    Button(role: .destructive) { isConfirmingDelete = true } label: {
                        Label(LocalizedString("Delete", comment: "Delete button title"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel(LocalizedString("More", comment: "Accessibility label of the profile actions menu"))
                }
            }
        }
        .profileSuccessHaptic(trigger: loadedCount)
        .profileSuccessHaptic(trigger: editedCount)
        .alert(String(format: LocalizedString("Load “%@”?", comment: "Title of the load profile confirmation (1: name)"), profile?.name ?? ""),
               isPresented: $isConfirmingLoad) {
            Button(LocalizedString("Cancel", comment: "Cancel button title"), role: .cancel) {}
            Button(LocalizedString("Load", comment: "Button that loads a profile")) { loadAfterAuthenticating() }
        } message: {
            Text(LocalizedString("Loop starts using these settings right away.", comment: "Message of the load profile confirmation"))
        }
        .alert(LocalizedString("Use the New Values Now?", comment: "Title when the active profile was edited"),
               isPresented: $isOfferingToApplyEdit) {
            Button(LocalizedString("Later", comment: "Keep the edit for the next load"), role: .cancel) {}
            Button(LocalizedString("Use Now", comment: "Apply the edited active profile now")) { load() }
        } message: {
            Text(String(format: LocalizedString("“%@” is the profile Loop is using. Your change is saved to the profile; Loop keeps its current values until you use it.", comment: "Message when the active profile was edited (1: name)"), profile?.name ?? ""))
        }
        .alert(LocalizedString("Rename Profile", comment: "Title of the rename profile alert"), isPresented: $isRenaming) {
            TextField(LocalizedString("Name", comment: "Placeholder for a profile name"), text: $renameText)
            Button(LocalizedString("Cancel", comment: "Cancel button title"), role: .cancel) {}
            Button(LocalizedString("Rename", comment: "Rename button title")) {
                if let name = profile?.name { viewModel.renameProfile(oldName: name, newName: renameText) }
            }
            .disabled(viewModel.sanitizeProfileName(renameText).isEmpty)
        }
        .alert(String(format: LocalizedString("Delete “%@”?", comment: "Title when deleting a profile (1: name)"), profile?.name ?? ""),
               isPresented: $isConfirmingDelete) {
            Button(LocalizedString("Cancel", comment: "Cancel button title"), role: .cancel) {}
            Button(LocalizedString("Delete", comment: "Delete button title"), role: .destructive) {
                if let profile { viewModel.removeProfile(profile: profile) }
            }
        } message: {
            Text(LocalizedString("Your current therapy settings don't change.", comment: "Message when deleting a profile"))
        }
        .alert(LocalizedString("Couldn't Load Profile", comment: "Title when loading a profile fails"),
               isPresented: profileAlertBinding($errorMessage)) {
            Button(LocalizedString("OK", comment: "OK button title"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isActive {
                ProfileStatusPill(isEdited: !isActiveAndUnchanged)
            }
            DescriptiveText(label: summaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryText: String {
        if isActiveAndUnchanged {
            return LocalizedString("This is the profile Loop is using now. Tap a setting to change it in this profile.", comment: "Profile detail text for the active profile")
        }
        if profile?.isMissingSettings == true {
            return LocalizedString("Saved by an older version: the Glucose Safety Limit, Pre-Meal Range and Delivery Limits below are your current ones. Tap a setting to change it in this profile — nothing changes in Loop until you load it.", comment: "Profile detail text for a profile saved before profiles held every setting")
        }
        return LocalizedString("Tap a setting to change it in this profile. Nothing changes in Loop until you load it.", comment: "Profile detail text explaining editing and loading")
    }

    private var loadButton: some View {
        Button {
            isConfirmingLoad = true
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    SwiftUI.ProgressView()
                }
                Text(isActiveAndUnchanged
                     ? LocalizedString("Active Profile", comment: "Disabled load button on the active profile")
                     : LocalizedString("Load Profile", comment: "Button that loads a profile"))
            }
        }
        .buttonStyle(ActionButtonStyle(.primary))
        .disabled(isLoading || isActiveAndUnchanged)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: Loading

    /// Loading a profile changes therapy settings, so it needs Face ID / passcode like the Therapy Settings editors.
    private func loadAfterAuthenticating() {
        guard let profile else { return }
        if case .failure(let error) = viewModel.validateProfile(profile) {
            showError(error)
            return
        }
        authenticate(LocalizedString("Authenticate to load this profile's therapy settings", comment: "Authentication hint string for loading a profile")) { authResult in
            guard case .success = authResult else { return }
            load(dismissingAfterwards: true)
        }
    }

    /// Applies the profile. "Use Now" after editing comes here directly: the editor
    /// that made the change already asked for Face ID / passcode a moment ago.
    private func load(dismissingAfterwards: Bool = false) {
        guard let profile else { return }
        if case .failure(let error) = viewModel.validateProfile(profile) {
            showError(error)
            return
        }
        isLoading = true
        viewModel.loadProfile(profile: profile) { result in
            isLoading = false
            switch result {
            case .success:
                loadedCount += 1
                if dismissingAfterwards { dismiss() }
            case .failure(let error):
                showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        // Wait for the confirmation alert to finish closing before presenting the next one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            errorMessage = error.localizedDescription
        }
    }
}
