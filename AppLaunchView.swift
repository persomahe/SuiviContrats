//
//  AppLaunchView.swift
//  SuiviContrats
//
//  Created by erwan mahe on 08/09/2026.
//

import SwiftUI

struct AppLaunchView: View {
    @State private var showContent = false

    var body: some View {
        Group {
            if showContent {
                ContentView()
            } else {
                SplashView()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showContent = true
                }
            }
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            // Bulles colorées en arrière-plan
            Circle()
                .fill(Color.green)
                .frame(width: 280, height: 280)
                .offset(x: -160, y: -300)

            Circle()
                .fill(Color.blue)
                .frame(width: 180, height: 180)
                .offset(x: 100, y: -220)

            Circle()
                .fill(Color.orange)
                .frame(width: 260, height: 260)
                .offset(x: 130, y: 230)

            Circle()
                .fill(Color.purple)
                .frame(width: 150, height: 150)
                .offset(x: -130, y: 250)

            Circle()
                .fill(Color.pink)
                .frame(width: 110, height: 110)
                .offset(x: 20, y: 80)

            Circle()
                .stroke(Color.white, lineWidth: 5)
                .offset(x: 80, y: 140)
            
            Circle()
                .stroke(Color.white, lineWidth: 5)
                .offset(x: -180, y: -100)
            
            Circle()
                .stroke(Color.white, lineWidth: 5)
                .offset(x: 260, y: -300)
            
            Circle()
                .fill(Color.indigo)
                .frame(width: 110, height: 110)
                .offset(x: -120, y: 40)
             
            Text("SUBSTRACK")
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(.appBrown)
                .multilineTextAlignment(.center)
                .padding()
                .offset(x: 0, y: -100)

            Text("pour savoir \nquand renégociez vos contrats !")
                .font(.system(size: 18, weight: .medium))
                .italic()
                .foregroundColor(.appBrown)
                .multilineTextAlignment(.center)
                .padding()
                .offset(x: 0, y: -50)
        }
    }
}
