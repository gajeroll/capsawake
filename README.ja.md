# CapsAwake

[English](README.md)

[![CI](https://github.com/gajeroll/capsawake/actions/workflows/ci.yml/badge.svg)](https://github.com/gajeroll/capsawake/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

CapsAwake は、**Caps Lock** をスリープ抑止のスイッチにする macOS のメニューバーアプリです。

- **Caps Lock オン**でシステムスリープを止めます。外部ディスプレイがなくても、蓋を閉じたまま作業できます。
- **Caps Lock オフ**で、いつものスリープに戻ります。
- スリープを止めているあいだ、メニューバーのアイコンは緑になります。

通信は行わず、利用状況も送りません。表示言語はシステムの言語に従い、設定で選べます。

![CapsAwake のメニュー](docs/menu.png)

## 動作環境

- macOS 14 以降
- Apple silicon。リリースビルドは Universal ではなく、Intel Mac には対応していません。

## インストール

### ビルド済みのアプリ

[Releases](https://github.com/gajeroll/capsawake/releases) から
`CapsAwake-<version>.zip` をダウンロードし、展開して `CapsAwake.app` を
`/Applications` に移します。

初回起動時に、**システム設定 → 一般 → ログイン項目と拡張機能** でバックグラウンドのデーモンを許可します。

### ソースからビルド

```sh
git clone https://github.com/gajeroll/capsawake.git
cd capsawake
make build
make test
SKIP_SIGNING=true ./scripts/build-app.sh ~/Applications/CapsAwake.app
open ~/Applications/CapsAwake.app
```

macOS 14 以降と Swift 6.2（Xcode 26）が必要です。ソースからビルドしたアプリはメニューとキーは動きますが、スリープ設定は変えられません。デーモンは公証済みの Developer ID ビルドでしか起動しないためです。[リリース](https://github.com/gajeroll/capsawake/releases)を使うか、`make notarize` で作ってください。手順は [CONTRIBUTING.md](CONTRIBUTING.md) にあります。

### アンインストール

```sh
scripts/uninstall.sh
```

アプリを捨てるだけでは、デーモンのログイン項目が残ります。このスクリプトは CapsAwake を終了し、変更していたスリープ設定を戻してから、デーモンの登録を外します。

## 権限

- **バックグラウンドのデーモン（root）。** 必須です。蓋を閉じ、外部ディスプレイがない状態で Mac を起こしたままにする公開の手段は `pmset -a disablesleep` だけで、これには root が要ります。`SMAppService` で登録します。デーモンが行うことは [SECURITY.md](SECURITY.md) にすべて書いてあります。
- **アクセシビリティ。** **Caps LockをCapsAwake専用にする** をオンにしたときだけ必要です。それまではハードウェアのロック状態を読むだけで、イベントタップは入れません。キー入力の保存や送信は行いません。

## キーの動き

**Caps LockをCapsAwake専用にする** がオフのときは、一度の押下で大文字入力とスリープ抑止が一緒に切り替わります。

オンにすると、ふたつに分かれます。

- Caps Lock 単体はスリープ抑止だけを切り替え、大文字は打ちません。
- **Shift+Caps Lock**、または設定で記録した組み合わせが、大文字入力を切り替えます。
- 緑はスリープ抑止、塗りつぶしは大文字入力を表します。

蓋を閉じても、外部ディスプレイなしで作業を続けられます。内蔵ディスプレイにはスリープを求めます。スリープ抑止中はエネルギーモードを切り替えられ（初期値は低電力モード）、オフにすると以前のモードに戻します。

Mac が重大な高温を知らせたとき、または設定の **最低バッテリー残量**（初期値は 5%）を下回ったときは、スリープ抑止を自ら解除します。

## トラブルシューティング

- **スリープ抑止がオンにならない。** **システム設定 → 一般 → ログイン項目と拡張機能** で CapsAwake のデーモンを有効にしてください。
- **ビルドし直すとアクセシビリティの許可が消える。** アドホック署名はビルドのたびに変わるため、macOS が許可を捨てます。Apple Development の証明書で署名するか、**プライバシーとセキュリティ → アクセシビリティ** で CapsAwake を一度オフにしてからオンにしてください。
- **ダウンロードしたアプリを macOS が開かない。** `CapsAwake.app` を右クリックして **開く** を選んでください。

## 開発

署名、公証、リリース手順は [CONTRIBUTING.md](CONTRIBUTING.md) にあります。

```sh
make build
make test
make lint
```

## セキュリティ

デーモンは root で動きます。受け付けるリクエストと脆弱性の報告先は [SECURITY.md](SECURITY.md) にあります。

## クレジット

[Capsomnia](https://github.com/fuji-mak/Capsomnia) に着想を得ています。

## ライセンス

[MIT](LICENSE)
