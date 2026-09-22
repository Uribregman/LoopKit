//
//  ProfileViewModel+FileManagement.swift
//  LoopKitUI
//
//  Created by Jonas Björkert on 2023-05-19.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit
import os.log

private let profileLog = OSLog(subsystem: "com.loopkit.Loop", category: "Profiles")

public enum ProfileValidationError: Error, LocalizedError {
    case fileLoadError
    case unsupportedIncrement
    case correctionRangeError
    case insulinSensitivityError
    case carbRatioError
    case basalRateError
    case maxBasalRateNotSet
    case missingTherapySettings
    case emptyName
    case suspendThresholdError
    case correctionRangeOverrideError
    case maximumBasalRateError
    case maximumBolusError

    public var errorDescription: String? {
        switch self {
        case .fileLoadError:
            return "Unable to load the profile file."
        case .unsupportedIncrement:
            return "The profile contains unsupported increments."
        case .correctionRangeError:
            return "Correction Range values are out of bounds."
        case .insulinSensitivityError:
            return "Insulin Sensitivity values are out of bounds."
        case .carbRatioError:
            return "Carb Ratio values are out of bounds."
        case .basalRateError:
            return "Basal Rate values are out of bounds."
        case .maxBasalRateNotSet:
            return "Maximum Basal Rate is not set."
        case .missingTherapySettings:
            return "Correction Range, Carb Ratios, Basal Rates and Insulin Sensitivities must all be set before saving a profile."
        case .emptyName:
            return "Enter a name for the profile."
        case .suspendThresholdError:
            return "The Glucose Safety Limit is out of bounds."
        case .correctionRangeOverrideError:
            return "The Pre-Meal or Workout range is out of bounds for this profile's correction range and safety limit."
        case .maximumBasalRateError:
            return "This profile's Maximum Basal Rate isn't supported by your pump or is below its own basal rates."
        case .maximumBolusError:
            return "This profile's Maximum Bolus isn't supported by your pump."
        }
    }
}

public enum LoadProfileResult {
    case success
    case failure(Error)
}

// MARK: File management
extension ProfileViewModel {
    private func setCurrentProfile(name: String, syncChange: Bool = false) {
        let sanitizedProfileName = sanitizeProfileName(name)
        currentProfileName = sanitizedProfileName
        if syncChange {
            triggerProfileSync()
        }
    }

    private func clearCurrentProfile() {
        currentProfileName = nil
        triggerProfileSync()
    }

    private var profilesDirectory: URL {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent("LoopProfile")
    }

