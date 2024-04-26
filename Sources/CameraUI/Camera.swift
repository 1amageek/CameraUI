//
//  Camera.swift
//
//
//  Created by nori on 2021/02/06.
//

import UIKit
import Foundation
import AVFoundation
import Photos

public class Camera: NSObject, ObservableObject {
    
    public enum CaptureMode: Equatable {
        
        case photo(Configuration)
        
        case movie(Configuration)
        
        var configuration: Configuration {
            switch self {
            case .photo(let configuration): return configuration
            case .movie(let configuration): return configuration
            }
        }
        
        public struct Configuration: Equatable {
            
            public var sessionPreset: AVCaptureSession.Preset
            
            public var angleMode: AngleMode
            
            public init(sessionPreset: AVCaptureSession.Preset, angleMode: AngleMode = .responsive) {
                self.sessionPreset = sessionPreset
                self.angleMode = angleMode
            }
            
            public static var photo: Configuration { Configuration(sessionPreset: .photo) }
            
            public static var high: Configuration { Configuration(sessionPreset: .high) }
            
            public static var medium: Configuration { Configuration(sessionPreset: .medium) }
            
            public static var low: Configuration { Configuration(sessionPreset: .low) }
        }
        
        public static func == (lhs: Camera.CaptureMode, rhs: Camera.CaptureMode) -> Bool {
            switch (lhs, rhs) {
            case (.photo(let c0), .photo(let c1)): return c0 == c1
            case (.movie(let c0), .movie(let c1)): return c0 == c1
            default: return false
            }
        }
    }
    
    public enum VideoDevice {
        
        case back(Configuration? = nil)
        
        case front(Configuration? = nil)
        
        var position: AVCaptureDevice.Position {
            switch self {
            case .back(_): return .back
            case .front(_): return .front
            }
        }
        
        var deviceType: AVCaptureDevice.DeviceType? {
            switch self {
            case .back(let configuration): return configuration?.deviceType
            case .front(let configuration): return configuration?.deviceType
            }
        }
        
        var videoStabilizationMode: AVCaptureVideoStabilizationMode {
            switch self {
            case .back(let configuration): return configuration?.videoStabilizationMode ?? .auto
            case .front(let configuration): return configuration?.videoStabilizationMode ?? .auto
            }
        }
        
        public struct Configuration {
            
            public var deviceType: AVCaptureDevice.DeviceType?
            
            public var videoStabilizationMode: AVCaptureVideoStabilizationMode
            
            public init(deviceType: AVCaptureDevice.DeviceType?, videoStabilizationMode: AVCaptureVideoStabilizationMode = .auto) {
                self.deviceType = deviceType
                self.videoStabilizationMode = videoStabilizationMode
            }
            
            public static var builtInWideAngleCamera: Configuration { Configuration(deviceType: .builtInWideAngleCamera) }
            
            public static var builtInTelephotoCamera: Configuration { Configuration(deviceType: .builtInTelephotoCamera) }
            
            public static var builtInUltraWideCamera: Configuration { Configuration(deviceType: .builtInUltraWideCamera) }
            
            public static var builtInDualCamera: Configuration { Configuration(deviceType: .builtInDualCamera) }
            
            public static var builtInDualWideCamera: Configuration { Configuration(deviceType: .builtInDualWideCamera) }
            
            public static var builtInTripleCamera: Configuration { Configuration(deviceType: .builtInTripleCamera) }
            
            public static var builtInTrueDepthCamera: Configuration { Configuration(deviceType: .builtInTrueDepthCamera) }
            
            public static var builtInLiDARDepthCamera: Configuration { Configuration(deviceType: .builtInLiDARDepthCamera) }
            
            public static var continuityCamera: Configuration { Configuration(deviceType: .continuityCamera) }
            
        }
    }
    
    public enum AngleMode: Equatable {
        case fixed(Orientation)
        case responsive
        
