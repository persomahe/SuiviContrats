//
//  BackgroundImage.swift
//  SuiviContrats
//
//  Created by automated edit on behalf of the user.
//

import SwiftUI

/// A reusable full-screen background image view.
/// Use this inside stacks as the background image. Caller may add `.ignoresSafeArea()` if desired.
struct BackgroundImage: View {
    let imageName: String

    var body: some View {
        GeometryReader { geometry in
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
    }
}
