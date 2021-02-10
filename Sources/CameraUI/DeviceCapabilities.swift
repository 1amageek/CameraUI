//
//  DeviceCapabilities.swift
//  
//
//  Created by nori on 2021/02/10.
//

import Foundation

@propertyWrapper public struct Supported<Value> {

    private var supported: Bool = false

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    public var wrappedValue: Value

    public var projectedValue: Bool {
        get { supported }
        set { supported = newValue }
    }
}


class DeviceCapabilities: ObservableObject {


}
