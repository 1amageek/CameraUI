//
//  File.swift
//  
//
//  Created by nori on 2021/02/06.
//

import UIKit
import Foundation
import AVFoundation
import Photos

public class Camera: NSObject, ObservableObject {

    public enum CaptureMode {
        case photo
        case movie
    }

    public enum LivePhotoMode {
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

    private let session: AVCaptureSession = AVCaptureSession()

    private var isSessionRunning: Bool = false

    private var selectedSemanticSegmentationMatteTypes: [AVSemanticSegmentationMatte.MatteType] = []

    // Communicate with the session and other session objects on this queue.
    private let sessionQueue: DispatchQueue = DispatchQueue(label: "queue.session.CameraUI")

    private var setupResult: SessionSetupResult = .success

    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!

    // MARK: Device Configuration

    private let videoDeviceDiscoverySession = AVCaptureDevice
        .DiscoverySession(deviceTypes: [
            .builtInWideAngleCamera,
            .builtInDualCamera,
            .builtInTrueDepthCamera
        ],
        mediaType: .video, position: .unspecified)

    // MARK: Mode

    @Published public private(set) var isEnabled: Bool = false

    @Published public private(set) var captureMode: CaptureMode = .photo

    @Published public var flashMode: AVCaptureDevice.FlashMode = .auto

    @Published public var livePhotoMode: LivePhotoMode = .on

    @Published public var depthDataDeliveryMode: DepthDataDeliveryMode = .on

    @Published public var portraitEffectsMatteDeliveryMode: PortraitEffectsMatteDeliveryMode = .on

    @Published public var photoQualityPrioritizationMode: AVCapturePhotoOutput.QualityPrioritization = .balanced

    @Published public private(set) var deviceOrientation: UIDeviceOrientation = UIDevice.current.orientation

    // MARK: State

    @Published public private(set) var isCapturingLivePhoto: Bool = false

    @Published public private(set) var isPhotoProcessing: Bool = false

    @Published public private(set) var isCameraChanging: Bool = false

    // MARK: Preview

    let previewView: PreviewView = PreviewView()

    // MARK: Capturing Photos

    private let photoOutput: AVCapturePhotoOutput = AVCapturePhotoOutput()

    private var inProgressPhotoCaptureDelegates: [Int64: PhotoCaptureProcessor] = [:]

    fileprivate var inProgressLivePhotoCapturesCount = 0

    // MARK: Recording Movies

    private var movieFileOutput: AVCaptureMovieFileOutput?

    private var backgroundRecordingID: UIBackgroundTaskIdentifier?