        public enum Orientation {
            case portrait
            case portraitUpsideDown
            case landscapeLeft
            case landscapeRight
        }
    }

    
    public enum LivePhotoCaptureMode {
        case on
        case off
    }
    
    public enum DepthDataDeliveryMode {
        case on
        case off
    }
    
    public enum PortraitEffectsMatteDeliveryMode {
        case on
        case off
    }
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    public enum Error: Swift.Error {
        case notAuthorized
        case configurationFailed
    }
    
    public let session: AVCaptureSession = AVCaptureSession()
    
    private var isSessionRunning: Bool = false
    
    // Communicate with the session and other session objects on this queue.
    public let sessionQueue: DispatchQueue = DispatchQueue(label: "queue.session.CameraUI")
    
    private var setupResult: SessionSetupResult = .success
    
    @objc public dynamic var videoDeviceInput: AVCaptureDeviceInput!
    
    // MARK: Device Configuration
    
    private var videoDeviceDiscoverySession: AVCaptureDevice.DiscoverySession!
    
    // MARK: DeviceCapabilities
    
    @Published public var controller: AVCaptureDevice.Controller = AVCaptureDevice.Controller()
    
    // MARK: Mode
    
    @Published public private(set) var angleMode: AngleMode = .responsive
    
    @Published public private(set) var isEnabled: Bool = false
    
    @Published public private(set) var captureMode: CaptureMode = .photo(.photo)
    
    @Published public private(set) var videoDevice: VideoDevice = .back(.builtInWideAngleCamera)
    
    @Published public private(set) var deviceOrientation: UIDeviceOrientation = UIDevice.current.orientation
    
    // MARK: State
    
    @Published public private(set) var isCapturingLivePhoto: Bool = false
    
    @Published public private(set) var isPhotoProcessing: Bool = false
    
    @Published public private(set) var isCameraChanging: Bool = false
    
    @Published public private(set) var isMovieRecoding: Bool = false
    
    @Published public var interruptionReason: AVCaptureSession.InterruptionReason?
    
    @Published public var error: Camera.Error?
    
    // MARK: Preview
    
    public let previewView: PreviewView = PreviewView()
    
    // MARK: Capturing Photos
    
    public let photoOutput: AVCapturePhotoOutput = AVCapturePhotoOutput()
    
    private var inProgressPhotoCaptureDelegates: [Int64: PhotoCaptureProcessor] = [:]
    
    private var inProgressFileOutputRecodingDelegates: [String: FileOutputRecordingProcesser] = [:]
    
    fileprivate var inProgressLivePhotoCapturesCount = 0
    
    // MARK: Recording Movies
    
    private var movieFileOutput: AVCaptureMovieFileOutput?
    
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    
    private var videoDeviceRotationCoordinator: AVCaptureDevice.RotationCoordinator!
    
    override private init() {
        super.init()
    }
    
