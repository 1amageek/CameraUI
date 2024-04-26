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
    
    @StateObject var camera: Camera = Camera(captureMode: .photo(.high))
    
    @StateObject var snap: Snap = Snap()
    
    @StateObject var visionProcesser: VisionProcesser = VisionProcesser()
    
    @GestureState var isDetectingLongPress = false
    
    @State var progress: Float = 0
    
    var gesture: some Gesture {
        TapGesture()
            .onEnded { value in
                print("TapGesture onEnded", value)
//                camera.capturePhoto { resource in
//                    resource.createAsset()
//                }
                let photoOutput = camera.photoOutput
                camera.sessionQueue.async {
                    var photoSettings = AVCapturePhotoSettings(format: [kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)])
                    photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                    photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)]
                    let maxDimensions = camera.videoDeviceInput.device.activeFormat.supportedMaxPhotoDimensions
                        .max(by: { $0.width * $0.height < $1.width * $1.height })                    
                    photoSettings.maxPhotoDimensions = maxDimensions!
                    photoSettings.flashMode = .off
                    photoSettings.isDepthDataDeliveryEnabled = false
                    photoSettings.isPortraitEffectsMatteDeliveryEnabled = false
                    photoSettings.photoQualityPrioritization = .quality
                    photoOutput.capturePhoto(with: photoSettings, delegate: visionProcesser)
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
                .gesture(focus)
                .ignoresSafeArea(.all)
                .overlay {
                    GeometryReader { geometry in
                        if let observation = visionProcesser.observations.first {
                            let size = geometry.frame(in: .local).size
                            let topLeft = observation.topLeft.scaled(to: size)
                            let topRight = observation.topRight.scaled(to: size)
                            let bottomRight = observation.bottomRight.scaled(to: size)
                            let bottomLeft = observation.bottomLeft.scaled(to: size)
                            RoundedCornerRectangleShape(
                                topLeft: topLeft,
                                topRight: topRight,
                                bottomRight: bottomRight,
                                bottomLeft: bottomLeft,
                                cornerRadius: 20
                            )
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .animation(.spring, value: observation)
                            .id("document")
                        }
                    }
                }
            
            if let image = visionProcesser.preview {
                Image(uiImage: image)
                    .resizable()
                    .padding()
            }
            
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
    
    func convert(pointOfInterest: CGPoint, withinImageSize size: CGSize) -> CGPoint {
        
        let imageWidth = size.width
        let imageHeight = size.height
        
        // Begin with input rect.
        var point = pointOfInterest
        
        // Reposition origin.
        point.x *= imageWidth
        point.y = (1 - imageHeight) * imageHeight
                
        return point
    }
}

struct RoundedCornerRectangleShape: Shape {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint
    var cornerRadius: CGFloat
    var stretch: CGFloat = 8
    
    var animatableData: AnimatablePair<AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>, AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>> {
        get {
            AnimatablePair(
                AnimatablePair(topLeft.animatableData, topRight.animatableData),
                AnimatablePair(bottomRight.animatableData, bottomLeft.animatableData)
            )
        }
        set {
            topLeft.animatableData = newValue.first.first
            topRight.animatableData = newValue.first.second
            bottomRight.animatableData = newValue.second.first
            bottomLeft.animatableData = newValue.second.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Start at the top-left corner
        path.move(to: CGPoint(x: topLeft.x - cornerRadius, y: topLeft.y + stretch))
        path.addArc(center: CGPoint(x: topLeft.x, y: topLeft.y),
                    radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: topLeft.x + stretch, y: topLeft.y - cornerRadius))
        
        path.move(to: CGPoint(x: topRight.x - stretch, y: topRight.y - cornerRadius))
        path.addArc(center: CGPoint(x: topRight.x, y: topRight.y),
                    radius: cornerRadius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: topRight.x + cornerRadius, y: topRight.y + stretch))
        
        path.move(to: CGPoint(x: bottomRight.x + cornerRadius, y: bottomRight.y - stretch))
        path.addArc(center: CGPoint(x: bottomRight.x, y: bottomRight.y),
                    radius: cornerRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: bottomRight.x - stretch, y: bottomRight.y + cornerRadius))
        
        path.move(to: CGPoint(x: bottomLeft.x + stretch, y: bottomLeft.y + cornerRadius))
        path.addArc(center: CGPoint(x: bottomLeft.x, y: bottomLeft.y),
                    radius: cornerRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: bottomLeft.x - cornerRadius, y: bottomLeft.y - stretch))
        return path
    }
}

extension CGPoint {
    func scaled(to size: CGSize) -> CGPoint {
        return CGPoint(x: self.x * size.width, y: (1 - self.y) * size.height)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
