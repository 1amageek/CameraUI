//
//  PreviewView.swift
//  
//
//  Created by nori on 2021/02/06.
//

import SwiftUI
import AVFoundation

extension Camera {
    
    struct _PreviewView: UIViewRepresentable {

        typealias UIViewType = Camera.PreviewView
        
        var uiView: Camera.PreviewView
        
        init(_ uiView: Camera.PreviewView) {
            self.uiView = uiView
        }
        
        func makeUIView(context: Context) -> Camera.PreviewView {
            uiView
        }
        
        func updateUIView(_ uiView: Camera.PreviewView, context: Context) {
            
        }
    }

    public func view(_ videoGravity: AVLayerVideoGravity = .resizeAspect) -> some View {
        self.previewView.videoGravity = videoGravity
        return _PreviewView(self.previewView)
            .onAppear { self.onAppear() }
            .onDisappear { self.onDisappear() }
    }
}

#Preview {
    Camera().view()
}
