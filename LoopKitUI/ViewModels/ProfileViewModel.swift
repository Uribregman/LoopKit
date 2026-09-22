//
//  ProfileViewModel.swift
//  LoopKitUI
//
//  Created by Jonas Björkert on 2023-04-22.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine
import LoopKit
import HealthKit
import SwiftUI

/// Saved therapy-setting profiles, shown inside the Therapy Settings screen.
///
/// It reads and writes therapy settings THROUGH that screen's `TherapySettingsViewModel`,
/// so the cards on the screen and the profiles can never disagree: editing a schedule
/// updates "is the active profile edited?", and loading a profile updates the cards.
public class ProfileViewModel: ObservableObject {

    @Published public private(set) var therapySettings: TherapySettings
    @Published public var profiles = [ProfileReference]()
    @Published public var currentProfileName: String? {
        didSet {
            UserDefaults.standard.setValue(currentProfileName, forKey: "currentProfileName")
        }
    }

    /// Decoded profiles keyed by file name, so rows don't read the disk on every redraw.
    var cachedProfiles = [String: Profile]()

    /// Strong on purpose: the Settings screen creates a new `TherapySettingsViewModel` whenever it
    /// redraws, so nothing else keeps the one this was built with alive. `attach(_:)` swaps in the new one.
    private var therapySettingsViewModel: TherapySettingsViewModel?
    private var therapySettingsObserver: AnyCancellable?

    var delegate: TherapySettingsViewModelDelegate? {
        therapySettingsViewModel?.delegate
    }

    public init(therapySettingsViewModel: TherapySettingsViewModel) {
        self.therapySettings = therapySettingsViewModel.therapySettings
        self.currentProfileName = UserDefaults.standard.string(forKey: "currentProfileName")
        self.loadProfiles()
        attach(therapySettingsViewModel)
    }

    /// Follow `therapySettingsViewModel` (the one the Therapy Settings screen is showing now).
    public func attach(_ therapySettingsViewModel: TherapySettingsViewModel) {
        guard therapySettingsViewModel !== self.therapySettingsViewModel else { return }
        self.therapySettingsViewModel = therapySettingsViewModel
        if therapySettings != therapySettingsViewModel.therapySettings {
            therapySettings = therapySettingsViewModel.therapySettings
        }
        therapySettingsObserver = therapySettingsViewModel.$therapySettings
            .dropFirst()
            .sink { [weak self] in self?.therapySettings = $0 }
    }

    public func pumpSupportedIncrements() -> PumpSupportedIncrements? {
        return delegate?.pumpSupportedIncrements()
    }
}

public struct Profile: Codable {
    var name: String
    let correctionRange: GlucoseRangeSchedule
    let carbRatioSchedule: CarbRatioSchedule
    let basalRateSchedule: BasalRateSchedule
    let insulinSensitivitySchedule: InsulinSensitivitySchedule
    var sortOrder: Int?

    // The rest of Therapy Settings. Optional so profiles saved before they were
    // added still load; a missing value means "keep the current setting".
    var suspendThreshold: GlucoseThreshold? = nil
    var correctionRangeOverrides: CorrectionRangeOverrides? = nil
    var maximumBasalRatePerHour: Double? = nil
    var maximumBolus: Double? = nil

    /// True when the profile was saved before it held every therapy setting.
    var isMissingSettings: Bool {
        suspendThreshold == nil || maximumBasalRatePerHour == nil || maximumBolus == nil
    }
}

public struct ProfileReference: Codable, Equatable {
    var name: String
    var fileName: String
    var sortOrder: Int?
}


// MARK: Saving
extension ProfileViewModel {

    /// Applies all four schedules of a profile as ONE therapy-settings change, so Loop never
    /// runs (or uploads) with a half-loaded mix of the old and the new profile.
    func saveTherapySettings(_ settings: TherapySettings) {
        // Updating the screen's view model redraws its cards and, through the observer, this one.
        therapySettingsViewModel?.therapySettings = settings
        therapySettings = settings
        delegate?.saveCompletion(therapySettings: settings)
    }

    /// The current therapy settings with `profile` applied on top.
    func therapySettings(applying profile: Profile) -> TherapySettings? {
        let unit = therapySettings.glucoseTargetRangeSchedule?.unit ?? .milligramsPerDeciliter
        guard let correctionRange = profile.correctionRange.schedule(for: unit),
              let insulinSensitivitySchedule = profile.insulinSensitivitySchedule.schedule(for: unit) else {
            return nil
        }
        var settings = therapySettingsViewModel?.therapySettings ?? therapySettings
        settings.glucoseTargetRangeSchedule = correctionRange
        settings.carbRatioSchedule = profile.carbRatioSchedule
        settings.basalRateSchedule = profile.basalRateSchedule
        settings.insulinSensitivitySchedule = insulinSensitivitySchedule
        if let suspendThreshold = profile.suspendThreshold {
            settings.suspendThreshold = suspendThreshold
        }
        if let overrides = profile.correctionRangeOverrides {
            settings.correctionRangeOverrides = overrides
        }
        if let maximumBasalRatePerHour = profile.maximumBasalRatePerHour {
            settings.maximumBasalRatePerHour = maximumBasalRatePerHour
        }
        if let maximumBolus = profile.maximumBolus {
            settings.maximumBolus = maximumBolus
        }
        return settings
    }

    public func triggerProfileSync() {
        delegate?.updateCurrentProfileName()
    }
}
