import SwiftUI

/// Full-screen overlay shown during OCR/VLM processing with rotating tips
struct ProcessingTipsView: View {
    let isVLM: Bool
    let onDismiss: (() -> Void)?

    @State private var currentTipIndex = 0
    @State private var tipOpacity: Double = 1.0
    @State private var dotScale: CGFloat = 1.0
    @State private var rotation: Double = 0
    @State private var pulseScale: CGFloat = 0.8

    init(isVLM: Bool = false, onDismiss: (() -> Void)? = nil) {
        self.isVLM = isVLM
        self.onDismiss = onDismiss
    }

    private static let tips: [String] = [
        "レシートは平らな面に置くと認識精度が上がります",
        "暗い場所ではフラッシュを使うと読み取りやすくなります",
        "折り目のあるレシートは伸ばしてから撮影しましょう",
        "freeeやマネフォへの連携は設定からCSV出力できます",
        "レシートの写真は端末内に安全に保存されます",
        "電子帳簿保存法では紙のレシートを捨てても大丈夫です",
        "海外のレシートも7通貨に対応しています",
        "仕訳番号を入力すると会計ソフトとの連携がスムーズです",
        "金額を修正した場合も監査ログに記録されます",
        "Proプランなら月間レシート数は無制限です",
        "レシートの長押しで全画面表示できます",
        "複数のカテゴリを追加して自分の業種に合わせましょう",
        "確定申告の時期はデータをCSVで一括出力が便利です",
        "経費は発生した日に撮影するのがベストプラクティスです",
        "データのバックアップはiCloudで自動的に行われます",
        "検索機能で過去のレシートをすぐに見つけられます",
        "金額の範囲指定検索で特定の経費をフィルタリングできます",
        "税込金額から消費税を自動計算してfreee形式で出力します",
        "レシートの改ざんは検知される仕組みになっています",
        "GPSで撮影場所も自動記録されます（許可した場合）"
    ]

    var body: some View {
        ZStack {
            // Blurred dark background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .allowsHitTesting(true)

            VStack(spacing: 32) {
                Spacer()

                // Animated processing indicator
                ZStack {
                    // Outer pulse ring
                    Circle()
                        .stroke(Color.pasha.opacity(0.2), lineWidth: 2)
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulseScale)
                        .opacity(2.0 - Double(pulseScale))

                    // Spinning ring
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient(
                                colors: [Color.pasha, Color.pashaAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(rotation))

                    // Center icon
                    Image(systemName: isVLM ? "brain" : "doc.text.viewfinder")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.pasha, Color.pashaAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(dotScale)
                }

                // Status text
                VStack(spacing: 8) {
                    Text(isVLM ? "AI解析中..." : "読み取り中...")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(isVLM ? "ローカルAIがレシートを分析しています" : "Vision OCRでテキストを認識しています")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                // Tip card
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.pashaWarn)
                        Text("ヒント")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Text(Self.tips[currentTipIndex])
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .opacity(tipOpacity)
                        .animation(.easeInOut(duration: 0.4), value: tipOpacity)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
                .padding(.horizontal, 24)

                // Tip dots indicator
                HStack(spacing: 4) {
                    ForEach(0..<min(Self.tips.count, 5), id: \.self) { i in
                        Circle()
                            .fill(i == (currentTipIndex % 5) ? Color.pasha : Color.white.opacity(0.2))
                            .frame(width: 5, height: 5)
                    }
                }

                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear {
            startAnimations()
            // Shuffle to a random start
            currentTipIndex = Int.random(in: 0..<Self.tips.count)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                guard !Task.isCancelled else { break }
                // Fade out
                withAnimation(.easeOut(duration: 0.3)) {
                    tipOpacity = 0
                }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { break }
                // Change tip and fade in
                currentTipIndex = (currentTipIndex + 1) % Self.tips.count
                withAnimation(.easeIn(duration: 0.3)) {
                    tipOpacity = 1.0
                }
            }
        }
    }

    private func startAnimations() {
        // Spinning animation
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        // Pulse animation
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.3
        }
        // Dot scale breathing
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            dotScale = 1.15
        }
    }
}

#Preview {
    ProcessingTipsView(isVLM: false)
        .preferredColorScheme(.dark)
}