    public convenience init(captureMode: CaptureMode = .photo(.photo),
                            videoDevice: VideoDevice = .back(.builtInWideAngleCamera),
                            useDeviceTypes: [AVCaptureDevice.DeviceType] = [
                                .builtInWideAngleCamera,
                                .builtInDualCamera,
                                .builtInTrueDepthCamera
                            ]) {
                                self.init()
                                self.captureMode = captureMode
                                self.videoDevice = videoDevice
                                self.videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: useDeviceTypes,
                                                                                                    mediaType: .video,
                                                                                                    position: .unspecified)
                                self.previewView.session = session
                                self.boot()
                            }
    
    private func boot() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. Suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general, it's not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Don't perform these tasks on the main queue because
         AVCaptureSession.startRunning() is a blocking call, which can
         take a long time. Dispatch session setup to the sessionQueue, so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        let previewLayer = self.previewView.videoPreviewLayer
        sessionQueue.async {
            self.configureSession(previewLayer: previewLayer)
        }
    }
    
    public func onAppear() {
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    self.error = .notAuthorized
                }
            case .configurationFailed:
                DispatchQueue.main.async {
                    self.error = .configurationFailed
                }
            }
        }
    }
    
    public func onDisappear() {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
    }
    
    private var videoRotationAngleForHorizonLevelPreviewObservation: NSKeyValueObservation?
    
    private func createDeviceRotationCoordinator(videoDeviceInput: AVCaptureDeviceInput, videoPreviewLayer: AVCaptureVideoPreviewLayer) {

        let newVideoRotationAngle: CGFloat = getVideoRotationAngle(videoDeviceRotationCoordinator)
        
        // Ensure connection exists and supports the new rotation angle before setting it.
        guard let connection = videoPreviewLayer.connection,
              connection.isVideoRotationAngleSupported(newVideoRotationAngle) else {
            print("The video rotation angle is either unsupported or the connection is nil.")
            return
        }
        connection.videoRotationAngle = newVideoRotationAngle
        
        // Set up an observer to adjust the video rotation angle when the mode is responsive
        switch captureMode.configuration.angleMode {
            case .fixed:
                // Remove the observer if it was previously set
                videoRotationAngleForHorizonLevelPreviewObservation?.invalidate()
                videoRotationAngleForHorizonLevelPreviewObservation = nil
            case .responsive:
                videoRotationAngleForHorizonLevelPreviewObservation = videoDeviceRotationCoordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { _, change in
                    guard let videoRotationAngleForHorizonLevelPreview = change.newValue,
                          connection.isVideoRotationAngleSupported(videoRotationAngleForHorizonLevelPreview) else {
                        return
                    }
                    connection.videoRotationAngle = videoRotationAngleForHorizonLevelPreview
                }
            }
    }
    
    private func getVideoRotationAngle(_ videoDeviceRotationCoordinator: AVCaptureDevice.RotationCoordinator) -> CGFloat {
        switch captureMode.configuration.angleMode {
        case .fixed(let orientation):
            switch orientation {
            case .portrait:
                return 90
            case .portraitUpsideDown:
                return 270
            case .landscapeLeft:
                return 0
            case .landscapeRight:
                return 180
            }
        case .responsive:
            return videoDeviceRotationCoordinator.videoRotationAngleForHorizonLevelPreview
        }
    }

    
    // Call this on the session queue.
    /// - Tag: ConfigureSession
    private func configureSession(previewLayer: AVCaptureVideoPreviewLayer) {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        // Add video input.
        var defaultVideoDevice: AVCaptureDevice?
        
        // Choose the back dual camera, if available, otherwise default to a wide angle camera.
        
        if let deviceType: AVCaptureDevice.DeviceType = videoDevice.deviceType,
           let defaultDevice: AVCaptureDevice = AVCaptureDevice.default(deviceType, for: .video, position: videoDevice.position) {
            defaultVideoDevice = defaultDevice
        } else if let dualCameraDevice: AVCaptureDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            defaultVideoDevice = dualCameraDevice
        } else if let backCameraDevice: AVCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            defaultVideoDevice = backCameraDevice
        } else if let builtInUltraWideCamera: AVCaptureDevice = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
            defaultVideoDevice = builtInUltraWideCamera
        } else if let frontCameraDevice: AVCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            defaultVideoDevice = frontCameraDevice
        }
        guard let videoDevice = defaultVideoDevice else {
            print("Default video device is unavailable.")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        do {
            let videoDeviceInput: AVCaptureDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            guard session.canAddInput(videoDeviceInput) else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            
            session.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
            self.videoDeviceRotationCoordinator = AVCaptureDevice.RotationCoordinator(device: videoDeviceInput.device, previewLayer: previewLayer)
            DispatchQueue.main.async {
                self.createDeviceRotationCoordinator(videoDeviceInput: videoDeviceInput, videoPreviewLayer: previewLayer)
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add an audio input device.
        let audioDevice = AVCaptureDevice.default(for: .audio)
        do {
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
            }
        } catch {
            print("Could not create audio device input: \(error)")
        }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            if case .movie(let configuration) = captureMode {
                let movieFileOutput: AVCaptureMovieFileOutput = AVCaptureMovieFileOutput()
                if session.canAddOutput(movieFileOutput) {
                    session.addOutput(movieFileOutput)
                    session.sessionPreset = configuration.sessionPreset
                    if let connection = movieFileOutput.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = self.videoDevice.videoStabilizationMode
                        }
                    }
                    self.movieFileOutput = movieFileOutput
                }
            }
            
            if case .photo(let configuration) = captureMode {
                session.sessionPreset = configuration.sessionPreset
                if let connection = photoOutput.connection(with: .video) {
                    let newVideoRotationAngle: CGFloat = getVideoRotationAngle(videoDeviceRotationCoordinator)
                    if connection.isVideoRotationAngleSupported(newVideoRotationAngle) {
                        connection.videoRotationAngle = newVideoRotationAngle
                    }
                }
            }
            
            let maxDimensions = videoDevice.activeFormat.supportedMaxPhotoDimensions
                .max(by: { $0.width * $0.height < $1.width * $1.height })
            
            photoOutput.maxPhotoDimensions = maxDimensions!
            photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
            photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
            photoOutput.enabledSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
            let availableSemanticSegmentationMatteTypes: [AVSemanticSegmentationMatte.MatteType] = photoOutput.availableSemanticSegmentationMatteTypes
            photoOutput.maxPhotoQualityPrioritization = .quality
            DispatchQueue.main.async {
                self.controller.$livePhotoCaptureMode.isEnabled = self.photoOutput.isLivePhotoCaptureEnabled
                self.controller.$depthDataDeliveryMode.isEnabled = self.photoOutput.isDepthDataDeliveryEnabled
                self.controller.$portraitEffectsMatteDeliveryMode.isEnabled = self.photoOutput.isPortraitEffectsMatteDeliveryEnabled
                self.controller.$semanticSegmentationMatteTypes.isEnabled = availableSemanticSegmentationMatteTypes.isEmpty
                self.controller.photoQualityPrioritizationMode = self.photoOutput.maxPhotoQualityPrioritization
            }
        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    public func focusAndExposeTap(_ location: CGPoint) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: location)
        focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                /*
                 Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                 Call set(Focus/Exposure)Mode() to apply the new point of interest.
                 */
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    // MARK: KVO and Notifications
    
    private var orientationDidChangeObserver: NSObjectProtocol?
    private var AVCaptureDeviceSubjectAreaDidChangeObserver: NSObjectProtocol?
    private var AVCaptureSessionRuntimeErrorObserver: NSObjectProtocol?
    private var AVCaptureSessionWasInterruptedObserver: NSObjectProtocol?
    private var AVCaptureSessionInterruptionEndedObserver: NSObjectProtocol?
    private var keyValueObservations: [NSKeyValueObservation] = []
    /// - Tag: ObserveInterruption
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            let isLivePhotoCaptureEnabled = self.photoOutput.isLivePhotoCaptureEnabled
            let isDepthDeliveryDataEnabled = self.photoOutput.isDepthDataDeliveryEnabled
            let isPortraitEffectsMatteEnabled = self.photoOutput.isPortraitEffectsMatteDeliveryEnabled
            let isSemanticSegmentationMatteEnabled = !self.photoOutput.enabledSemanticSegmentationMatteTypes.isEmpty
            
            DispatchQueue.main.async {
                self.isEnabled = isSessionRunning
                self.controller.$livePhotoCaptureMode.isEnabled = isLivePhotoCaptureEnabled
                self.controller.$depthDataDeliveryMode.isEnabled = isDepthDeliveryDataEnabled
                self.controller.$portraitEffectsMatteDeliveryMode.isEnabled = isPortraitEffectsMatteEnabled
                self.controller.$semanticSegmentationMatteTypes.isEnabled = isSemanticSegmentationMatteEnabled
            }
        }
        keyValueObservations.append(keyValueObservation)
        
        let systemPressureStateObservation = observe(\.videoDeviceInput.device.systemPressureState, options: .new) { _, change in
            guard let systemPressureState = change.newValue else { return }
            self.setRecommendedFrameRateRangeForPressureState(systemPressureState: systemPressureState)
        }
        keyValueObservations.append(systemPressureStateObservation)
        
        orientationDidChangeObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { notification in
            self.deviceOrientation = UIDevice.current.orientation
        }
        AVCaptureDeviceSubjectAreaDidChangeObserver = NotificationCenter.default.addObserver(forName: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device, queue: .main) { notification in
            self.subjectAreaDidChange(notification: notification as NSNotification)
        }
        AVCaptureSessionRuntimeErrorObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { notification in
            self.sessionRuntimeError(notification: notification as NSNotification)
        }
        
        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        
        AVCaptureSessionWasInterruptedObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { notification in
            if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
               let reasonIntegerValue = userInfoValue.integerValue,
               let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
                print("Capture session was interrupted with reason \(reason)")
                self.interruptionReason = reason
            }
        }
        
        AVCaptureSessionInterruptionEndedObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { notification in
            print("Capture session interruption ended")
        }
    }
    
    private func removeObservers() {
        if let observer = orientationDidChangeObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = AVCaptureDeviceSubjectAreaDidChangeObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = AVCaptureSessionRuntimeErrorObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = AVCaptureSessionWasInterruptedObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = AVCaptureSessionInterruptionEndedObserver { NotificationCenter.default.removeObserver(observer) }
        NotificationCenter.default.removeObserver(self)
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
    }
    
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    /// - Tag: HandleRuntimeError
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        
        print("Capture session runtime error: \(error)")
        // If media services were reset, and the last start succeeded, restart the session.
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        //                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            //            resumeButton.isHidden = false
        }
    }
    
    /// - Tag: HandleSystemPressure
    private func setRecommendedFrameRateRangeForPressureState(systemPressureState: AVCaptureDevice.SystemPressureState) {
        /*
         The frame rates used here are only for demonstration purposes.
         Your frame rate throttling may be different depending on your app's camera configuration.
         */
        let pressureLevel = systemPressureState.level
        if pressureLevel == .serious || pressureLevel == .critical {
            if self.movieFileOutput == nil || self.movieFileOutput?.isRecording == false {
                do {
                    try self.videoDeviceInput.device.lockForConfiguration()
                    print("WARNING: Reached elevated system pressure level: \(pressureLevel). Throttling frame rate.")
                    self.videoDeviceInput.device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
                    self.videoDeviceInput.device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                    self.videoDeviceInput.device.unlockForConfiguration()
                } catch {
                    print("Could not lock device for configuration: \(error)")
                }
            }
        } else if pressureLevel == .shutdown {
            print("Session stopped running due to shutdown system pressure level.")
        }
    }
}

