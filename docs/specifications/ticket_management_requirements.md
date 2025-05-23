# チケット管理アプリ 要件定義書 (Ver.0.1 – 2025‑04‑24)

## 1. 目的・背景
オンライン／オフライン双方のイベントで「入場チケットの販売・発券・確認」をワンストップで行えるプラットフォームを構築し、運営コスト削減と参加者体験の向上を図る。**もぎり作業を秒速で終わらせること**が本プロジェクトの野望である（急いで席に着きたいですからね！）。

## 2. ゴール
1. イベント主催者がノーコードでチケットを販売開始できる  
2. 参加者が 3 分以内に購入完了できる UI/UX  
3. 入場列での QR スキャン時間を 1 秒未満に短縮  
4. 不正転売ゼロ（メタプロが泣くのでおやめください）  

## 3. ステークホルダー
| 役割 | 主な関心事 |
| --- | --- |
| イベント主催者 | 売上把握 / 座席在庫 / 当日入場制御 |
| 参加者 | スムーズ購入 / 確実な入場 |
| 会場スタッフ | スキャン速度 / オフライン対応 |
| 財務担当 | 決済照合 / 返金管理 |
| 開発チーム | 拡張性 / 保守性 / デプロイ簡素化 |
| カスタマーサポート | 返金・譲渡・紛失対応 |

## 4. 用語定義
- **イベント**: 舞台・ライブ・セミナーなど開催単位
- **チケット種別**: 価格や席種を示すメタデータ
- **座席**: 座席番号または立ち見エリア
- **QRコード**: チケットの一意識別子

## 5. 前提条件・制約
- 技術スタック: Ruby 3.3 / Rails 7.2 モノリス
- DB: MySQL 8 系
- 決済: Stripe Connect
- デプロイ: Docker + GitHub Actions
- 全ページ PWA 化 (オフライン発券)
- 24/7 稼働・月次メンテ 2h 以内

## 5A. メタ認知ステップによる機能洗い出し
1. **目的確認**: プロダクトの Why / What / Who を言語化し、ゴール指標 (NPS, GMV など) を設定。
2. **ステークホルダー視点列挙**: 主催者・参加者・会場スタッフ・CS・財務それぞれの"困りごと"を箇条書き。
3. **ジャーニーマッピング**: 購入前 → 購入中 → 来場 → アフターという時系列で体験を俯瞰し、タッチポイントごとに課題を洗い出す。
4. **課題→機能変換**: 各課題に対し、システム・業務・UI のどれで解決するかをメモ。
5. **CRUD マトリクス作成**: エンティティ (Event, Ticket, Order, User など) と操作 (Create / Read / Update / Delete) をクロス集計し、抜け漏れチェック。
6. **非機能チェックリスト**: 性能・可用性・セキュリティ・運用コスト・アクセシビリティをレビュー。
7. **リスクブレインストーミング**: ネットワーク障害・法規制変更など、最悪ケースを想定して対策を列挙。
8. **MoSCoW 優先度付け**: Must / Should / Could / Won't に機能を整理し、フェーズを設計。
9. **仮説と検証指標**: 初期 MVP で検証すべき仮説を定義し、計測方法を明記。
10. **Pull Request レベルでの要件トレース**: コード → チケット → 要件の一貫性を保つレビュー観点を策定。

## 5B. CRUD マトリクス（例）

| エンティティ \ 操作 | Create | Read | Update | Delete | 備考 |
| --- | --- | --- | --- | --- | --- |
| **Event** | Admin, Organizer | Public, Admin, Organizer | Admin, Organizer | Admin, Organizer (論理) | 開催後は更新不可 |
| **TicketType** | Organizer | Organizer, Admin | Organizer | Organizer (販売開始後は禁止) | |
| **Ticket** | System (購入時) | Owner, Admin, Organizer | _—_ (Status のみ) | System (返金時) | 発券後は内容固定 |
| **Order** | System (決済時) | Owner, Admin | Admin (返金) | Admin (取消) | 会計監査のため削除＝論理 |
| **User** | Self, Admin | Self, Admin | Self, Admin | Admin (論理) | 退会＝論理削除 |
| **ScanLog** | System (入場時) | Admin, Organizer | _—_ | Admin (90 日後 purge) | GDPR 準拠 |

