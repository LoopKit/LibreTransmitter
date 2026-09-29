//
//  GenericObservableObject.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 10/07/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine

class GenericObservableObject: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    func notify() {
        objectWillChange.send()
    }

    @discardableResult func listenOnce(listener: @escaping () -> Void) -> Self {
        objectWillChange
        .sink {  [weak self]_ in
            listener()
            self?.cancellables.removeAll()

        }
        .store(in: &cancellables)
        return self
    }

    /// Like `listenOnce`, but keeps listening for the lifetime of this object instead of
    /// tearing itself down after the first notification. Use for repeatable actions (e.g.
    /// navigation triggers that can fire more than once per screen), not one-shot ones.
    @discardableResult func listen(listener: @escaping () -> Void) -> Self {
        objectWillChange
        .sink { _ in
            listener()
        }
        .store(in: &cancellables)
        return self
    }
}
