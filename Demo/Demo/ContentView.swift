//
//  ContentView.swift
//  Demo
//
//  Created by nori on 2021/02/07.
//

import SwiftUI
import CameraUI
import Photos
import Vision

struct ContentView: View {
    
    @StateObject var camera: Camera = Camera(captureMode: .movie(.init(sessionPreset: .high, angleMode: .fixed(.portrait))))
    
    @StateObject var snap: Snap = Snap()
    
    @StateObject var visionProcesser: VisionProcesser = VisionProcesser()
    
    @GestureState var isDetectingLongPress = false
    
    @State var progress: Float = 0
    
    var gesture: some Gesture {
        TapGesture()
            .onEnded { value in
                print("TapGesture onEnded", value)
                camera.capturePhoto { resource in
                    resource.createAsset()
                }
            }
            .simultaneously(
                with:
                    LongPressGesture()
                    .onEnded { value in
                        print("LongPressGesture onEnded", value)
                        camera.movieStartRecording { resource in
                            resource.createAsset()
                        }
                        snap.start()
                    }
            )
            .simultaneously(
                with:
                    DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let zoom = max(value.startLocation.y - value.location.y, 0) / 350
                        print("DragGesture onChanged", zoom)
                        camera.changeRamp(zoomRatio: zoom)
                    }
                    .onEnded { value in
                        print("DragGesture onEnded", isDetectingLongPress, value)
                        camera.movieStopRecording()
                        snap.stop()
                    }
            )
    }
    
    var focus: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                camera.focusAndExposeTap(value.location)
            }
    }
    
    var body: some View {
        ZStack {
            camera.view()
                .ignoresSafeArea(.all)
                .background(Color.red)
                .gesture(focus)
            VStack {
                Spacer()
                HStack {
                    Button(action: {
                        if case .photo(_) = camera.captureMode {
                            camera.change(captureMode: .movie(.high))
                        } else {
                            camera.change(captureMode: .photo(.photo))
                        }
                    }) {
                        Group {
                            if case .photo(_) = camera.captureMode {
                                Image(systemName: "video.fill")                                
                            } else {
                                Image(systemName: "camera.fill")
                            }
                        }
                        .font(.system(size: 26))
                        .disabled(camera.isCameraChanging || camera.isMovieRecoding)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 4, antialiased: true)
                            .frame(width: 70, height: 70, alignment: .center)
                        ProgressCircle(progress: Float(snap.duration) / 10, lineWidth: 4)
                            .frame(width: 70, height: 70, alignment: .center)
                        Circle()
                            .foregroundColor(isDetectingLongPress ? Color.white.opacity(0.8) : .white)
                            .frame(width: 58, height: 58, alignment: .center)
                            .gesture(gesture)
                        
                    }
                    Spacer()
                    Button(action: {
                        if case .front(_) = camera.videoDevice {
                            camera.change(captureVideoDevice: .back())
                        } else {
                            camera.change(captureVideoDevice: .front())
                        }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 26))
                    }
                    .disabled(camera.isCameraChanging)
                }
                .accentColor(.white)
            }.padding()
        }
        .onAppear {
            visionProcesser.configureSession(with: camera.session)
        }
    }
}

class VisionProcesser: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var visionRequests: [VNRequest] = []
    
    var detectedDocumentRect: CGRect = .zero
    
    var rectangles: [VNRectangleObservation] = []
    
    func configureSession(with session: AVCaptureSession) {
        let videoDataOutput = AVCaptureVideoDataOutput()
        if let photoOutputConnection = videoDataOutput.connection(with: .video) {
            photoOutputConnection.videoRotationAngle = 90
        }
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
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
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
                return
            }
            print("width: \(inputImage.extent.width) height: \(inputImage.extent.height)")
        } catch let error {
            print("Error processing image: \(error.localizedDescription)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