// MARK: - Chage CaptureVideoDevice

extension Camera {
    
    public func change(captureVideoDevice: VideoDevice) {
        self.isCameraChanging = true
        let videoPreviewLayer = self.previewView.videoPreviewLayer
        sessionQueue.async {
            
            let preferredPosition: AVCaptureDevice.Position = captureVideoDevice.position
            
            let devices: [AVCaptureDevice] = self.videoDeviceDiscoverySession.devices
            var newVideoDevice: AVCaptureDevice? = nil
            
            // First, seek a device with both the preferred position and device type. Otherwise, seek a device with only the preferred position.
            if let preferredDeviceType: AVCaptureDevice.DeviceType = captureVideoDevice.deviceType,
               let device: AVCaptureDevice = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
                newVideoDevice = device
            } else if let device = devices.first(where: { $0.position == preferredPosition }) {
                newVideoDevice = device
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput: AVCaptureDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    // Remove the existing device input first, because AVCaptureSession doesn't support
                    // simultaneous use of the rear and front cameras.
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        if let observer = self.AVCaptureDeviceSubjectAreaDidChangeObserver {
                            NotificationCenter.default.removeObserver(observer)
                        }
                        self.AVCaptureDeviceSubjectAreaDidChangeObserver = NotificationCenter.default.addObserver(forName: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device, queue: .main) { notification in
                            self.subjectAreaDidChange(notification: notification as NSNotification)
                        }
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                        DispatchQueue.main.async {
                            self.createDeviceRotationCoordinator(videoDeviceInput: videoDeviceInput, videoPreviewLayer: videoPreviewLayer)
                        }
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }
                    if let connection = self.movieFileOutput?.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = captureVideoDevice.videoStabilizationMode
                        }
                    }
                    
                    /*
                     Set Live Photo capture and depth data delivery if it's supported. When changing cameras, the
                     `livePhotoCaptureEnabled` and `depthDataDeliveryEnabled` properties of the AVCapturePhotoOutput
                     get set to false when a video device is disconnected from the session. After the new video device is
                     added to the session, re-enable them on the AVCapturePhotoOutput, if supported.
                     */
                    self.photoOutput.isLivePhotoCaptureEnabled = self.photoOutput.isLivePhotoCaptureSupported
                    self.photoOutput.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
                    self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = self.photoOutput.isPortraitEffectsMatteDeliverySupported
                    self.photoOutput.enabledSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    let semanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                    
                    DispatchQueue.main.async {
                        self.controller.semanticSegmentationMatteTypes = semanticSegmentationMatteTypes
                    }
                    
                    self.session.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.videoDevice = captureVideoDevice
                self.isCameraChanging = false
            }
        }
    }
}

