//
//  CaptureProcesser.swift
//  Ouchino
//
//  Created by Norikazu Muramoto on 2024/04/26.
//

import SwiftUI
import AVFoundation
import Vision
import CoreImage
import CameraUI


public class VisionProcesser: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var visionRequests: [VNRequest] = []
    
    @Published var preview: UIImage? = nil
    
    @Published var imageRect: CGRect = .zero
    
    @Published var observations: [VNRectangleObservation] = []
    
    public func configureSession(with session: AVCaptureSession) {
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoDataOutputQueue"))
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            if let connection = videoDataOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
        }
    }
    
    private var lastAnalysisTime: TimeInterval = 0
    
    private let analysisInterval: TimeInterval = 0.3
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastAnalysisTime >= analysisInterval else { return }
        lastAnalysisTime = currentTime
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
        let requestHandler = VNImageRequestHandler(ciImage: inputImage, orientation: .up)
        let documentDetectionRequest = VNDetectDocumentSegmentationRequest()
        do {
            try requestHandler.perform([documentDetectionRequest])
            guard
                let observations: [VNRectangleObservation] = documentDetectionRequest.results,
                let document = observations.filter({ observation in
                    observation.confidence > 0.8
                }).first else {
                DispatchQueue.main.async {
                    self.imageRect = inputImage.extent
                    self.observations = []
                }
                return
            }
            DispatchQueue.main.async {
                withAnimation {
                    self.imageRect = inputImage.extent
                    self.observations = [document]
                }
            }

        } catch let error {
            print("Error processing image: \(error.localizedDescription)")
        }
    }
    
    private func getDocumentImage(ciImage: CIImage) -> UIImage? {
        let size = ciImage.extent.size
        let request = VNDetectRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        try! handler.perform([request])
        guard let result = request.results?.first else { return nil }
            
        let topLeft = CGPoint(x: result.topLeft.x, y: 1-result.topLeft.y)
        let topRight = CGPoint(x: result.topRight.x, y: 1-result.topRight.y)
        let bottomLeft = CGPoint(x: result.bottomLeft.x, y: 1-result.bottomLeft.y)
        let bottomRight = CGPoint(x: result.bottomRight.x, y: 1-result.bottomRight.y)

        let deNormalizedTopLeft = VNImagePointForNormalizedPoint(topLeft, Int(size.width), Int(size.height))
        let deNormalizedTopRight = VNImagePointForNormalizedPoint(topRight, Int(size.width), Int(size.height))
        let deNormalizedBottomLeft = VNImagePointForNormalizedPoint(bottomLeft, Int(size.width), Int(size.height))
        let deNormalizedBottomRight = VNImagePointForNormalizedPoint(bottomRight, Int(size.width), Int(size.height))

        let croppedImage = getCroppedImage(image: ciImage, topL: deNormalizedTopLeft, topR: deNormalizedTopRight, botL: deNormalizedBottomLeft, botR: deNormalizedBottomRight)
        let context = CIContext(options: nil)
        let safeCGImage = context.createCGImage(croppedImage, from: croppedImage.extent)
        let croppedUIImage = UIImage(cgImage: safeCGImage!, scale: 1, orientation: .up)
        return croppedUIImage
    }

    private func getCroppedImage(image: CIImage, topL: CGPoint, topR: CGPoint, botL: CGPoint, botR: CGPoint) -> CIImage {
        let rectCoords = NSMutableDictionary(capacity: 4)
        rectCoords["inputTopLeft"] = topL.toVector(image: image)
        rectCoords["inputTopRight"] = topR.toVector(image: image)
        rectCoords["inputBottomLeft"] = botL.toVector(image: image)
        rectCoords["inputBottomRight"] = botR.toVector(image: image)
        guard let coords = rectCoords as? [String : Any] else {
            return image
        }
        return image.applyingFilter("CIPerspectiveCorrection", parameters: coords)
    }
}

extension CGPoint {
    func toVector(image: CIImage) -> CIVector {
        return CIVector(x: x, y: image.extent.height-y)
    }
}

extension VisionProcesser: AVCapturePhotoCaptureDelegate {
    
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        if let error = error {
            print("Error didFinishProcessingPhoto: \(error)")
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            return
        }
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return
        }
        guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return
        }
        let orientationValue = imageProperties[kCGImagePropertyOrientation] as? UInt32 ?? UInt32(CGImagePropertyOrientation.up.rawValue)
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue)!
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return
        }
        let ciImage = CIImage(cgImage: cgImage).oriented(forExifOrientation: Int32(orientation.rawValue))
        DispatchQueue.main.async {
            self.preview = self.getDocumentImage(ciImage: ciImage)
        }
    }
}
