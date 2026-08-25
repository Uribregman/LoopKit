//
//  PreferencesProvider.swift
//  LoopKit
//
//  Created by Jonas Björkert on 2024-02-25.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

public protocol PreferencesProvider {
    var basalLockThreshold: HKQuantity { get set }
    var isBasalLockEnabled: Bool { get set }
}
