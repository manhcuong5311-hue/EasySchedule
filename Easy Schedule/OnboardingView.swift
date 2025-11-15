import SwiftUI

struct EnhancedOnboardingView: View {
    @Binding var showOnboarding: Bool
    @State private var logoScale: CGFloat = 0.6
    @State private var textOpacity: Double = 0.0

    var body: some View {
        TabView {
            // Slide 1: Logo app
            featureSlide(
                imageName: "appstore",
                title: "Sắp xếp lịch của bạn",
                description: "Giữ cho mọi cuộc hẹn và công việc ngăn nắp.",
                gradient: LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing),
                useSystemImage: false
            )
            
            // Slide 2: Calendar SF Symbol
            featureSlide(
                imageName: "calendar",
                title: "Không bỏ lỡ cuộc hẹn nào",
                description: "Nhận thông báo và nhắc hẹn cho sự kiện quan trọng của bạn.",
                gradient: LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                useSystemImage: true
            )
            
            // Slide 3: Bell SF Symbol + Button
            featureSlide(
                imageName: "bell",
                title: "Dễ dàng và thuận tiện sắp xếp.",
                description: "Nhanh chóng sắp xếp sự kiện mới và kiểm soát lịch của bạn hiệu quả hơn.",
                gradient: LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                useSystemImage: true,
                showButton: true
            )
        }
        .tabViewStyle(PageTabViewStyle())
    }
    
    @ViewBuilder
    func featureSlide(imageName: String, title: String, description: String, gradient: LinearGradient, useSystemImage: Bool, showButton: Bool = false) -> some View {
        ZStack {
            gradient
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Image hoặc SF Symbol
                if useSystemImage {
                    Image(systemName: imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                        .foregroundColor(.white)
                        .scaleEffect(logoScale)
                        .animation(.easeOut(duration: 1), value: logoScale)
                } else {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                        .scaleEffect(logoScale)
                        .animation(.easeOut(duration: 1), value: logoScale)
                }
                
                // Text
                VStack(spacing: 10) {
                    Text(title)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity(textOpacity)
                        .animation(.easeIn(duration: 1).delay(0.3), value: textOpacity)
                    
                    Text(description)
                        .font(.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .opacity(textOpacity)
                        .animation(.easeIn(duration: 1).delay(0.5), value: textOpacity)
                }
                
                // Button "Get Started" chỉ slide cuối
                if showButton {
                    Button(action: {
                        showOnboarding = false
                        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                    }) {
                        Text("Bắt đầu")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.orange)
                            .cornerRadius(15)
                            .padding(.horizontal)
                    }
                    .padding(.top, 20)
                }
            }
            .padding()
        }
        .onAppear {
            logoScale = 1.0
            textOpacity = 1.0
        }
    }
}

struct EnhancedOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedOnboardingView(showOnboarding: .constant(true))
    }
}
