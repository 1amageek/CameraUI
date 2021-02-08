//
//  PreviewView.swift
//  
//
//  Created by nori on 2021/02/06.
//

import SwiftUI
import UIKit
import AVFoundation

extension Camera.PreviewView: UIViewRepresentable {

    public func makeUIView(context: Context) -> Camera.PreviewView {
        return self
    }

    public func updateUIView(_ uiView: Camera.PreviewView, context: Context) { }
}

extension Camera {

    public func view(_ videoGravity: AVLayerVideoGravity = .resizeAspect) -> some View {
        self.previewView.videoGravity = videoGravity
        return self.previewView
            .onAppear { self.onAppear() }
            .onDisappear { self.onDisappear() }
    }
}


struct PreviewView_Previews: PreviewProvider {
    static var previews: some View {
        Camera().view()
    }
}
