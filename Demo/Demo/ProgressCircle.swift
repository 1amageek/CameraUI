//
//  ProgressCircle.swift
//  Demo
//
//  Created by nori on 2021/02/08.
//

import SwiftUI

struct ProgressCircle: View {

    var progress: Float

    var lineWidth: CGFloat = 16

    var body: some View {
        Circle()
            .trim(from: 0.0, to: CGFloat(min(self.progress, 1.0)))
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .foregroundColor(Color.red)
            .rotationEffect(Angle(degrees: 270.0))
            .animation(.linear, value: self.progress)
    }
}

struct ProgressCircle_Previews: PreviewProvider {
    static var previews: some View {
        ProgressCircle(progress: 0.9, lineWidth: 10)
            .frame(width: 80, height: 80, alignment: .center)
    }
}
