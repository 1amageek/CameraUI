//
//  ContentView.swift
//  Demo
//
//  Created by nori on 2021/02/07.
//

import SwiftUI
import CameraUI

struct ContentView: View {

    @ObservedObject var camera: Camera = Camera(captureMode: .movie)

    @GestureState var isDetectingTap = false

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
                    .onEnded { value in
                        print("DragGesture onEnded", isDetectingLongPress, value)
                        camera.movieStopRecording()
                    }
            )
    }

    var body: some View {
        ZStack {
            Color.black
            camera.view()
                .background(Color.red)
            VStack {
                Spacer()
                HStack {
                    Button(action: {
                        if camera.captureMode == .photo {
                            camera.changeCaptureMode(.movie)
                        } else {
                            camera.changeCaptureMode(.photo)
                        }
                    }) {
                        Image(systemName: camera.captureMode == .photo ? "video.fill" : "camera.fill")
                            .font(.system(size: 26))
                    }
                    .disabled(camera.isCameraChanging)
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
                        camera.changeCamera()
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