> "System" はバックエンドジョブや API が自動実行する操作を示す。

---

## 5C. チケット種別ごとの在庫戦略
- **固定席**: 座席番号に紐づく 1:1 在庫、タイムアウト取り置き (15 min)。  
- **立ち見**: エリア毎に数量管理、ピーク時は入場時点で減算。  
- **追加リリース枠**: ダイナミックプライシング対応、発券上限を Soft Cap → Hard Cap へ昇格可能。  
- **戻りチケット再販**: 返金・譲渡で戻った在庫を専用プールに戻し、再販通知。  
- **販売停止トリガー**: 主催者手動 / 自動 (公演 30 min 前) でクローズ。

## 5D. 返金フロー詳細
| ケース | トリガー | 責任者 | 手数料 | 返金処理 | SL A |
| --- | --- | --- | --- | --- | --- |
| 主催者キャンセル | 公演中止 | Organizer | 0% | 全額即時 Stripe Refund API | T+0d |
| 参加者都合 | User 申請 | User | 10% (設定可) | 自動判定 (開催 7 d 前まで) | T+3d |
| イベント延期 | Organizer | Organizer | 0% | ユーザー選択: 返金 or 代替券 | T+5d |
| システム障害 | System | Admin | 0% | Case‑by‑case | T+5d |

- 返金は **Webhook** でステータス同期し、`RefundLog` に記録。
- 監査対応として Stripe Balance Transaction ID を保持。

## 5E. 通知チャネル多層化
1. **Primary – Email (SendGrid)**: トランザクションメール。  
2. **Secondary – SMS (Twilio)**: メール bounce 時のフォールバック。  
3. **Tertiary – LINE Bot**: 任意 opt‑in、リマインダ中心。  
4. **Retry ポリシー**: 1>2>3 順に 3 回リトライ／指数バックオフ。  
5. **ユーザー設定**: 通知オプトアウト／チャネル優先度変更 UI。  
6. **Rate Limit**: 1 msg/sec / user、GDPR 準拠。

## 5F. オフライン入場モードの失敗シナリオ
- **キャッシュ破損**: 署名付き JSON にチェックサム付与 → 壊れたら再同期促すモーダル。
- **時計ずれ**: デバイスタイムとサーバ時刻差 > ±5 min で警告、手動承認ボタンを表示。  
- **バッテリー切れ**: スタッフ用モバイルバッテリー常備、残量 <20% でアラート。  
- **端末紛失**: MDM リモート wipe、資格情報は JWT + デバイスキーで暗号化。
- **QR 偽造検知**: 署名 + カウンタ、同一カウンタ2回読み取りで二重入場フラグ。  
- **完全オフライン対応期限**: 8 h 以内とし、それ以上は再認証要求。

---

## 6. 業務フロー概要
1. 主催者がイベント作成→チケット種別設定  
2. 販売開始日時に公開  
3. 参加者購入→決済→チケット発行 (PDF & Apple/Google Wallet)  
4. 当日 QR スキャン→入場ログ生成  
5. 売上集計→振込レポート生成  

## 7. 機能要件
### 7.1 イベント・チケット管理
- [ ] イベント CRUD（複数日程・複数会場対応）
- [ ] チケット種別 CRUD（料金・販売期間・枚数制限）
- [ ] 座席マップインポート (CSV + 画像)
- [ ] 発売スケジュール自動公開

### 7.2 購入・決済
- [ ] カート & 一括購入  
- [ ] Stripe 決済 / コンビニ決済 / クーポン適用  
- [ ] 領収書 PDF 自動発行  

