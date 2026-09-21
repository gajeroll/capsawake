# CapsAwake

[English](README.md)

[![CI](https://github.com/gajeroll/capsawake/actions/workflows/ci.yml/badge.svg)](https://github.com/gajeroll/capsawake/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

CapsAwake は、**Caps Lock** をスリープ抑止スイッチにする軽量な macOS メニューバーアプリです。

- **Caps Lock オン:** 外部ディスプレイなしで蓋を閉じても、システムスリープを防止します。
- **Caps Lock オフ:** 通常のスリープ動作に戻します。
- メニューバーアイコンはスリープ抑止中に緑色になり、塗りつぶしは大文字入力中を示します。

通信やデータ収集は行いません。英語と日本語の UI に対応しています。

![CapsAwake のメニュー](docs/menu.png)

## 動作環境

- **対応 OS:** macOS 14 以降
- **アーキテクチャ:** Apple silicon のみ（Intel Mac は非対応、リリースビルドは Universal ではありません）
- **ビルド環境（ソースからビルドする場合）:** Swift 6.2（Xcode 26）

## インストール

### ビルド済みバイナリ

[Releases](https://github.com/gajeroll/capsawake/releases) から最新の `CapsAwake-<version>.zip` をダウンロード・展開し、`CapsAwake.app` を `/Applications` に移動してください。

初回起動時に、**システム設定 → 一般 → ログイン項目と拡張機能** でバックグラウンドデーモンを許可してください。

### ソースからビルド

```sh
git clone https://github.com/gajeroll/capsawake.git
cd capsawake
make build
make test
SKIP_SIGNING=true ./scripts/build-app.sh ~/Applications/CapsAwake.app
open ~/Applications/CapsAwake.app
```

ソースビルドはメニューやキー動作を確認できますが、スリープ設定は変更できません。デーモンは公証済みの Developer ID ビルドからのみ起動するためです。[リリース版](https://github.com/gajeroll/capsawake/releases)を使用するか、`make notarize` でビルドしてください。詳細は [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

### アンインストール

```sh
scripts/uninstall.sh
```

アプリをゴミ箱へ移動するだけでは、デーモンのログイン項目が残ります。このスクリプトは CapsAwake を終了し、変更したスリープ設定を元に戻してからデーモンの登録を解除します。

## 権限

- **バックグラウンドデーモン（root）:** 必須。外部ディスプレイなしで蓋を閉じたままスリープさせない公開の手段は `pmset -a disablesleep` だけです。`SMAppService` で登録します。詳細は [SECURITY.md](SECURITY.md) にあります。
- **アクセシビリティ:** **Caps LockをCapsAwake専用にする** をオンにした場合のみ必要です。オフの間はハードウェアのロック状態を直接読み取り、イベントタップは作成しません。キー入力の保存や送信は行いません。

## キーの動作

- **「Caps LockをCapsAwake専用にする」オフ（初期値）:** 1 回の押下で大文字入力とスリープ抑止を同時に切り替えます。
- **「Caps LockをCapsAwake専用にする」オン:**
  - **Caps Lock** 単体でスリープ抑止を切り替え、大文字入力は行いません。
  - **Shift+Caps Lock**（または設定で記録したショートカット）で大文字入力を切り替えます。
- **クラムシェル動作:** 外部ディスプレイがなくても蓋を閉じたまま作業を継続でき、内蔵ディスプレイはスリープします。
- **エネルギーモード:** スリープ抑止中は指定したモード（初期値は低電力モード）に切り替え、解除時に元のモードへ戻します。
- **安全停止:** 重大な高温を検知したとき、またはバッテリー残量が設定の **最低バッテリー残量**（初期値は 5%）を下回ったときは自動でスリープ抑止を停止します。

## トラブルシューティング

- **スリープ抑止が有効にならない:** **システム設定 → 一般 → ログイン項目と拡張機能** で CapsAwake デーモンを有効にしてください。
- **再ビルド後にアクセシビリティ権限が消える:** **システム設定 → プライバシーとセキュリティ → アクセシビリティ** で CapsAwake を一度オフにしてから再度オンにするか、Apple Development 証明書で署名してください。
- **ダウンロードしたアプリが開けない:** `CapsAwake.app` を右クリックして **開く** を選択してください。

## 開発

コントリビューションを歓迎します。署名、公証、リリース手順は [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

```sh
make build
make test
make lint
```

## セキュリティ

デーモンは root 権限で動作します。受け付けるリクエストと脆弱性の報告手順は [SECURITY.md](SECURITY.md) を参照してください。

## クレジット

[Capsomnia](https://github.com/fuji-mak/Capsomnia) に着想を得ています。

## ライセンス

[MIT License](LICENSE) の下で配布されています。
