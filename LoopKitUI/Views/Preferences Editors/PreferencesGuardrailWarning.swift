//
//  PreferencesGuardrailWarning.swift
//  LoopKitUI
//
//  Created by Jonas Björkert on 2024-02-25.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit

public struct PreferencesGuardrailWarning: View {
    private enum CrossedThresholds {
        case one(SafetyClassification.Threshold)
        case oneOrMore([SafetyClassification.Threshold])
    }
    
    private var title: Text
    private var crossedThresholds: CrossedThresholds
    private var captionOverride: Text?
    private var preferencesSetting: PreferencesSetting
    
    public init(
        preferencesSetting: PreferencesSetting,
        title: Text,
        threshold: SafetyClassification.Threshold,
        caption: Text? = nil
    ) {
        self.preferencesSetting = preferencesSetting
        self.title = title
        self.crossedThresholds = .one(threshold)
        self.captionOverride = caption
    }
    
    public init(
        preferencesSetting: PreferencesSetting,
        title: Text,
        thresholds: [SafetyClassification.Threshold],
        caption: Text? = nil
    ) {
        precondition(!thresholds.isEmpty)
        self.preferencesSetting = preferencesSetting
        self.title = title
        self.crossedThresholds = .oneOrMore(thresholds)
        self.captionOverride = caption
    }
    
    public var body: some View {
        WarningView(title: title, caption: caption, severity: severity)
    }
    
    private var severity: WarningSeverity {
        switch crossedThresholds {
        case .one(let threshold):
            return threshold.severity
        case .oneOrMore(let thresholds):
            return thresholds.lazy.map({ $0.severity }).max()!
        }
    }
    
    private var caption: Text {
        if let caption = captionOverride {
            return caption
        }
        
        switch crossedThresholds {
        case .one(let threshold):
            return captionForThreshold(threshold)
        case .oneOrMore(let thresholds):
            if thresholds.count == 1, let threshold = thresholds.first {
                return captionForThreshold(threshold)
            } else {
                return captionForThresholds()
            }
        }
    }
    
    private func captionForThreshold(_ threshold: SafetyClassification.Threshold) -> Text {
        switch threshold {
        case .minimum, .belowRecommended:
            return Text(preferencesSetting.guardrailCaptionForLowValue)
        case .aboveRecommended, .maximum:
            return Text(preferencesSetting.guardrailCaptionForHighValue)
        }
    }
    
    private func captionForThresholds() -> Text {
        return Text(preferencesSetting.guardrailCaptionForOutsideValues)
    }
}

fileprivate extension SafetyClassification.Threshold {
    var severity: WarningSeverity {
        switch self {
        case .belowRecommended, .aboveRecommended:
            return .default
        case .minimum, .maximum:
            return .critical
        }
    }
}