### 7.3 入場管理
- [ ] QR/バーコード発行 (v4 MIME)  
- [ ] iOS/Android ネイティブスキャン (オフラインキャッシュ)  
- [ ] リアルタイム残席表示 (ActionCable)

### 7.4 管理ダッシュボード
- [ ] 売上/入場レポート (日次・期間指定)  
- [ ] CSV エクスポート・S3 連携  
- [ ] 権限管理 (admin/operator)  

### 7.5 通知・メール
- [ ] 購入完了メール + 添付 PDF  
- [ ] 開催前リマインダ / 開催後サンクス  
- [ ] 障害時の内部アラート (Slack Webhook)

### 7.6 返金・譲渡
- [ ] 主催者パネルからの手動返金  
- [ ] 参加者同士の譲渡 (手数料設定可)  
- [ ] 不正検知ロジック（同一 QR 二重使用ブロック）

## 8. 非機能要件
| 区分 | 要件 |
| --- | --- |
| 性能 | ピーク 100 リクエスト/秒 で P95 < 400 ms |
| スケーラビリティ | イベント 1 つで最大 50 万枚発券 |
| セキュリティ | OWASP top10 準拠、2FA、WAF 導入 |
| 可観測性 | APM + 構造化ログ (JSON) |
| 保守性 | Gem 更新は Dependabot + CI 自動テストで検証 |
| 可用性 | SLA 99.9%、RTO 30 min、RPO 15 min |

## 9. データ要件
```
Event 1—N TicketType 1—N Ticket
Ticket N—1 Order N—1 User
Venue 1—N Event
Ticket 1—N ScanLog
```
※ 詳細 ER 図は別紙 (Mermaid) 参照

## 10. 画面要件 (主要)
| 画面ID | 目的 | 主要操作 |
| --- | --- | --- |
| EVT-L-001 | イベント一覧 | 新規作成 / 編集 / 終了 |
| TKT-P-001 | チケット購入 | 枚数選択 / 支払方法 |
| SCN-M-001 | スキャンモード | QR 連続読み取り |
| ADM-D-001 | 売上ダッシュボード | 集計期間フィルタ / CSV |

## 11. 外部インタフェース
- **Stripe API**: 決済/返金
- **Amazon S3**: 画像・CSV ファイル
- **SendGrid**: メール送信
- **Webhook**: Slack 通知

## 12. テスト戦略
- RSpec + FactoryBot + Faker で C1 90% 以上
- SystemTest (Capybara + Headless Chrome)
- 負荷試験 (k6) – ピークシナリオ

## 13. 移行計画
- 既存イベント DB からの CSV インポートツール
- フェーズ移行: α→β→本番

## 14. リスク & 想定外
| ID | リスク | 軽減策 |
| --- | --- | --- |
| R-001 | 決済 API 仕様変更 | Stripe API バージョン管理 |
| R-002 | ネットワーク障害 | オフラインチケット検証モード |
| R-003 | 法規制 (特定興行入場券転売禁止法) | 利用規約アップデート & 転売検知 |

## 15. 成功指標
- リリース 6 か月以内に GMV 5,000 万円
- 問い合わせ/販売枚数比率 < 1%
- NPS 60 以上

## 16. 付録
- **A. 参照: イベント管理アプリ技術要件**  
- **B. 用語集**  
- **C. Mermaid ER 図 v0.1**

---
*(ごほうび: 要件エクセル表を輸入する際は「セル結合禁止」を合言葉に!)*


## 17. WBS (Work Breakdown Structure)

