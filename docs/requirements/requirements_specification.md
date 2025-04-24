# eventa 要件定義書 (v0.2)

## 1. 背景・目的  
### 背景  
- ライブ・カンファレンス・スポーツなど多様なイベントがオンラインで完結したチケット販売／入場管理を求めている。  
- 現行ツールは機能分散・操作性の低さ・高コストが課題。  

### 目的  
- **SaaS『eventa』**を Ruby on Rails モノリスで 3 か月（MVP）で構築し、主催者の **チケット設定 → 決済 → 当日運営 → 分析** をワンストップで実現する。  
- 第一フェーズは国内向け、日本語 UI。第二フェーズで多通貨／多言語を追加。  

---

## 2. 用語定義  
| 用語 | 定義 |
|------|------|
| イベント | 公演・展示会など、開催日時・会場を持つ最上位オブジェクト |
| セクション | 会場内の座席ブロック（例: Aブロック 1列–10列） |
| チケット種別 | 価格や特典が異なる販売 SKU（例: 一般, VIP, 早割） |
| チケット | 個々の電子券（QR コード）／座席番号を保持 |
| オーガナイザ | 主催者ロール。イベント登録・販売設定を行うユーザ |
| カスタマー | 最終購入者。チケット購入・マイページ確認を行うユーザ |
| 管理者 | eventa のシステム管理者 (B2B SaaS 運営側) |

---

## 3. スコープ (機能一覧)  
### 3.1 オーガナイザ向け  
- イベント CRUD / 複製  
- 会場レイアウト登録 (SVG / JSON)  
- 座席／立ち見・チケット種別・販売数設定  
- 決済連携 (Stripe Connect Standard)  
- 販売状況ダッシュボード (売上・来場率)  
- 入場チェックインアプリ用 API (QR read)  
- CSV エクスポート（購入者一覧・売上）  

### 3.2 カスタマー向け  
- イベント一覧・詳細  
- 座席選択 UI・カート  
- 決済 (クレカ / Apple Pay / Google Pay)  
- 購入履歴・マイチケット（QR）  
- 払い戻し申請（主催者承認制）  

### 3.3 管理者向け  
- ユーザ・イベント監視  
- 手数料率設定  
- サポート用検索／チケット再発行  

### 3.4 共通  
- SNS シェア OG タグ自動生成  
- PWA 対応（オフライン QR 表示）  
- アクセシビリティ (WCAG 2.1 AA)  

---

## 4. 非機能要件  
| 項目 | 指標 / 方針 |
|------|-------------|
| パフォーマンス | p95 レスポンス < 300 ms (API)、同時購入 500 RPS でスロットルしない |
| 可用性 | 99.9 % / 月、Zero‑Downtime デプロイ (Kamal Rolling) |
| セキュリティ | OWASP Top‑10 対策、CSP / Strict‑Transport‑Security、Brakeman & audit CI | 
| データ保全 | 本番 MySQL Multi‑AZ、5 分 PITR、S3 バックアップ 30 日保持 |
| 監視 | Datadog (APM, Logs, RUM)、UptimeRobot Healthcheck `/up` |
| ログ | JSON 構造化、PII マスク (filter_parameters) |
| 国際化 | i18n (ja-JP, en-US) 基盤のみ MVP では ja 起動 |

---

## 5. 技術スタック / バージョン固定  
| レイヤ | 採用技術 | 備考 |
|--------|----------|------|
| 言語 | **Ruby 3.3.8** | `.ruby-version` 済み |
| Web FW | **Rails 8.0.2** | API + Hotwire (Turbo/Stimulus) |
| DB | **MySQL 8.0** | utf8mb4 / InnoDB | 
| キャッシュ | **Solid Cache** (MySQL) & browser-cache | |
| ジョブ | **Solid Queue** (MySQL) | Web プロセス内 Supervisor (MVP) |
| リアルタイム | **Solid Cable** | ActionCable 代替 |
| メッセージ送信 | Action Mailer (SendGrid API) |
| 決済 | **Stripe Connect Standard** |
| Container | Docker (multi‑stage) & Docker Compose dev |
| Deploy | **Kamal 2.x** / Traefik proxy TLS │ AWS EC2 (t4g.medium) |
| CI/CD | GitHub Actions + Dependabot │ Jobs: lint, brakeman, importmap audit, test |
| テスト | Minitest (system: Capybara + Selenium/Chrome) │ RSpec 検討中 |
| フロント | Tailwind CSS 3.x / Propshaft / Importmap |

---

## 6. アーキテクチャ概要  
- 単一 Rails コンテナ (web) + MySQL + Redis (セッション, future cache) を docker‑compose & Kamal deploy。  
- DDD 準拠パッケージ分割 (`app/models/domain/…`, `app/services/…`) で疎結合を保つ。  
- Job/Cache/Cable 用に DB を論理分離 (Solid Queue など用の DB)。  

```
┌────────┐   HTTP(S)   ┌──────────┐
│ Browser │ ─────────▶ │ Traefik  │ ─ reverse proxy / TLS
└────────┘             └──────────┘
                             │
                    Kamal overlay network
                             │
                      ┌────────────┐
                      │ Rails (web)│─┬─ MySQL(primary)
                      └────────────┘ │
                                      └─ Redis (cache/session)
```

---

## 7. データモデル (抜粋)  
| テーブル | 主キー | 主なカラム | 備考 |
|----------|--------|-----------|------|
| events | id | name, starts_at, ends_at, venue_id, status | |
| ticket_types | id | event_id, name, price_cents, quota | 座席区分ごとに複数 |
| tickets | id | ticket_type_id, user_id, seat_no, qr_token, status | 電子券 |
| orders | id | user_id, total_cents, stripe_checkout_id, status | 決済単位 |
| users | id | role(enum), email, encrypted_password, … | Devise/Sorcery TBD |

詳細 ER 図は別紙参照。  

---

## 8. 外部サービス連携  
- **Stripe Connect**: 決済・精算  
- **SendGrid**: メール送信  
- **S3 (AWS)**: ログ・バックアップ  
- **Datadog**: APM／Log  

---

## 9. 開発プロセス & CI/CD  
1. **GitHub Flow**（`main` 保護、PR レビュー 1 名必須）  
2. Dependabot → 自動 PR → CI  
3. CI Steps  
   - `brakeman` 静的解析 (fail‐on‐warn)  
   - `rubocop` Lint  
   - `importmap audit` JS 脆弱性  
   - `rails test` (Minitest + System)  
4. `main` push で `kamal deploy production` 実行 (manual approval)  

---

## 10. マイルストーン  
| 週 | Deliverable | 備考 |
|----|-------------|------|
| W0–1 | 要件定義 v0.2・画面遷移図・ER 図 FIX |  | 
| W2–4 | 認証・イベント CRUD・チケット種別 UI | Devise or Sorcery 決定 | 
| W5–6 | 座席マップ, Stripe 決済, QR 生成 | | 
| W7–8 | チェックイン API, ダッシュボード | | 
| W9 | オープン β & フィードバック | | 
| W10–11 | 決済周り hardening・監視 | | 
| W12 | MVP リリース 🚀 | |

