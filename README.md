# パシャ — 撮るだけ、ラクになる。

> AI搭載レシート経費管理アプリ

[![TestFlight](https://img.shields.io/badge/TestFlight-Beta-blue)](https://testflight.apple.com/join/CTmyqV6H)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Open Source](https://img.shields.io/badge/Open%20Source-Enabler-E8A838)](https://enablerdao.com)

## Features

- AI OCR自動入力 — レシートを撮るだけで金額・日付・店舗名を自動認識
- 電子帳簿保存法対応 — 全8要件を満たし、法令準拠の電子保存を実現
- チェーンハッシュ — データの改ざんを検知する連鎖ハッシュで記録の信頼性を担保
- Solanaアンカリング — ブロックチェーンにハッシュを記録し、第三者検証を可能に
- 月次レポート — Swift Chartsによる支出の可視化と分析

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS | SwiftUI, SwiftData |
| OCR | Vision Framework |
| Charts | Swift Charts |
| Hash | CryptoKit (chain hash) |
| Blockchain | Solana |

## Getting Started

```bash
git clone https://github.com/yukihamada/pasha.git
cd pasha/ios
xcodegen generate
xcodebuild -project Pasha.xcodeproj -scheme Pasha \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

## Contributing

PRs welcome!

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit your changes
4. Push and create a PR

### コントリビューションポイント

Enablerエコシステムへの貢献はポイントとして記録されます。
将来的なガバナンス参加に活用される予定です。

## Security

- 全データはiPhoneのローカルに保存
- 外部サーバーへのデータ送信なし
- オープンソースでコードを検証可能

## License

MIT — 詳細は [LICENSE](LICENSE) を参照

## Links

- [TestFlight Beta](https://testflight.apple.com/join/CTmyqV6H)
- [Enabler](https://enablerdao.com)
- [pasha.run](https://pasha.run)

---

Built with AI. Tested with AI. Polished by humans.
