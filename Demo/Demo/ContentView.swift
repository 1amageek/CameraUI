//
//  ContentView.swift
//  Demo
//
//  Created by nori on 2021/02/07.
//

import SwiftUI
import CameraUI

struct ContentView: View {

    @ObservedObject var camera: Camera = Camera(captureMode: .movie(.high))

    @GestureState var isDetectingLongPress = false

    var gesture: some Gesture {
        TapGesture()
            .onEnded { value in
                print("TapGesture onEnded", value)
                camera.capturePhoto()
            }
            .simultaneously(
                with:
                    LongPressGesture()
                    .onEnded { value in
                        print("LongPressGesture onEnded", value)
                        camera.movieStartRecording()
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
                    }
            )
    }

    var focus: some Gesture {
        DragGesture(minimumDistance: 0)
        .onEnded { value in
            print("DragGesture onEnded", isDetectingLongPress, value)
            camera.focusAndExposeTap(value.location)
        }
    }

    var body: some View {
        ZStack {
            camera.view()
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
                        .disabled(camera.isCameraChanging)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 4, antialiased: true)
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
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