// MARK: - Chage CaptureMode

extension Camera {
    
    /// - Tag: EnableDisableModes
    public func change(captureMode: CaptureMode) {
        
        if self.captureMode == captureMode { return }
        
        sessionQueue.async {
            switch captureMode {
            case .photo(let configuration):
                // Remove the AVCaptureMovieFileOutput from the session because it doesn't support capture of Live Photos.
                self.session.beginConfiguration()
                if let movieFileOutput: AVCaptureMovieFileOutput = self.movieFileOutput {
                    self.session.removeOutput(movieFileOutput)
                    self.movieFileOutput = nil
                }
                self.session.sessionPreset = configuration.sessionPreset
                
                if self.photoOutput.isLivePhotoCaptureSupported {
                    self.photoOutput.isLivePhotoCaptureEnabled = true
                    
                    DispatchQueue.main.async {
                        self.controller.$livePhotoCaptureMode.isEnabled = true
                    }
                }
                if self.photoOutput.isDepthDataDeliverySupported {
                    self.photoOutput.isDepthDataDeliveryEnabled = true
                    
                    DispatchQueue.main.async {
                        self.controller.$depthDataDeliveryMode.isEnabled = true
                    }
                }
                
                if self.photoOutput.isPortraitEffectsMatteDeliverySupported {
                    self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = true
                    
                    DispatchQueue.main.async {
                        self.controller.$portraitEffectsMatteDeliveryMode.isEnabled = true
                    }
                }
                
                if !self.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty {
                    self.photoOutput.enabledSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    let semanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    
                    DispatchQueue.main.async {
                        self.controller.semanticSegmentationMatteTypes = semanticSegmentationMatteTypes
                        self.controller.$semanticSegmentationMatteTypes.isEnabled = (self.controller.depthDataDeliveryMode == .on) ? true : false
                    }
                }
                
                DispatchQueue.main.async {
                    self.captureMode = captureMode
                    self.controller.$livePhotoCaptureMode.isHidden = false
                    self.controller.$depthDataDeliveryMode.isHidden = false
                    self.controller.$portraitEffectsMatteDeliveryMode.isHidden = false
                    self.controller.$semanticSegmentationMatteTypes.isHidden = false
                    self.controller.$photoQualityPrioritizationMode.isHidden = false
                }
                self.session.commitConfiguration()
            case .movie(let configuration):
                let movieFileOutput: AVCaptureMovieFileOutput = AVCaptureMovieFileOutput()
                if self.session.canAddOutput(movieFileOutput) {
                    self.session.beginConfiguration()
                    self.session.addOutput(movieFileOutput)
                    self.session.sessionPreset = configuration.sessionPreset
                    if let connection = movieFileOutput.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    self.session.commitConfiguration()
                    self.movieFileOutput = movieFileOutput
                    
                    DispatchQueue.main.async {
                        self.captureMode = captureMode
                    }
                }
            }
        }
    }
    