| WBS ID | レベル1 | レベル2 | 主要作業内容 | 完了基準 | 担当 | 依存 | 期間 (週) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | プロジェクト準備 |  | キックオフ & 役割定義 | 参加者合意 | PM | — | 1 |
| 1.1 | プロジェクト準備 | 要件精査 | 既存要件レビュー、Gap分析 | 要件凍結 | BA | 1 | 2 |
| 2 | 設計 |  | アーキテクチャ設計 | ADR 承認 | Tech Lead | 1.1 | 2 |
| 2.1 | 設計 | DB & ER 設計 | ER 図確定、マイグレーション雛形 | PR Merge | DBA | 2 | 1 |
| 3 | 実装 | バックエンド | Event/Ticket API, Stripe連携 | RSpec C1>90% | BE Dev | 2 | 4 |
| 3.1 | 実装 | フロントエンド | 購入フロー, Admin ダッシュボード | Storybook 承認 | FE Dev | 2 | 4 |
| 3.2 | 実装 | モバイルスキャン | React Native スキャナ | P95 < 500ms Scan | FE Dev | 2 | 3 |
| 4 | テスト |  | 単体・結合・システム・性能 | 全テスト Pass | QA | 3 | 3 |
| 5 | デプロイ |  | CI/CD & インフラ構築 | Staging 動作確認 | DevOps | 4 | 1 |
| 6 | UAT & 移行 |  | 主催者 & スタッフ受入 | UAT Sign‑off | PM | 5 | 2 |
| 7 | リリース |  | 本番リリース & モニタリング | SLA 達成 | DevOps | 6 | 1 |
| 8 | 保守 & 改善 |  | KPI 監視 & フィードバック改善 | NPS >= 60 | CS | 7 | 継続 |

> 期間はベロシティ 10 ストーリーポイント/週を想定したラフ見積。詳細は次フェーズで微調整。

---



## 18. 技術要件詳細（Level-2）
**参照元**: イベント管理アプリ — レベル2 技術要件ドキュメント（2025-04-24）

### 18.1 Ruby 言語・メタプログラミング
- `freeze` を適切に使用して不変オブジェクトを保証するポイントを特定できること
- `proc` / `lambda` を使い分け、ブロックを引数として受け取るメソッドを定義できること
- `public_send`, `define_method` などのメタプロを理解し、コードリーディングが可能であること
- メタプログラミングによる罠・危険性を説明し、回避策を示せること

### 18.2 クラス設計とモジュール構成
- 依存関係を整理したクラス設計（カプセル化を意識）
- 継承クラスでメソッドをオーバーライドし、`super` を活用して振る舞いを個別化
- `extend` / `prepend` / `include` の使い分けと適切なユースケース
- `Struct` を用いた軽量データオブジェクトの実装

### 18.3 Gem 管理
- Gem のアップデートと変更点の調査・対応
- Gem 選定基準の明文化（GitHub Stars, 最終リリース日, DL 数など）

### 18.4 データベース・ActiveRecord
- 一括登録/更新/削除の実装とロールバック戦略
- 可逆性を担保したマイグレーション・データパッチ
- 自己結合・テーブル外モデルの設計
- `preload` / `eager_load` / `includes` の使い分けと N+1 対策
- 複雑検索（ポリモーフィック・STI・OR/AND 混在）を ransack を使わずに実装
- `join` 句を活用した複合条件検索

### 18.5 バリデーション & コールバック
- カスタムバリデータの作成と共通化クラス
- モデル各ライフサイクルでのコールバック設計
- セキュアなログ出力を行う Action コールバック

### 18.6 アプリケーションアーキテクチャ
- Decorator パターンでビュー層のロジックを整理
- モダンフロントエンドと ERB+jQuery 併存時の複雑度管理
- PDF・Excel 読み込み/生成機能
- 外部ストレージ (Amazon S3 等) 連携

### 18.7 認証・認可
- 複数スコープ（admin / user）ログイン
- ソーシャルログイン統合

### 18.8 非同期処理・バッチ
- ActiveJob + 適切なアダプタでの非同期ジョブ
- Rake タスクによるデータパッチ・リリースバッチ