    public override init() {
        super.init()
        previewView.session = session
        boot()
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
        sessionQueue.async {
            self.configureSession()
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
                        let changePrivacySetting = "CameraUI doesn't have permission to use the camera, please change privacy settings"
                        let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                        let alertController = UIAlertController(title: "CameraUI", message: message, preferredStyle: .alert)

                        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                                style: .cancel,
                                                                handler: nil))

                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                                style: .`default`,
                                                                handler: { _ in
                                                                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                              options: [:],
                                                                                              completionHandler: nil)
                                                                }))

                        //                    self.present(alertController, animated: true, completion: nil)
                    }

                case .configurationFailed:
                    DispatchQueue.main.async {
                        let alertMsg = "Alert message when something goes wrong during capture session configuration"
                        let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                        let alertController = UIAlertController(title: "CameraUI", message: message, preferredStyle: .alert)

                        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                                style: .cancel,
                                                                handler: nil))

                        //                    self.present(alertController, animated: true, completion: nil)
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


    // Call this on the session queue.
    /// - Tag: ConfigureSession
    private func configureSession() {
        if setupResult != .success {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?

            // Choose the back dual camera, if available, otherwise default to a wide angle camera.

            if let dualCameraDevice: AVCaptureDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let backCameraDevice: AVCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                // If a rear dual camera is not available, default to the rear wide angle camera.
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice: AVCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                // If the rear wide angle camera isn't available, default to the front wide angle camera.
                defaultVideoDevice = frontCameraDevice
            }
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput

                DispatchQueue.main.async {
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if let videoOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) {
                        initialVideoOrientation = videoOrientation
                    }
                    self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
                }
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        // Add an audio input device.
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)

            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
            }
        } catch {
            print("Could not create audio device input: \(error)")
        }

        // Add the photo output.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)

            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
            photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
            photoOutput.enabledSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
            selectedSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
            photoOutput.maxPhotoQualityPrioritization = .quality
            DispatchQueue.main.async {
                self.livePhotoMode = self.photoOutput.isLivePhotoCaptureSupported ? .on : .off
                self.depthDataDeliveryMode = self.photoOutput.isDepthDataDeliverySupported ? .on : .off
                self.portraitEffectsMatteDeliveryMode = self.photoOutput.isPortraitEffectsMatteDeliverySupported ? .on : .off
                self.photoQualityPrioritizationMode = .balanced
            }

        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()
    }

    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
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
//            let isLivePhotoCaptureEnabled = self.photoOutput.isLivePhotoCaptureEnabled
//            let isDepthDeliveryDataEnabled = self.photoOutput.isDepthDataDeliveryEnabled
//            let isPortraitEffectsMatteEnabled = self.photoOutput.isPortraitEffectsMatteDeliveryEnabled
//            let isSemanticSegmentationMatteEnabled = !self.photoOutput.enabledSemanticSegmentationMatteTypes.isEmpty

            DispatchQueue.main.async {
                self.isEnabled = isSessionRunning
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
            /*
             In some scenarios you want to enable the user to resume the session.
             For example, if music playback is initiated from Control Center while
             using CameraUI, then the user can let CameraUI resume
             the session running, which will stop music playback. Note that stopping
             music playback in Control Center will not automatically resume the session.
             Also note that it's not always possible to resume, see `resumeInterruptedSession(_:)`.
             */
            if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
               let reasonIntegerValue = userInfoValue.integerValue,
               let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
                print("Capture session was interrupted with reason \(reason)")


            }
        }

        AVCaptureSessionInterruptionEndedObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { notification in
            print("Capture session interruption ended")

            //            if !resumeButton.isHidden {
            //                UIView.animate(withDuration: 0.25,
            //                               animations: {
            //                                self.resumeButton.alpha = 0
            //                }, completion: { _ in
            //                    self.resumeButton.isHidden = true
            //                })
            //            }
            //            if !cameraUnavailableLabel.isHidden {
            //                UIView.animate(withDuration: 0.25,
            //                               animations: {
            //                                self.cameraUnavailableLabel.alpha = 0
            //                }, completion: { _ in
            //                    self.cameraUnavailableLabel.isHidden = true
            //                }
            //                )
            //            }
        }
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)

        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
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

extension Camera {

    /// - Tag: ChangeCamera
    public func changeCamera() {
        self.isCameraChanging = true
        sessionQueue.async {
            let currentVideoDevice: AVCaptureDevice = self.videoDeviceInput.device
            let currentPosition: AVCaptureDevice.Position = currentVideoDevice.position

            let preferredPosition: AVCaptureDevice.Position
            let preferredDeviceType: AVCaptureDevice.DeviceType

            switch currentPosition {
            case .unspecified, .front:
                preferredPosition = .back
                preferredDeviceType = .builtInDualCamera

            case .back:
                preferredPosition = .front
                preferredDeviceType = .builtInTrueDepthCamera

            @unknown default:
                print("Unknown capture position. Defaulting to back, dual-camera.")
                preferredPosition = .back
                preferredDeviceType = .builtInDualCamera
            }
            let devices = self.videoDeviceDiscoverySession.devices
            var newVideoDevice: AVCaptureDevice? = nil

            // First, seek a device with both the preferred position and device type. Otherwise, seek a device with only the preferred position.
            if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
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
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }
                    if let connection = self.movieFileOutput?.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
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
                    self.selectedSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    self.photoOutput.maxPhotoQualityPrioritization = .quality

                    self.session.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }

            DispatchQueue.main.async {
                self.isCameraChanging = false
            }
        }
    }
}

