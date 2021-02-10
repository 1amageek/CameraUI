//
//  Resource.swift
//  
//
//  Created by nori on 2021/02/10.
//

import Foundation
import Photos

public struct PhotoResource {

    public var uniformTypeIdentifier: String?

    public var photoData: Data?

    public var livePhotoCompanionMovieURL: URL?

    public var portraitEffectsMatteData: Data?

    public var semanticSegmentationMatteDataArray: [Data] = []

    public func createAsset() {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    let options: PHAssetResourceCreationOptions = PHAssetResourceCreationOptions()
                    let creationRequest: PHAssetCreationRequest = PHAssetCreationRequest.forAsset()
                    options.uniformTypeIdentifier = self.uniformTypeIdentifier

                    if let photoData: Data = self.photoData {
                        creationRequest.addResource(with: .photo, data: photoData, options: options)
                    }

                    if let livePhotoCompanionMovieURL: URL = self.livePhotoCompanionMovieURL {
                        let livePhotoCompanionMovieFileOptions: PHAssetResourceCreationOptions = PHAssetResourceCreationOptions()
                        livePhotoCompanionMovieFileOptions.shouldMoveFile = true
                        creationRequest.addResource(with: .pairedVideo,
                                                    fileURL: livePhotoCompanionMovieURL,
                                                    options: livePhotoCompanionMovieFileOptions)
                    }

                    // Save Portrait Effects Matte to Photos Library only if it was generated
                    if let portraitEffectsMatteData: Data = self.portraitEffectsMatteData {
                        let creationRequest: PHAssetCreationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .photo,
                                                    data: portraitEffectsMatteData,
                                                    options: nil)
                    }
                    // Save Portrait Effects Matte to Photos Library only if it was generated
                    for semanticSegmentationMatteData: Data in self.semanticSegmentationMatteDataArray {
                        let creationRequest: PHAssetCreationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .photo,
                                                    data: semanticSegmentationMatteData,
                                                    options: nil)
                    }
                }, completionHandler: { _, error in
                    if let error = error {
                        print("Error occurred while saving photo to photo library: \(error)")
                    }
                    self.delete()
                })
            }
        }
    }

    public func delete() {
        if let path: String = self.livePhotoCompanionMovieURL?.path {
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

public struct VideoResource {

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
