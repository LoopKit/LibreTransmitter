//
//  GlucoseSmoothing.swift
//  MiaomiaoClientUI
//
//  Created by LoopKit Authors on 25/03/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

// https://github.com/NightscoutFoundation/xDrip/pull/828/files

/// Smooths readings over the same 5 minutes the 5-point average covers when the
/// readings are one minute apart, as they are in a sensor's FRAM.
///
/// A Libre 2's BLE packet holds readings 0, 2, 4, 6, 7, 12 and 15 minutes old. Five of
/// those points span 7 minutes, so the 5-point average lags a changing glucose by
/// about 4 minutes. For readings that are not one minute apart, each reading is
/// averaged with the readings up to 4 minutes older than it instead.
func CalculateSmoothedData(origtrends: [LibreGlucose]) -> [LibreGlucose] {
    let oneMinuteApart = zip(origtrends, origtrends.dropFirst()).allSatisfy {
        abs(abs($0.startDate.timeIntervalSince($1.startDate)) - 60) < 15
    }
    if oneMinuteApart {
        return CalculateSmothedData5Points(origtrends: origtrends)
    }

    var trends = origtrends
    for i in trends.indices {
        let window = origtrends.filter {
            let older = trends[i].startDate.timeIntervalSince($0.startDate)
            return older > -15 && older < 4.5 * 60
        }
        trends[i].glucoseDouble = window.map(\.unsmoothedGlucose).reduce(0, +) / Double(window.count)
    }
    return trends
}

// private func trendToLibreGlucose(_ measurements: [Measurement]) -> [LibreGlucose]?{

func CalculateSmothedData5Points(origtrends: [LibreGlucose]) -> [LibreGlucose] {
    // In all places in the code, there should be exactly 16 points.
    // Since that might change, and I'm doing an average of 5, then in the case of less then 5 points,
    // I'll only copy the data as is (to make sure there are reasonable values when the function returns).

    var trends = origtrends
    // this is an adoptation, doesn't follow the original directly
    if trends.count < 5 {
        for i in 0 ..< trends.count {
            trends[i].glucoseDouble = trends[i].unsmoothedGlucose
        }

        return trends
    }
    for i in 0 ..< trends.count - 4 {
        trends[i].glucoseDouble = (trends[i].unsmoothedGlucose + trends[i + 1].unsmoothedGlucose +
                                   trends[i + 2].unsmoothedGlucose +
                                   trends[i + 3].unsmoothedGlucose +
                                   trends[i + 4].unsmoothedGlucose) / 5
    }
    trends[trends.count - 4].glucoseDouble = (trends[trends.count - 4].unsmoothedGlucose +
                                              trends[trends.count - 3].unsmoothedGlucose +
                                              trends[trends.count - 2].unsmoothedGlucose +
                                              trends[trends.count - 1].unsmoothedGlucose) / 4

    trends[trends.count - 3].glucoseDouble = (trends[trends.count - 3].unsmoothedGlucose + trends[trends.count - 2].unsmoothedGlucose + trends[trends.count - 1].unsmoothedGlucose ) / 3

    trends[trends.count - 2].glucoseDouble = (trends[trends.count - 2].unsmoothedGlucose + trends[trends.count - 1].unsmoothedGlucose ) / 2

    trends[trends.count - 1].glucoseDouble = trends[trends.count - 2].glucoseDouble

    return trends
}