    public func changeRamp(zoomRatio: CGFloat) {
        let zoomRatio = min(max(zoomRatio, 0), 1)
        
        sessionQueue.async {
            if self.videoDeviceInput == nil { return }
            let device: AVCaptureDevice = self.videoDeviceInput.device
            if device.isVirtualDevice {
                print("is Virtual Device")
            } else {
                let factor: CGFloat = device.minAvailableVideoZoomFactor + zoomRatio * (device.maxAvailableVideoZoomFactor - device.minAvailableVideoZoomFactor)
                do {
                    try device.lockForConfiguration()
                    device.ramp(toVideoZoomFactor: factor, withRate: 20.0)
                    device.unlockForConfiguration()
                } catch {
                    print("Could not change ramp: \(self.videoDeviceInput.device)")
                }
            }
        }
    }
}

extension Camera {
    
    /// - Tag: CapturePhoto
    public func capturePhoto(_ completion: ((CapturedPhoto) -> Void)? = nil) {
        /*
         Retrieve the video preview layer's video orientation on the main queue before
         entering the session queue. Do this to ensure that UI elements are accessed on
         the main thread and session configuration is done on the session queue.
         */
        
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoRotationAngle = self.getVideoRotationAngle(self.videoDeviceRotationCoordinator)
            }
            var photoSettings: AVCapturePhotoSettings = AVCapturePhotoSettings()
            
