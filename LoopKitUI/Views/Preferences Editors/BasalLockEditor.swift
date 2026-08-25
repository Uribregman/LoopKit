//
//  BasalLockEditor.swift
//  LoopKitUI
//
//  Created by Jonas Björkert on 2024-02-25.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit

public struct BasalLockEditor: View {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    
    @Environment(\.dismissAction) var dismiss
    @Environment(\.authenticate) var authenticate
    @Environment(\.appName) private var appName
    
    let viewModel: PreferencesViewModel
    let didSave: (() -> Void)?
    
    @State private var userDidTap: Bool = false
    @State private var isBasalLockEnabled: Bool
    @State private var threshold: HKQuantity
    @State private var isEditing = false
    @State private var showingConfirmationAlert = false
    
    private var initialValue: HKQuantity {
        viewModel.basalLockThreshold
    }
    
    public init(preferencesViewModel: PreferencesViewModel, didSave: (() -> Void)? = nil) {
        self.viewModel = preferencesViewModel
        self._isBasalLockEnabled = State(initialValue: preferencesViewModel.isBasalLockEnabled)
        self._threshold = State(initialValue: preferencesViewModel.basalLockThreshold)
        self.didSave = didSave
    }
    
    public var body: some View {
        contentWithCancel
            .navigationBarTitle("", displayMode: .inline)
    }
    
    private var contentWithCancel: some View {
        content
            .navigationBarBackButtonHidden(isBasalLockEnabled != viewModel.isBasalLockEnabled || threshold != viewModel.basalLockThreshold)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    leadingNavigationBarItem
                }
            }
    }
    
    @ViewBuilder
    private var leadingNavigationBarItem: some View {
        if isBasalLockEnabled != viewModel.isBasalLockEnabled || threshold != viewModel.basalLockThreshold {
            cancelButton
        } else {
            EmptyView()
        }
    }
    
    private var cancelButton: some View {
        Button(action: { self.dismiss() }) {
            Text(LocalizedString("Cancel", comment: "Cancel editing settings button title"))
        }
    }
    
    private var picker: GlucoseValuePicker {
        GlucoseValuePicker(
            value: self.$threshold.animation(),
            unit: displayGlucosePreference.unit,
            guardrail: .basalLockThreshold,
            bounds: Guardrail.basalLockThreshold.absoluteBounds.lowerBound...Guardrail.basalLockThreshold.absoluteBounds.upperBound
        )
    }
    
    private var content: some View {
        ConfigurationPage(
            title: Text(LocalizedString("Basal Lock Threshold", comment: "Title for basal lock threshold setting")),
            actionButtonTitle: Text(LocalizedString("Save", comment: "Save button title")),
            actionButtonState: saveButtonState,
            cards: {
                Card {
                    description
                        .font(.callout)
                        .foregroundColor(Color(.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Toggle(isOn: $isBasalLockEnabled) {
                        Text("Enable Basal Lock")
                    }
                    .animation(.default, value: isBasalLockEnabled)
                    
                    ExpandableSetting(
                        isEditing: $isEditing,
                        valueContent: {
                            GuardrailConstrainedQuantityView(
                                value: threshold,
                                unit: displayGlucosePreference.unit,
                                guardrail: .basalLockThreshold,
                                isEditing: isEditing,
                                // Workaround for strange animation behavior on appearance
                                forceDisableAnimations: true
                            )
                        },
                        expandedContent: {
                            // Prevent the picker from expanding the card's width on small devices
                            picker.frame(maxWidth: 200)
                        }
                    )
                    .transition(.slide)
                }
            },
            actionAreaContent: {
                instructionalContentIfNecessary
                if isBasalLockEnabled && warningThreshold != nil && userDidTap {
                    PreferencesGuardrailWarning(preferencesSetting: .basalLock, title: basalLockTitle, threshold: warningThreshold!)
                        .transition(.slide)
                }
            },
            action: {
                if self.warningThreshold == nil {
                    self.startSaving()
                } else {
                    self.showingConfirmationAlert = true
                }
            }
        )
        .alert(isPresented: $showingConfirmationAlert, content: confirmationAlert)
        .simultaneousGesture(TapGesture().onEnded {
            withAnimation {
                self.userDidTap = true
            }
        })
    }
    
    private var basalLockTitle: Text {
        Text(LocalizedString("Basal Lock Threshold", comment: "Title for basal lock threshold setting"))
    }
    
    private var description: Text {
        Text(LocalizedString("Basal Lock prevents the basal rate from being throttled if the blood glucose is above a certain level.", comment: "Description for basal lock threshold setting"))
    }
    
    private var instructionalContentIfNecessary: some View {
        Group {
            if !userDidTap {
                instructionalContent
            }
        }
    }
    
    private var instructionalContent: some View {
        HStack {
            Text(LocalizedString("You can edit the setting by tapping into the line item.", comment: "Description of how to edit setting"))
                .foregroundColor(.secondary)
                .font(.subheadline)
            Spacer()
        }
    }
    
    private var saveButtonState: ConfigurationPageActionButtonState {
        let selectableValues = picker.selectableValues
        let adjustedBounds = (selectableValues.first!)...(selectableValues.last!)
        guard adjustedBounds.contains(threshold.doubleValue(for: displayGlucosePreference.unit)) else {
            return .disabled
        }
        return (isBasalLockEnabled != viewModel.isBasalLockEnabled || threshold != viewModel.basalLockThreshold) ? .enabled : .disabled
    }
    
    private var warningThreshold: SafetyClassification.Threshold? {
        switch Guardrail.basalLockThreshold.classification(for: threshold) {
        case .withinRecommendedRange:
            return nil
        case .outsideRecommendedRange(let threshold):
            return threshold
        }
    }
    
    private func confirmationAlert() -> SwiftUI.Alert {
        SwiftUI.Alert(
            title: Text(LocalizedString("Save Basal Lock Threshold?", comment: "Alert title for confirming a basal lock threshold outside the recommended range")),
            message: Text(LocalizedString("Your setting for basal lock is outside the recommended range.", comment: "Descriptive text for saving settings outside the recommended range for basal lock")),
            primaryButton: .cancel(Text(LocalizedString("Go Back", comment: "Text for go back action on confirmation alert"))),
            secondaryButton: .default(
                Text(LocalizedString("Continue", comment: "Text for continue action on confirmation alert")),
                action: startSaving
            )
        )
    }
    
    private func startSaving() {
        authenticate(LocalizedString("Authentication is required to save this setting.", comment: "Authentication challenge description for basal lock threshold")) {
            switch $0 {
            case .success: self.continueSaving()
            case .failure: break
            }
        }
    }
    
    private func continueSaving() {
        viewModel.updateBasalLockEnabled(self.isBasalLockEnabled)
        viewModel.updateBasalLockThreshold(self.threshold)
        didSave?()
        self.dismiss()
    }
}
