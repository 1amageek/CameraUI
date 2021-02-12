//
//  File.swift
//  
//
//  Created by nori on 2021/02/12.
//

import Foundation

@propertyWrapper public struct Control<Value> {

    private var state: State

    public var wrappedValue: Value

    public init(wrappedValue: Value, state: State) {
        self.wrappedValue = wrappedValue
        self.state = state
    }

    public var projectedValue: State {
        get { state }
        set { state = newValue }
    }

    public struct State {

        public var isEnabled: Bool = true

        public var isHidden: Bool = true

        public init(isEnabled: Bool, isHidden: Bool) {
            self.isEnabled = isEnabled
            self.isHidden = isHidden
        }

        public static var `default`: State {
            return .init(isEnabled: false, isHidden: false)
        }
    }
}
