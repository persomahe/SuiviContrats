//
//  AppLaunchView.swift
//  SuiviContrats
//
//  Created by erwan mahe on 08/09/2026.
//

import SwiftUI

struct AppLaunchView: View {
    @ObservedObject var store: ContractStore
    @State private var showContent = false

    var body: some View {
        Group {
            if showContent {
                ContentView(store: store)
            } else {
                SplashView()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showContent = true
                }
            }
        }
    }
}

private struct SplashView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("fondPage")
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .clipped()

                Image("contractFolder")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260)
                    .offset(y: -60)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
        .ignoresSafeArea()
    }
}