### 18.9 メール・通知
- Action Mailer によるメール送信
- 添付ファイル (PDF, Excel) の動的生成と配信

### 18.10 テスト & 品質保証
- C1 / C2 カバレッジを意識したテストケース設計
- Headless Chrome を用いた SystemTest 実装
- タイピングパターン網羅用テストデータ生成

### 18.11 エラーハンドリング & ステータス
- `NoMethodError`, `ArgumentError`, `RangeError`, `StandardError` 等の捕捉と適切なレスポンス
- 404, 403 などケース別 HTTP ステータスの返却
- 422 / 500 カスタムエラーページ

### 18.12 運用 & 開発効率化ツール
- RailsDB, LetterOpener など開発補助ツール導入
- モニタリング・ログレベル最適化

---

## 19. アーキテクチャ概要
```
┌─────────────┐        ┌────────────┐
│   Next.js FE    │  API   │  Rails API     │
│ (PWA & Admin)   │<──────>│ (Docker Swarm) │
└─────────────┘        └────────────┘
        ▲                           ▲
        │ WebSocket (ActionCable)   │ ActiveJob
        │                           │
┌─────────────┐        ┌────────────┐
│  ReactNative │  gRPC │  Worker Pod │
│  Scanner App │<──────>│  Sidekiq     │
└─────────────┘        └────────────┘
        ▲                           ▲
        │ HTTPS                     │ RDS Proxy
┌─────────────┐        ┌────────────┐
│  User Device │       │   MySQL     │
└─────────────┘        └────────────┘
```
- **デプロイ**: AWS Fargate + RDS + CloudFront + WAF
- **監視**: Datadog (APM, Log, RUM) / CloudWatch
- **CI/CD**: GitHub Actions → ECR → ECS Rolling Update

## 20. 主要シーケンス（チケット購入フロー）
1. User → Frontend: チケット一覧取得 (GET /events/{id}/tickets)
2. Frontend → API: Order 作成 (POST /orders)
3. API → Stripe: PaymentIntent 作成
4. Stripe → API: 状態 Webhook (succeeded)
5. API → Worker: Ticket 発行ジョブ enqueue
6. Worker → S3: PDF 保存
7. API → SendGrid: 購入完了メール送信
8. Frontend: 完了画面 & Wallet ボタン表示

## 21. 品質管理計画
| 項目 | 指標 | 基準 | ツール |
| --- | --- | --- | --- |
| 静的解析 | RuboCop offense | 0 | GitHub Actions |
| 単体テスト | C1 カバレッジ | ≥ 90% | SimpleCov |
| 結合テスト | E2E Pass Rate | 100% | Cypress |
| 性能 | P95 レイテンシ | < 400 ms | k6, Datadog |
| セキュリティ | OWASP Top10 チェック | 0 Critical | Brakeman, Snyk |

## 22. コミュニケーション・レポーティング
- **Daily Stand-up**: 10 min (Slack huddle)
- **Weekly Sync**: 30 min (Zoom) – スプリントデモ & レトロ
- **ステータスレポート**: PM → 経営層へ Notion 週次更新
- **障害速報**: PagerDuty → Slack #incident, 15 min 以内初報

## 23. 変更管理プロセス
1. 変更提案 (Notion チケット) → 影響分析 (Tech Lead) → MoSCoW 再分類
2. 承認: PM / PO / QA / 財務 (決済影響時)
3. スプリント計画へ反映
4. リリースノート自動生成 (Release Drafter)

## 24. 参照資料
- 公式ガイド: Rails, Stripe, AWS
- 社内 Wiki: コーディング規約, デプロイ手順
- ブログ記事: メタプログラミング Patterns, PWA Best Practices

---

### **Table of Contents (自動生成用)**
1. 目的・背景 …1
2. ゴール …1
3. ステークホルダー …1
… (以下省略 – pandoc TOC オプションで出力)