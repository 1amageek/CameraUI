//
//  Resource.swift
//  
//
//  Created by nori on 2021/02/10.
//

import Foundation
import Photos

public struct CapturedVideo {

    public var outputFileURL: URL?

    public func createAsset() {

        guard let outputFileURL: URL = self.outputFileURL else { return }

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
                    self.delete()
                })
            }
        }
    }

    public func delete() {
        if let path: String = self.outputFileURL?.path {
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    print("Could not remove file at url: \(path)")
                }
            }
        }
    }
}
