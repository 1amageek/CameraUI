//
//  DeviceCapabilities.swift
//  
//
//  Created by nori on 2021/02/10.
//

import Foundation
import AVFoundation

@propertyWrapper public struct Supported<Value> {

    private var status: Status

    private var valueWhenUnsupported: Value

    public init(valueWhenUnsupported: Value) {
        self.status = Status(isSupported: false, value: valueWhenUnsupported)
        self.valueWhenUnsupported = valueWhenUnsupported
    }

    public var wrappedValue: Value {
        get { status.isSupported ? status.value : valueWhenUnsupported }
        set { status.value = newValue }
    }

    public struct Status {

        public var isSupported: Bool = false

        public var value: Value

        public static func supported(value: Value) -> Status {
            Status(isSupported: true, value: value)
        }

        public static func unsupported(value: Value) -> Status {
            Status(isSupported: false, value: value)
        }
    }

    public var projectedValue: Status {
        get { status }
        set { status = newValue }
    }
}

extension Bool {
    func set<Value>(_ value: Value) -> Supported<Value>.Status {
        if self {
            return Supported<Value>.Status.supported(value: value)
        } else {
            return Supported<Value>.Status.unsupported(value: value)
        }
    }
}

extension Array {
    func set(_ value: [Element]) -> Supported<[Element]>.Status where Element: Equatable {
        let filteredItems: [Element] = value.filter({ self.contains($0) })
        if filteredItems.isEmpty {
            return Supported<[Element]>.Status.unsupported(value: filteredItems)
        } else {
            return Supported<[Element]>.Status.supported(value: filteredItems)
        }
    }
}

public class DeviceCapabilities: ObservableObject {

    public var isHighResolutionCaptureEnabled: Bool = true

    @Supported(valueWhenUnsupported: .off) public var flashMode: AVCaptureDevice.FlashMode

    @Supported(valueWhenUnsupported: false) public var isLivePhotoCaptureEnabled: Bool

    @Supported(valueWhenUnsupported: false) public var isDepthDataDeliveryEnabled: Bool

    @Supported(valueWhenUnsupported: false) public var isPortraitEffectsMatteDeliveryEnabled: Bool

    @Supported(valueWhenUnsupported: []) public var enabledSemanticSegmentationMatteTypes: [AVSemanticSegmentationMatte.MatteType]

    public var maxPhotoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization
}