    private func createProfileDirectoryIfNotExists() throws {
        let fileManager = FileManager.default
        var isDir : ObjCBool = false
        if !fileManager.fileExists(atPath: profilesDirectory.path, isDirectory: &isDir) {
            try fileManager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true, attributes: nil)
        } else if !isDir.boolValue {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError, userInfo: nil)
        }
    }

    private func getAllProfileFiles() throws -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: profilesDirectory.path) else {
            return []   // nothing saved yet
        }
        let files = try fileManager.contentsOfDirectory(at: profilesDirectory, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "json" }
    }

    private func encodeProfile(_ profile: Profile) throws -> Data {
        return try JSONEncoder().encode(profile)
    }

    private func decodeProfile(from data: Data) throws -> Profile {
        return try JSONDecoder().decode(Profile.self, from: data)
    }

    private func write(_ profile: Profile, toFileNamed fileName: String) throws {
        let fileURL = profilesDirectory.appendingPathComponent(fileName)
        // Atomic, and protected like the rest of Loop's data until the phone is first unlocked.
        try encodeProfile(profile).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func sanitizeProfileName(_ name: String) -> String {
        // Replace problematic characters
        var sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: ".", with: "_")
        sanitized = sanitized.replacingOccurrences(of: "<", with: "_")

        // Limit the name to 32 characters
        if sanitized.count > 32 {
            sanitized = String(sanitized.prefix(32))
        }

        return sanitized
    }

    /// Saves the current therapy settings as a profile. Returns an error the view can show.
    @discardableResult
    public func saveProfile(withName name: String) -> ProfileValidationError? {
        let sanitizedName = sanitizeProfileName(name)
        guard !sanitizedName.isEmpty else {
            return .emptyName
        }

        guard let correctionRange = therapySettings.glucoseTargetRangeSchedule?.schedule(for: .milligramsPerDeciliter),
              let carbRatioSchedule = therapySettings.carbRatioSchedule,
              let basalRateSchedule = therapySettings.basalRateSchedule,
              let insulinSensitivitySchedule = therapySettings.insulinSensitivitySchedule?.schedule(for: .milligramsPerDeciliter) else {
            return .missingTherapySettings
        }

        do {
            try createProfileDirectoryIfNotExists()

            let existingProfile = getProfileReference(withName: sanitizedName)

            let overrides = therapySettings.correctionRangeOverrides
            let profile = Profile(
                name: sanitizedName,
                correctionRange: correctionRange,
                carbRatioSchedule: carbRatioSchedule,
                basalRateSchedule: basalRateSchedule,
                insulinSensitivitySchedule: insulinSensitivitySchedule,
                sortOrder: existingProfile?.sortOrder ?? -1,
                suspendThreshold: therapySettings.suspendThreshold,
                correctionRangeOverrides: (overrides?.preMeal == nil && overrides?.workout == nil) ? nil : overrides,
                maximumBasalRatePerHour: therapySettings.maximumBasalRatePerHour,
                maximumBolus: therapySettings.maximumBolus
            )

            // Updating an existing profile keeps its file (and so its place in the list).
            let fileName: String
            if let existingProfile {
                fileName = existingProfile.fileName
            } else {
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
                fileName = dateFormatter.string(from: Date()) + "-" + String(UUID().uuidString.prefix(8)) + ".json"
            }

            try write(profile, toFileNamed: fileName)
            setCurrentProfile(name: sanitizedName, syncChange: true)

            self.loadProfiles()
            return nil
        } catch {
            print("An error occurred while saving profile: \(error)")
            return .fileLoadError
        }
    }

    /// Replaces a saved profile's values with `settings` (from the profile editor).
    /// Only the file changes: Loop's live settings are untouched until the profile is loaded.
    @discardableResult
    func updateProfile(fileName: String, with settings: TherapySettings) -> Bool {
        guard let existing = cachedProfiles[fileName],
              let correctionRange = settings.glucoseTargetRangeSchedule?.schedule(for: .milligramsPerDeciliter),
              let carbRatioSchedule = settings.carbRatioSchedule,
              let basalRateSchedule = settings.basalRateSchedule,
              let insulinSensitivitySchedule = settings.insulinSensitivitySchedule?.schedule(for: .milligramsPerDeciliter) else {
            return false
        }
        let overrides = settings.correctionRangeOverrides
        let profile = Profile(
            name: existing.name,
            correctionRange: correctionRange,
            carbRatioSchedule: carbRatioSchedule,
            basalRateSchedule: basalRateSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule,
            sortOrder: existing.sortOrder,
            suspendThreshold: settings.suspendThreshold,
            correctionRangeOverrides: (overrides?.preMeal == nil && overrides?.workout == nil) ? nil : overrides,
            maximumBasalRatePerHour: settings.maximumBasalRatePerHour,
            maximumBolus: settings.maximumBolus
        )
        do {
            try write(profile, toFileNamed: fileName)
            os_log("Edited profile %{public}@", log: profileLog, type: .default, profile.name)
            loadProfiles()
            return true
        } catch {
            os_log("Editing profile failed: %{public}@", log: profileLog, type: .error, String(describing: error))
            return false
        }
    }

    public func renameProfile(oldName: String, newName: String) {
        let sanitizedProfileName = sanitizeProfileName(newName)
        guard !sanitizedProfileName.isEmpty else { return }

        do {
            guard let profileReference = getProfileReference(withName: oldName) else {
                print("Profile with old name not found.")
                return
            }

            let profile = try getProfile(from: profileReference)

            var newProfile = profile
            newProfile.name = sanitizedProfileName

            if let existingProfile = getProfileReference(withName: sanitizedProfileName),
               existingProfile.fileName != profileReference.fileName {
                removeProfile(profileReference: existingProfile)
            }

            try write(newProfile, toFileNamed: profileReference.fileName)

            if currentProfileName == oldName {
                setCurrentProfile(name: sanitizedProfileName, syncChange: true)
            }

            self.loadProfiles()
        } catch {
            print("An error occurred while renaming profile: \(error)")
        }
    }

    /// Moves a profile one place up (-1) or down (+1) in the list.
    public func moveProfile(_ reference: ProfileReference, by offset: Int) {
        guard let index = profiles.firstIndex(of: reference) else { return }
        let target = index + offset
        guard profiles.indices.contains(target) else { return }
        profiles.swapAt(index, target)
        updateProfilesOrder()
    }

    /// The live profile for a list row, read from the cache.
    func profile(for reference: ProfileReference) -> Profile? {
        cachedProfiles[reference.fileName]
    }

    /// True when the active profile's schedules no longer match the current therapy settings.
    public var isActiveProfileEdited: Bool {
        isCurrentProfileOutOfSync()
    }

    public func updateProfilesOrder() {
        for (index, profileReference) in profiles.enumerated() {
            do {
                let profile = try getProfile(from: profileReference)
                guard profile.sortOrder != index else { continue }
                var newProfile = profile
                newProfile.sortOrder = index
                try write(newProfile, toFileNamed: profileReference.fileName)
            } catch {
                print("An error occurred while updating profile order: \(error)")
            }
        }
        loadProfiles()
    }

    public func loadProfiles() {
        let profileFiles: [URL]
        do {
            profileFiles = try getAllProfileFiles()
        } catch {
            print("An error occurred while loading profiles: \(error)")
            return
        }

        var newProfiles = [ProfileReference]()
        var decoded = [String: Profile]()
        for fileURL in profileFiles {
            // One unreadable file must not hide every other profile.
            do {
                let data = try Data(contentsOf: fileURL)
                let profile = try decodeProfile(from: data)
                let fileName = fileURL.lastPathComponent
                decoded[fileName] = profile
                newProfiles.append(ProfileReference(name: sanitizeProfileName(profile.name), fileName: fileName, sortOrder: profile.sortOrder))
            } catch {
                print("Skipping unreadable profile \(fileURL.lastPathComponent): \(error)")
            }
        }

        newProfiles.sort { ($0.sortOrder ?? 0, $0.fileName) < ($1.sortOrder ?? 0, $1.fileName) }

        self.cachedProfiles = decoded
        self.profiles = newProfiles
    }

    public func loadProfile(profile: Profile, completion: @escaping (LoadProfileResult) -> Void) {
        guard let target = therapySettings(applying: profile) else {
            completion(.failure(ProfileValidationError.fileLoadError))
            return
        }

        if !isCurrentProfileOutOfSync(comparedTo: profile) {
            // Therapy settings already match: just mark it as the active profile.
            self.setCurrentProfile(name: profile.name, syncChange: true)
            completion(.success)
            return
        }

        guard let delegate else {
            completion(.failure(ProfileValidationError.fileLoadError))
            return
        }

        let current = therapySettings

        // 1. Delivery limits go to the pump first (this also cancels a running temp
        //    basal that is above a lower new maximum), 2. then the basal schedule,
        // 3. then everything is saved to Loop as one change. Steps the pump doesn't
        //    need are skipped.
        let limitsChanged = target.maximumBasalRatePerHour != current.maximumBasalRatePerHour
            || target.maximumBolus != current.maximumBolus
        let basalChanged = target.basalRateSchedule != current.basalRateSchedule

        func finish(_ settings: TherapySettings) {
            os_log("Loaded profile %{public}@", log: profileLog, type: .default, profile.name)
            // Record the name first: saving the settings uploads them, and the upload carries the name.
            setCurrentProfile(name: profile.name, syncChange: false)
            saveTherapySettings(settings)
            completion(.success)
        }

        func syncBasal(_ settings: TherapySettings) {
            guard basalChanged, let items = settings.basalRateSchedule?.items else {
                finish(settings)
                return
            }
            delegate.syncBasalRateSchedule(items: items) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let syncedSchedule):
                        var settings = settings
                        settings.basalRateSchedule = syncedSchedule
                        finish(settings)
                    case .failure(let error):
                        if limitsChanged {
                            // The pump already has the new limits; keep Loop in step with it.
                            var partial = self.therapySettings
                            partial.maximumBasalRatePerHour = settings.maximumBasalRatePerHour
                            partial.maximumBolus = settings.maximumBolus
                            self.saveTherapySettings(partial)
                        }
                        completion(.failure(error))
                    }
                }
            }
        }

        guard limitsChanged else {
            syncBasal(target)
            return
        }
        let limits = DeliveryLimits(
            maximumBasalRate: target.maximumBasalRatePerHour.map { HKQuantity(unit: .internationalUnitsPerHour, doubleValue: $0) },
            maximumBolus: target.maximumBolus.map { HKQuantity(unit: .internationalUnit(), doubleValue: $0) })
        delegate.syncDeliveryLimits(deliveryLimits: limits) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let synced):
                    var settings = target
                    settings.maximumBasalRatePerHour = synced.maximumBasalRate?.doubleValue(for: .internationalUnitsPerHour)
                    settings.maximumBolus = synced.maximumBolus?.doubleValue(for: .internationalUnit())
                    syncBasal(settings)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func getProfileReference(withName name: String) -> ProfileReference? {
        let sanitizedInputName = sanitizeProfileName(name)
        return profiles.first(where: { sanitizeProfileName($0.name) == sanitizedInputName })
    }

    public func removeProfile(profile: Profile) {
        guard let profileReference = getProfileReference(withName: profile.name) else {
            print("No ProfileReference found for given Profile")
            return
        }

        removeProfile(profileReference: profileReference)
        if currentProfileName == profile.name {
            clearCurrentProfile()
        }
    }

    public func removeProfile(profileReference: ProfileReference) {
        do {
            let fileManager = FileManager.default
            let fileURL = profilesDirectory.appendingPathComponent(profileReference.fileName)
            try fileManager.removeItem(at: fileURL)
            loadProfiles()
        } catch {
            print("An error occurred while removing profile: \(error)")
        }
    }

    func doesProfileExist(withName name: String) -> Bool {
        return getProfileReference(withName: name) != nil
    }

    public func getProfile(from profileReference: ProfileReference) throws -> Profile {
        if let cached = cachedProfiles[profileReference.fileName] {
            return cached
        }
        let fileURL = profilesDirectory.appendingPathComponent(profileReference.fileName)
        let data = try Data(contentsOf: fileURL)
        return try decodeProfile(from: data)
    }

    public func validateProfile(_ profile: Profile) -> Result<Void, ProfileValidationError> {
        guard let supportedIncrements = delegate?.pumpSupportedIncrements() else {
            return .failure(.fileLoadError)
        }

        guard !profile.correctionRange.items.isEmpty,
              !profile.insulinSensitivitySchedule.items.isEmpty,
              !profile.carbRatioSchedule.items.isEmpty,
              !profile.basalRateSchedule.items.isEmpty else {
            return .failure(.fileLoadError)
        }

        // The safety limit this profile would run with (older profiles keep the current one).
        let suspendThreshold = profile.suspendThreshold ?? therapySettings.suspendThreshold
        if let threshold = profile.suspendThreshold?.quantity,
           !Guardrail.suspendThreshold.absoluteBounds.contains(threshold) {
            return .failure(.suspendThresholdError)
        }

        // Checking Correction Range Schedule (a Profile always stores it in mg/dL)
        guard let correctionRange = profile.correctionRange.schedule(for: .milligramsPerDeciliter) else {
            return .failure(.correctionRangeError)
        }
        for item in correctionRange.items {
            let minValue = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: item.value.minValue)
            let maxValue = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: item.value.maxValue)

            if !(Guardrail.correctionRange.absoluteBounds.contains(minValue) && Guardrail.correctionRange.absoluteBounds.contains(maxValue)) {
                return .failure(.correctionRangeError)
            }
            // The correction range must stay above the suspend threshold, as the Therapy Settings editor requires.
            if let suspendThreshold = suspendThreshold?.quantity, minValue < suspendThreshold {
                return .failure(.correctionRangeError)
            }
        }

        // Pre-Meal and Workout ranges, against this profile's correction range and safety limit
        if let overrides = profile.correctionRangeOverrides {
            for preset in CorrectionRangeOverrides.Preset.allCases {
                guard let range = overrides.ranges[preset] else { continue }
                let guardrail = Guardrail.correctionRangeOverride(for: preset,
                                                                  correctionRangeScheduleRange: correctionRange.scheduleRange(),
                                                                  suspendThreshold: suspendThreshold)
                if !(guardrail.absoluteBounds.contains(range.lowerBound) && guardrail.absoluteBounds.contains(range.upperBound)) {
                    return .failure(.correctionRangeOverrideError)
                }
            }
        }

        // Checking Insulin Sensitivity Schedule
        guard let insulinSensitivity = profile.insulinSensitivitySchedule.schedule(for: .milligramsPerDeciliter) else {
            return .failure(.insulinSensitivityError)
        }
        for item in insulinSensitivity.items {
            let value = HKQuantity(unit: HKUnit.milligramsPerDeciliter.unitDivided(by: .internationalUnit()), doubleValue: item.value)

            if !Guardrail.insulinSensitivity.absoluteBounds.contains(value) {
                return .failure(.insulinSensitivityError)
            }
        }

        // Checking Carb Ratio Schedule
        for item in profile.carbRatioSchedule.items {
            let value = HKQuantity(unit: .gramsPerUnit, doubleValue: item.value)

            if !Guardrail.carbRatio.absoluteBounds.contains(value) {
                return .failure(.carbRatioError)
            }
        }

        // Delivery limits, against what the pump supports and this profile's own schedules.
        // Only a limit the profile CHANGES is checked: the current one is already in use.
        if let maximumBasalRate = profile.maximumBasalRatePerHour,
           abs(maximumBasalRate - (therapySettings.maximumBasalRatePerHour ?? -1)) > 0.0001 {
            let guardrail = Guardrail.maximumBasalRate(supportedBasalRates: supportedIncrements.basalRates,
                                                       scheduledBasalRange: profile.basalRateSchedule.valueRange(),
                                                       lowestCarbRatio: profile.carbRatioSchedule.lowestValue())
            if !supportedIncrements.basalRates.contains(where: { abs($0 - maximumBasalRate) < 0.0001 })
                || !guardrail.absoluteBounds.contains(HKQuantity(unit: .internationalUnitsPerHour, doubleValue: maximumBasalRate)) {
                return .failure(.maximumBasalRateError)
            }
        }
        if let maximumBolus = profile.maximumBolus,
           abs(maximumBolus - (therapySettings.maximumBolus ?? -1)) > 0.0001 {
            let guardrail = Guardrail.maximumBolus(supportedBolusVolumes: supportedIncrements.maximumBolusVolumes)
            if !supportedIncrements.maximumBolusVolumes.contains(where: { abs($0 - maximumBolus) < 0.0001 })
                || !guardrail.absoluteBounds.contains(HKQuantity(unit: .internationalUnit(), doubleValue: maximumBolus)) {
                return .failure(.maximumBolusError)
            }
        }

        // Checking Basal Rate Schedule
        if let maximumBasalRate = profile.maximumBasalRatePerHour ?? therapySettings.maximumBasalRatePerHour {
            if profile.basalRateSchedule.items.count > supportedIncrements.maximumBasalScheduleEntryCount {
                return .failure(.basalRateError)
            }
            for item in profile.basalRateSchedule.items {
                let value = item.value

                // Tolerance: stored rates pass through unit conversions and can gain float noise (0.30000000000000004).
                if value > maximumBasalRate + 0.0001 || !supportedIncrements.basalRates.contains(where: { abs($0 - value) < 0.0001 }) {
                    return .failure(.basalRateError)
                }
            }
        } else {
            return .failure(.maxBasalRateNotSet)
        }

        return .success(())
    }

    func isCorrectionRangeEqual(a: GlucoseRangeSchedule, b: GlucoseRangeSchedule) -> Bool {
        guard a.items.count == b.items.count else {
            return false
        }

        for (item1, item2) in zip(a.items, b.items) {
            if item1.startTime != item2.startTime ||
                abs(item1.value.minValue - item2.value.minValue) > 0.01 ||
                abs(item1.value.maxValue - item2.value.maxValue) > 0.01 {
                return false
            }
        }

        return true
    }

    func isInsulinSensitivityScheduleEqual(a: InsulinSensitivitySchedule, b: InsulinSensitivitySchedule) -> Bool {
        guard a.items.count == b.items.count else {
            return false
        }

        for (item1, item2) in zip(a.items, b.items) {
            if item1.startTime != item2.startTime ||
                abs(item1.value - item2.value) > 0.01 {
                return false
            }
        }

        return true
    }

    /// True when the current therapy settings differ from `profile` (compared in mg/dL, so mmol/L rounding doesn't matter).
    func isCurrentProfileOutOfSync(comparedTo profile: Profile) -> Bool {
        guard let therapyGlucoseSchedule = therapySettings.glucoseTargetRangeSchedule?.schedule(for: HKUnit.milligramsPerDeciliter),
              let therapyInsulinSensitivitySchedule = therapySettings.insulinSensitivitySchedule?.schedule(for: HKUnit.milligramsPerDeciliter),
              let profileGlucoseSchedule = profile.correctionRange.schedule(for: HKUnit.milligramsPerDeciliter),
              let profileInsulinSensitivitySchedule = profile.insulinSensitivitySchedule.schedule(for: HKUnit.milligramsPerDeciliter) else {
            return true
        }

        if !isCorrectionRangeEqual(a: therapyGlucoseSchedule, b: profileGlucoseSchedule)
            || therapySettings.carbRatioSchedule != profile.carbRatioSchedule
            || therapySettings.basalRateSchedule != profile.basalRateSchedule
            || !isInsulinSensitivityScheduleEqual(a: therapyInsulinSensitivitySchedule, b: profileInsulinSensitivitySchedule) {
            return true
        }

        // The rest only counts when the profile holds it (older profiles don't).
        let mgdl = HKUnit.milligramsPerDeciliter
        func differs(_ a: HKQuantity?, _ b: HKQuantity?) -> Bool {
            switch (a, b) {
            case (nil, nil): return false
            case let (a?, b?): return abs(a.doubleValue(for: mgdl) - b.doubleValue(for: mgdl)) > 0.5
            default: return true
            }
        }
        if let threshold = profile.suspendThreshold,
           differs(threshold.quantity, therapySettings.suspendThreshold?.quantity) {
            return true
        }
        if let overrides = profile.correctionRangeOverrides {
            let current = therapySettings.correctionRangeOverrides
            for preset in CorrectionRangeOverrides.Preset.allCases {
                if differs(overrides.ranges[preset]?.lowerBound, current?.ranges[preset]?.lowerBound)
                    || differs(overrides.ranges[preset]?.upperBound, current?.ranges[preset]?.upperBound) {
                    return true
                }
            }
        }
        if let maximumBasalRate = profile.maximumBasalRatePerHour,
           abs(maximumBasalRate - (therapySettings.maximumBasalRatePerHour ?? -1)) > 0.0001 {
            return true
        }
        if let maximumBolus = profile.maximumBolus,
           abs(maximumBolus - (therapySettings.maximumBolus ?? -1)) > 0.0001 {
            return true
        }
        return false
    }

    public func isCurrentProfileOutOfSync() -> Bool {
        guard let currentProfileName = self.currentProfileName,
              let currentProfileReference = profiles.first(where: { $0.name == currentProfileName }),
              let profile = try? getProfile(from: currentProfileReference),
              therapySettings.glucoseTargetRangeSchedule != nil,
              therapySettings.insulinSensitivitySchedule != nil else {
            return false // No current profile set or profile not found or schedules not available
        }

        return isCurrentProfileOutOfSync(comparedTo: profile)
    }
}
