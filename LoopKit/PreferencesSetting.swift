//
//  PreferencesSetting.swift
//  LoopKit
//
//  Created by Jonas Björkert on 2024-02-25.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation

public enum PreferencesSetting {
    case basalLock
}

extension PreferencesSetting: Equatable { }

public extension PreferencesSetting {
    var title: String {
        switch self {
        case .basalLock:
            return LocalizedString("Basal Lock", comment: "Title text for basal lock setting")
        }
    }
    
    var smallTitle: String {
        return title
    }
    
    func descriptiveText(appName: String) -> String {
        switch self {
        case .basalLock:
            return String(format: LocalizedString("Basal Lock prevents the basal rate from being throttled if the blood glucose is above a certain level.", comment: "Descriptive text for basal lock (1: app name)"), appName)
        }
    }
}

// MARK: Guardrails
public extension PreferencesSetting {
    var guardrailCaptionForLowValue: String {
        switch self {
        case .basalLock:
            return LocalizedString("The value you have entered is lower than what is typically recommended.", comment: "Descriptive text for guardrail low value warning for basal lock")
        }
    }
    
    var guardrailCaptionForHighValue: String {
        switch self {
        case .basalLock:
            return LocalizedString("The value you have entered is higher than what is typically recommended.", comment: "Descriptive text for guardrail high value warning for basal lock")
        }
    }
    
    var guardrailCaptionForOutsideValues: String {
        return LocalizedString("The value you have entered for Basal Lock is outside of the recommended range.", comment: "Descriptive text for guardrail outside value warning for basal lock")
    }
    
    var guardrailSaveWarningCaption: String {
        return LocalizedString("Please note that this value is outside of the recommended range.", comment: "Descriptive text for saving settings outside the recommended range for basal lock")
    }
}