            // Capture HEIF photos when supported. Enable auto-flash and high-resolution photos.
            if  self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
            if self.videoDeviceInput.device.isFlashAvailable {
                photoSettings.flashMode = self.controller.flashMode
            }
            
            let maxDimensions = self.videoDeviceInput.device.activeFormat.supportedMaxPhotoDimensions
                .max(by: { $0.width * $0.height < $1.width * $1.height })
            
            photoSettings.maxPhotoDimensions = maxDimensions!
            
            if !photoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
            }
            // Live Photo capture is not supported in movie mode.
            if self.controller.livePhotoCaptureMode == .on && self.photoOutput.isLivePhotoCaptureSupported {
                let livePhotoMovieFileName = NSUUID().uuidString
                let livePhotoMovieFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((livePhotoMovieFileName as NSString).appendingPathExtension("mov")!)
                photoSettings.livePhotoMovieFileURL = URL(fileURLWithPath: livePhotoMovieFilePath)
            }
            
            photoSettings.isDepthDataDeliveryEnabled = (self.controller.depthDataDeliveryMode == .on && self.photoOutput.isDepthDataDeliveryEnabled)
            photoSettings.isPortraitEffectsMatteDeliveryEnabled = (self.controller.portraitEffectsMatteDeliveryMode == .on && self.photoOutput.isPortraitEffectsMatteDeliveryEnabled)
            
            if photoSettings.isDepthDataDeliveryEnabled {
                if !self.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty {
                    photoSettings.enabledSemanticSegmentationMatteTypes = self.controller.semanticSegmentationMatteTypes
                }
            }
            
            photoSettings.photoQualityPrioritization = self.controller.photoQualityPrioritizationMode
            
            let photoCaptureProcessor: PhotoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                // Flash the screen to signal that CameraUI took a photo.
                DispatchQueue.main.async {
                    self.previewView.videoPreviewLayer.opacity = 0
                    UIView.animate(withDuration: 0.25) {
                        self.previewView.videoPreviewLayer.opacity = 1
                    }
                }
            }, livePhotoCaptureHandler: { capturing in
                self.sessionQueue.async {
                    if capturing {
                        self.inProgressLivePhotoCapturesCount += 1
                    } else {
                        self.inProgressLivePhotoCapturesCount -= 1
                    }
                    
                    let inProgressLivePhotoCapturesCount = self.inProgressLivePhotoCapturesCount
                    DispatchQueue.main.async {
                        if inProgressLivePhotoCapturesCount > 0 {
                            self.isCapturingLivePhoto = true
                        } else if inProgressLivePhotoCapturesCount == 0 {
                            self.isCapturingLivePhoto = false
                        } else {
                            print("Error: In progress Live Photo capture count is less than 0.")
                        }
                    }
                }
            }, completionHandler: { photoCaptureProcessor in
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
            }, photoProcessingHandler: { isProcessing in
                DispatchQueue.main.async {
                    self.isPhotoProcessing = isProcessing
                }
            }) { capturedPhoto in
                DispatchQueue.main.async {
                    completion?(capturedPhoto)
                }
            }
            
            // The photo output holds a weak reference to the photo capture delegate and stores it in an array to maintain a strong reference.
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }
}

