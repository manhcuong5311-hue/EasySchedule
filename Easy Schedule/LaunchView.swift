//
//  LaunchView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 13/11/25.
//



import SwiftUI

struct LaunchView: View {
    @State private var logoScale: CGFloat = 0.5
    @State private var textOpacity: Double = 0.0

    var body: some View {
        ZStack {
            // Gradient nền bắt mắt
            LinearGradient(colors: [Color.orange, Color.red],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Logo ES với animation phóng to
                Image("appstore") // logo trong Assets
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    .scaleEffect(logoScale)
                    .animation(.easeOut(duration: 1.0), value: logoScale)
                
                // Text Welcome với fade in
                Text("Chào mừng bạn đến với Easy Schedule!")
                    .multilineTextAlignment(.center)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .opacity(textOpacity)
                    .animation(.easeIn(duration: 1.0).delay(0.5), value: textOpacity)
            }
        }
        .onAppear {
            // Trigger animation khi view xuất hiện
            logoScale = 1.0
            textOpacity = 1.0
        }
    }
}

struct LaunchView_Previews: PreviewProvider {
    static var previews: some View {
        LaunchView()
    }
}

