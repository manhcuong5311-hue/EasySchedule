import SwiftUI

struct LaunchView: View {
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0.0

    var body: some View {
        ZStack {
            // NỀN TRẮNG – an toàn tuyệt đối
            Color.white
                .ignoresSafeArea()

            Image("1") // tên ảnh trong Assets
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .animation(
                    .easeOut(duration: 0.6),
                    value: logoScale
                )
                .animation(
                    .easeIn(duration: 0.4),
                    value: logoOpacity
                )
        }
        .onAppear {
            logoScale = 1.0
            logoOpacity = 1.0
        }
    }
}

struct LaunchView_Previews: PreviewProvider {
    static var previews: some View {
        LaunchView()
    }
}