extension Camera {
    
    public func movieStartRecording(_ completion: ((CapturedVideo) -> Void)? = nil) {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        self.isMovieRecoding = true
        
        sessionQueue.async {
            if !movieFileOutput.isRecording {
                
                let fileOutputRecordingProcesser: FileOutputRecordingProcesser = FileOutputRecordingProcesser { fileOutputRecordingProcesser in
                    self.sessionQueue.async {
                        self.inProgressFileOutputRecodingDelegates[fileOutputRecordingProcesser.uniqueID] = nil
                    }
                } resourceHandler: { CapturedVideo in
                    DispatchQueue.main.async {
                        completion?(CapturedVideo)
                    }
                }
                
                if UIDevice.current.isMultitaskingSupported {
                    fileOutputRecordingProcesser.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                // Update the orientation on the movie file output video connection before recording.
                let movieFileOutputConnection: AVCaptureConnection? = movieFileOutput.connection(with: .video)
                movieFileOutputConnection?.videoRotationAngle = self.getVideoRotationAngle(self.videoDeviceRotationCoordinator)
                
                let availableVideoCodecTypes: [AVVideoCodecType] = movieFileOutput.availableVideoCodecTypes
                
                if availableVideoCodecTypes.contains(.hevc) {
                    movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
                }
                
                // Start recording video to a temporary file.
                let outputFileName: String = fileOutputRecordingProcesser.uniqueID
                let outputFilePath: String = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                self.inProgressFileOutputRecodingDelegates[fileOutputRecordingProcesser.uniqueID] = fileOutputRecordingProcesser
                movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: fileOutputRecordingProcesser)
            } else {
                movieFileOutput.stopRecording()
            }
        }
    }
    
    public func movieStopRecording() {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        sessionQueue.async {
            if movieFileOutput.isRecording {
                movieFileOutput.stopRecording()
            }
            DispatchQueue.main.async {
                self.isMovieRecoding = false
            }
        }
    }
}

extension Camera {
    final public class PreviewView: UIView {
        
        public override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
        
        public var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            guard let layer = layer as? AVCaptureVideoPreviewLayer else {
                fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check PreviewView.layerClass implementation.")
            }
            return layer
        }
        
        var videoGravity: AVLayerVideoGravity {
            get {
                return videoPreviewLayer.videoGravity
            }
            set {
                if videoPreviewLayer.videoGravity != newValue {
                    videoPreviewLayer.videoGravity = newValue
                }
            }
        }
        
        var session: AVCaptureSession? {
            get {
                return videoPreviewLayer.session
            }
            set {
                videoPreviewLayer.session = newValue
            }
        }
        
        public override func layoutSublayers(of layer: CALayer) {
            super.layoutSublayers(of: layer)
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        var uniqueDevicePositions: [AVCaptureDevice.Position] = []
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        return uniqueDevicePositions.count
    }
}
