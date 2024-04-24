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

    private let resourceHandler: (CapturedVideo) -> Void

    private var resource: CapturedVideo = CapturedVideo()

    public init(completionHandler: @escaping ((FileOutputRecordingProcesser) -> Void),
                resourceHandler: @escaping ((CapturedVideo) -> Void)) {
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
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    print("Could not remove file at url: \(outputFileURL)")
                }
            }
            
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = .invalid
                if currentBackgroundRecordingID != .invalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
            
            self.completionHandler(self)
        }
        
        var success = true
        if let error = error {
            print("Movie file finishing error: \(error)")
            success = ((error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
        }
        
        if success {
            resource.outputFileURL = outputFileURL
            
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = .invalid
                if currentBackgroundRecordingID != .invalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
            
            completionHandler(self)
            resourceHandler(resource)
        } else {
            cleanup()
        }
        
        print("Did finish recording.")
    }
}
