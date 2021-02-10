//
//  FileOutputRecorder.swift
//  
//
//  Created by nori on 2021/02/08.
//

import AVFoundation
import Photos
import UIKit

public final class FileOutputRecordingProcesser: NSObject {

    public var backgroundRecordingID: UIBackgroundTaskIdentifier?

    public var uniqueID: String = UUID().uuidString

    private let completionHandler: (FileOutputRecordingProcesser) -> Void

    private let resourceHandler: (VideoResource) -> Void

    private var resource: VideoResource = VideoResource()

    public init(completionHandler: @escaping ((FileOutputRecordingProcesser) -> Void),
                resourceHandler: @escaping ((VideoResource) -> Void)) {
        self.completionHandler = completionHandler
        self.resourceHandler = resourceHandler
    }
}

extension FileOutputRecordingProcesser: AVCaptureFileOutputRecordingDelegate {

    public func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("Did start recording. fileURL: \(fileURL)")
    }

    public func fileOutput(_ output: AVCaptureFileOutput,
                           didFinishRecordingTo outputFileURL: URL,
                           from connections: [AVCaptureConnection],
                           error: Error?) {
        func cleanup() {
            let path: String = outputFileURL.path
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
            self.completionHandler(self)
        }

        var success: Bool = true

        if error != nil {
            print("Movie file finishing error: \(String(describing: error))")
            success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }

        if success {

            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskIdentifier.invalid

                if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
            completionHandler(self)
            resourceHandler(self.resource)
            


//            // Check the authorization status.
//            PHPhotoLibrary.requestAuthorization { status in
//                if status == .authorized {
//                    // Save the movie file to the photo library and cleanup.
//                    PHPhotoLibrary.shared().performChanges({
//                        let options = PHAssetResourceCreationOptions()
//                        options.shouldMoveFile = true
//                        let creationRequest = PHAssetCreationRequest.forAsset()
//                        creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
//                    }, completionHandler: { success, error in
//                        if !success {
//                            print("CameraUI couldn't save the movie to your photo library: \(String(describing: error))")
//                        }
//                        cleanup()
//                    })
//                } else {
//                    cleanup()
//                }
//            }
        } else {
            cleanup()
        }

        // Enable the Camera and Record buttons to let the user switch camera and start another recording.
        print("Did finish recording.")
    }

}
