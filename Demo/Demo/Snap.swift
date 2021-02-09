//
//  Snap.swift
//  Demo
//
//  Created by nori on 2021/02/08.
//

import Foundation

class Snap: ObservableObject {

    @Published var timer: Timer = Timer()

    @Published var duration: TimeInterval = 0

    func start() {
        self.duration = 0
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            self.duration += 0.05
        }
    }

    func stop() {
        self.timer.invalidate()
    }

    func reset() {
        self.duration = 0
    }
}
