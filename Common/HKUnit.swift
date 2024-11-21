//
//  HKUnit.swift
//  xDripG5
//
//  Created by Nate Racklyeft on 8/6/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopAlgorithm

extension LoopUnit {
    var localizedShortUnitString: String {
        if self == LoopUnit.millimolesPerLiter {
            return NSLocalizedString("mmol/L", comment: "The short unit display string for millimoles of glucose per liter")
        } else if self == .milligramsPerDeciliter {
            return NSLocalizedString("mg/dL", comment: "The short unit display string for milligrams of glucose per decilter")
        } else if self == .internationalUnit {
            return NSLocalizedString("U", comment: "The short unit display string for international units of insulin")
        } else if self == .gram {
            return NSLocalizedString("g", comment: "The short unit display string for grams")
        } else {
            return String(describing: self)
        }
    }
}