extension Camera {
    /// - Tag: EnableDisableModes
    public func changeCaptureMode(_ captureMode: CaptureMode) {

        if self.captureMode == captureMode { return }

        switch captureMode {
            case .photo:

                sessionQueue.async {
                    // Remove the AVCaptureMovieFileOutput from the session because it doesn't support capture of Live Photos.
                    self.session.beginConfiguration()
                    self.session.removeOutput(self.movieFileOutput!)
                    self.session.sessionPreset = .photo

                    self.movieFileOutput = nil

                    if self.photoOutput.isLivePhotoCaptureSupported {
                        self.photoOutput.isLivePhotoCaptureEnabled = true

                        DispatchQueue.main.async {
//                            self.livePhotoModeButton.isEnabled = true
                        }
                    }

                    if self.photoOutput.isDepthDataDeliverySupported {
                        self.photoOutput.isDepthDataDeliveryEnabled = true

                        DispatchQueue.main.async {
//                            self.depthDataDeliveryButton.isEnabled = true
                        }
                    }

                    if self.photoOutput.isPortraitEffectsMatteDeliverySupported {
                        self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = true

                        DispatchQueue.main.async {
//                            self.portraitEffectsMatteDeliveryButton.isEnabled = true
                        }
                    }

                    if !self.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty {
                        self.photoOutput.enabledSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                        self.selectedSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes

                        DispatchQueue.main.async {
//                            self.semanticSegmentationMatteDeliveryButton.isEnabled = (self.depthDataDeliveryMode == .on) ? true : false
                        }
                    }

                    DispatchQueue.main.async {
                        self.captureMode = .photo
    //                    self.livePhotoModeButton.isHidden = false
    //                    self.depthDataDeliveryButton.isHidden = false
    //                    self.portraitEffectsMatteDeliveryButton.isHidden = false
    //                    self.semanticSegmentationMatteDeliveryButton.isHidden = false
    //                    self.photoQualityPrioritizationSegControl.isHidden = false
    //                    self.photoQualityPrioritizationSegControl.isEnabled = true
                    }
                    self.session.commitConfiguration()
                }

            case .movie:
                sessionQueue.async {
                    let movieFileOutput: AVCaptureMovieFileOutput = AVCaptureMovieFileOutput()
                    if self.session.canAddOutput(movieFileOutput) {
                        self.session.beginConfiguration()
                        self.session.addOutput(movieFileOutput)
                        self.session.sessionPreset = .high
                        if let connection = movieFileOutput.connection(with: .video) {
                            if connection.isVideoStabilizationSupported {
                                connection.preferredVideoStabilizationMode = .auto
                            }
                        }
                        self.session.commitConfiguration()
                        self.movieFileOutput = movieFileOutput

                        DispatchQueue.main.async {
                            self.captureMode = .movie
    //                        self.recordButton.isEnabled = true

                            /*
                             For photo captures during movie recording, Speed quality photo processing is prioritized
                             to avoid frame drops during recording.
                             */
    //                        self.photoQualityPrioritizationSegControl.selectedSegmentIndex = 0
    //                        self.photoQualityPrioritizationSegControl.sendActions(for: UIControl.Event.valueChanged)
                        }
                    }
                }
        }
    }

    public func changeFlashMode(_ flashMode: AVCaptureDevice.FlashMode) {
        if self.flashMode == flashMode { return }
        self.flashMode = flashMode
    }

    public func changeDepthDataDeliveryMode(_ depthDataDeliveryMode: DepthDataDeliveryMode) {
        if self.depthDataDeliveryMode == depthDataDeliveryMode { return }
        self.depthDataDeliveryMode = depthDataDeliveryMode
    }

    public func changePortraitEffectsMatteDeliveryMode(_ portraitEffectsMatteDeliveryMode: PortraitEffectsMatteDeliveryMode) {
        if self.portraitEffectsMatteDeliveryMode == portraitEffectsMatteDeliveryMode { return }
        self.portraitEffectsMatteDeliveryMode = portraitEffectsMatteDeliveryMode
    }

    public func changePhotoQualityPrioritizationMode(_ photoQualityPrioritizationMode: AVCapturePhotoOutput.QualityPrioritization) {
        if self.photoQualityPrioritizationMode == photoQualityPrioritizationMode { return }
        self.photoQualityPrioritizationMode = photoQualityPrioritizationMode
    }

}

extension Camera {

    /// - Tag: CapturePhoto
    public func capturePhoto() {
        /*
         Retrieve the video preview layer's video orientation on the main queue before
         entering the session queue. Do this to ensure that UI elements are accessed on
         the main thread and session configuration is done on the session queue.
         */
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation

        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            var photoSettings: AVCapturePhotoSettings = AVCapturePhotoSettings()

            // Capture HEIF photos when supported. Enable auto-flash and high-resolution photos.
            if  self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }

            if self.videoDeviceInput.device.isFlashAvailable {
                photoSettings.flashMode = self.flashMode
            }

