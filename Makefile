.PHONY: setup build up down restart shell console db-console migrate test lint log log-tail clean

# デフォルトコマンド: ヘルプを表示
help:
	@echo "イベンタアプリケーション用Makefileコマンド一覧:"
	@echo "make setup         - 初期セットアップを実行 (ビルド、依存関係インストール、DBセットアップ)"
	@echo "make build         - Dockerイメージをビルド"
	@echo "make up            - アプリケーションを起動 (バックグラウンド実行)"
	@echo "make server        - アプリケーションを起動 (フォアグラウンド実行)"
	@echo "make down          - アプリケーションを停止"
	@echo "make restart       - アプリケーションを再起動"
	@echo "make shell         - webコンテナにシェルで接続"
	@echo "make console       - Railsコンソールを起動"
	@echo "make db-console    - MySQLコンソールに接続"
	@echo "make migrate       - データベースマイグレーションを実行"
	@echo "make routes        - ルート一覧を表示"
	@echo "make test          - テストを実行"
	@echo "make lint          - コードリントを実行"
	@echo "make log           - 開発ログを表示 (最新100行)"
	@echo "make log-tail      - 開発ログを継続的に監視 (tail -f)"
	@echo "make clean         - 未使用のDockerリソースをクリーンアップ"

# プロジェクトのセットアップ
setup: build
	docker compose run --rm web bundle install
	docker compose run --rm web bin/rails db:create
	docker compose run --rm web bin/rails db:migrate
	docker compose run --rm web bin/rails db:seed

# Dockerイメージをビルド
build:
	docker compose build

# アプリケーション起動 (バックグラウンド)
up:
	docker compose up -d --build
	@echo "アプリケーションがバックグラウンドで起動しました。"
	@echo "http://localhost:3000 でアクセスできます。"
	@echo "ログを確認するには 'make log' を実行してください。"
	@echo "アプリケーションを停止するには 'make down' を実行してください。"
	@echo "アプリケーションを再起動するには 'make restart' を実行してください。"
	@echo "webコンテナにシェルで接続するには 'make shell' を実行してください。"
	@echo "Railsコンソールを起動するには 'make console' を実行してください。"
	@echo "MySQLコンソールに接続するには 'make db-console' を実行してください。"

# アプリケーション起動 (フォアグラウンド)
server:
	docker compose up

# アプリケーション停止
down:
	docker compose down

# アプリケーション再起動
restart:
	docker compose restart
	@echo "アプリケーションが再起動しました。"

# webコンテナにシェル接続
shell:
	docker compose run --rm web bash
	@echo "webコンテナに接続しました。exitで終了できます。

# Railsコンソール起動
console:
	docker compose run --rm web bin/rails console
	@echo "Railsコンソールに接続しました。exitで終了できます。"

# MySQLコンソールに接続
db-console:
	docker compose exec db mysql -u root -ppassword

# マイグレーション実行
migrate:
	docker compose run --rm web bin/rails db:migrate

# ルート一覧表示
routes:
	docker compose run --rm web bin/rails routes

# テスト実行
test:
	docker compose run --rm web bin/rails test

# リント実行
lint:
	docker compose run --rm web bin/rubocop

# ログ表示 (最新100行)
log:
	@if docker compose run --rm web test -f log/development.log; then \
		docker compose run --rm web tail -n 100 log/development.log; \
	else \
		echo "ログファイルが存在しません。アプリケーションを一度起動してください (make server)"; \
	fi

# ログ監視（継続的に表示）
log-tail:
	@if docker compose run --rm web test -f log/development.log; then \
		docker compose run --rm web tail -f log/development.log; \
	else \
		echo "ログファイルが存在しません。アプリケーションを一度起動してください (make server)"; \
		docker compose logs -f web; \
	fi

# Docker不要リソースクリーンアップ
clean:
	docker compose down --remove-orphans
	docker system prune -f