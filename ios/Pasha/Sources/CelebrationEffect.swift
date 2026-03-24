import SwiftUI

// MARK: - Success Checkmark Animation

struct SuccessCheckmark: View {
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 80, height: 80)

            Circle()
                .fill(color)
                .frame(width: 64, height: 64)

            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                scale = 1
                opacity = 1
            }
        }
    }
}

// MARK: - Confetti Effect

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    let colors: [Color]

    init(colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange]) {
        self.colors = colors
    }

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Circle()
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .position(p.position)
                    .opacity(p.opacity)
                    .rotationEffect(.degrees(p.rotation))
            }
        }
        .onAppear { startConfetti() }
        .allowsHitTesting(false)
    }

    private func startConfetti() {
        for i in 0..<40 {
            let p = ConfettiParticle(
                id: i,
                color: colors.randomElement() ?? .blue,
                size: CGFloat.random(in: 4...10),
                position: CGPoint(x: CGFloat.random(in: 0...400), y: -20),
                opacity: 1,
                rotation: Double.random(in: 0...360)
            )
            particles.append(p)
        }

        withAnimation(.easeIn(duration: 2.0)) {
            for i in particles.indices {
                particles[i].position.y += CGFloat.random(in: 600...900)
                particles[i].position.x += CGFloat.random(in: -100...100)
                particles[i].opacity = 0
                particles[i].rotation += Double.random(in: 180...720)
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id: Int
    let color: Color
    let size: CGFloat
    var position: CGPoint
    var opacity: Double
    var rotation: Double
}