            photoSettings.isHighResolutionPhotoEnabled = true
            if !photoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
            }
            // Live Photo capture is not supported in movie mode.
            if self.livePhotoMode == .on && self.photoOutput.isLivePhotoCaptureSupported {
                let livePhotoMovieFileName = NSUUID().uuidString
                let livePhotoMovieFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((livePhotoMovieFileName as NSString).appendingPathExtension("mov")!)
                photoSettings.livePhotoMovieFileURL = URL(fileURLWithPath: livePhotoMovieFilePath)
            }

            photoSettings.isDepthDataDeliveryEnabled = (self.depthDataDeliveryMode == .on && self.photoOutput.isDepthDataDeliveryEnabled)
            photoSettings.isPortraitEffectsMatteDeliveryEnabled = (self.portraitEffectsMatteDeliveryMode == .on && self.photoOutput.isPortraitEffectsMatteDeliveryEnabled)

            if photoSettings.isDepthDataDeliveryEnabled {
                if !self.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty {
                    photoSettings.enabledSemanticSegmentationMatteTypes = self.selectedSemanticSegmentationMatteTypes
                }
            }

            photoSettings.photoQualityPrioritization = self.photoQualityPrioritizationMode

            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
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
            })

            // The photo output holds a weak reference to the photo capture delegate and stores it in an array to maintain a strong reference.
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }
}

extension Camera {

    public func movieStartRecording() {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        /*
         Disable the Camera button until recording finishes, and disable
         the Record button until recording starts or finishes.

         See the AVCaptureFileOutputRecordingDelegate methods.
         */
        let videoPreviewLayerOrientation: AVCaptureVideoOrientation? = previewView.videoPreviewLayer.connection?.videoOrientation

        sessionQueue.async {
            if !movieFileOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }

                // Update the orientation on the movie file output video connection before recording.
                let movieFileOutputConnection: AVCaptureConnection? = movieFileOutput.connection(with: .video)
                movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation!

                let availableVideoCodecTypes: [AVVideoCodecType] = movieFileOutput.availableVideoCodecTypes

                if availableVideoCodecTypes.contains(.hevc) {
                    movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
                }

                // Start recording video to a temporary file.
                let outputFileName: String = NSUUID().uuidString
                let outputFilePath: String = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
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
        }
    }
}

extension Camera: AVCaptureFileOutputRecordingDelegate {

    /// - Tag: DidStartRecording
    public func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Enable the Record button to let the user stop recording.
        DispatchQueue.main.async {
//            self.recordButton.isEnabled = true
//            self.recordButton.setImage(#imageLiteral(resourceName: "CaptureStop"), for: [])
        }
    }

    /// - Tag: DidFinishRecording
    public func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // Note: Because we use a unique file path for each recording, a new recording won't overwrite a recording mid-save.
        func cleanup() {
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    print("Could not remove file at url: \(outputFileURL)")
                }
            }

            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskIdentifier.invalid

                if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }

        var success: Bool = true

        if error != nil {
            print("Movie file finishing error: \(String(describing: error))")
            success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }

        if success {
            // Check the authorization status.
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Save the movie file to the photo library and cleanup.
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                    }, completionHandler: { success, error in
                        if !success {
                            print("CameraUI couldn't save the movie to your photo library: \(String(describing: error))")
                        }
                        cleanup()
                    })
                } else {
                    cleanup()
                }
            }
        } else {
            cleanup()
        }

        // Enable the Camera and Record buttons to let the user switch camera and start another recording.
        DispatchQueue.main.async {
            // Only enable the ability to change camera if the device has more than one camera.
//            self.cameraButton.isEnabled = self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
//            self.recordButton.isEnabled = true
//            self.captureModeControl.isEnabled = true
//            self.recordButton.setImage(#imageLiteral(resourceName: "CaptureVideo"), for: [])
        }
    }

}

extension Camera {
    final class PreviewView: UIView {

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            guard let layer = layer as? AVCaptureVideoPreviewLayer else {
                fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check PreviewView.layerClass implementation.")
            }
            return layer
        }

        var session: AVCaptureSession? {
            get {
                return videoPreviewLayer.session
            }
            set {
                videoPreviewLayer.session = newValue
            }
        }

        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
    }
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
            case .portrait: self = .portrait
            case .portraitUpsideDown: self = .portraitUpsideDown
            case .landscapeLeft: self = .landscapeRight
            case .landscapeRight: self = .landscapeLeft
            default: return nil
        }
    }

    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
            case .portrait: self = .portrait
            case .portraitUpsideDown: self = .portraitUpsideDown
            case .landscapeLeft: self = .landscapeLeft
            case .landscapeRight: self = .landscapeRight
            default: return nil
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {

        var uniqueDevicePositions = [AVCaptureDevice.Position]()

        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }

        return uniqueDevicePositions.count
    }
}
