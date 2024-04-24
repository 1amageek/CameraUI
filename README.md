# CameraUI

CameraUI is a library that simplifies the use of AVFoundation with SwiftUI, making it easier to incorporate advanced camera functionalities into iOS applications.

## Overview

CameraUI is designed to allow developers to easily integrate sophisticated camera capabilities such as photo capture and video recording into their SwiftUI applications. This library minimizes the complexity of interfacing directly with AVFoundation, providing straightforward APIs to manage camera operations.

## Motivation

Implementing camera functionality in iOS applications often requires intricate handling of AVFoundation, which can be time-consuming and complex. CameraUI streamlines this process, enabling developers using SwiftUI to incorporate camera features with minimal hassle and less code.

## Key Features

- **Photo Capture**: Support for capturing photos through a simple tap gesture.
- **Video Recording**: Start and stop video recording with a long press.
- **Zoom Adjustment**: Adjust camera zoom via drag gestures.
- **Focus and Exposure Adjustment**: Set camera focus and exposure based on the tap location.

## Installation

Currently, CameraUI can be integrated by directly adding the source code to your project. Future distributions might include support through Swift Package Manager.

1. Clone or download this repository.
2. Drag and drop the `CameraUI` directory into your project.
3. Add `import CameraUI` as needed to start using the library.

## Demo

The following sample code demonstrates how to set up a camera view using CameraUI and perform basic camera operations:

```swift
import SwiftUI
import CameraUI

struct ContentView: View {
    @ObservedObject var camera: Camera = Camera(captureMode: .movie(.high))
    
    var body: some View {
        ZStack {
            camera.view()
                .ignoresSafeArea(.all)
            // Additional UI components
        }
    }
}
```
