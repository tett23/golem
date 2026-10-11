# golem

## Overview

TODO: プロジェクトの概要を記述してください。

## Installation

TODO: インストール手順を記述してください。

## Usage

TODO: 使い方を記述してください。

## Development

### Git フックの有効化

クローン直後に、リポジトリ同梱の Git フックを有効にする。

```bash
git config core.hooksPath .githooks
```

フックは [adr-guard](https://github.com/tett23/adr-guard) を呼び出すので、あらかじめインストールしておく。
`.githooks/pre-commit` は、コミット済みの ADR（`docs/adr/` と `docs/<モジュール>/adr/` の配下）への変更、削除、リネームを含むコミットを拒否する。
例外は `ステータス:` で始まる行で、この行だけは変更できる。
ADR はコミット後に変更しない規約であり、変更が必要な場合は新しい連番の ADR を作成する（詳細は [CLAUDE.md](./CLAUDE.md)）。
`core.hooksPath` はクローンごとのローカル設定であり、リポジトリには保存されないため、クローンのたびに実行が必要になる。
同じ検査は CI の `adr` ジョブでも行う。

TODO: ビルド・テスト・実行方法を記述してください。

## License

[MIT](./LICENSE) © tett23
