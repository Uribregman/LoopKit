//
//  Guardrail+Preferences.swift
//  LoopKit
//
//  Created by Jonas Björkert on 2024-02-25.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

public extension Guardrail where Value == HKQuantity {
    static let basalLockThreshold = Guardrail(
        absoluteBounds: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 200)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 300),
        recommendedBounds: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 220)...HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 300),
        startingSuggestion: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 250)
    )
}
