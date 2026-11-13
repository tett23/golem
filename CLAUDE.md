# Golem

Golem はユーザーに組版システムと組版にまつわるワークフローを提供します。

## ディレクトリ構成

- **docs/** specifications.md に代表されるプロダクトのドキュメントを配置する
  - **docs/reserch/** 調査資料を置く。コミット後も更新できる。このディレクトリの資料だけを変更するときは文書の CI を実行する。
  - **docs/roadmap.md** どのバージョンで何を扱うかの予定、まだ実装していない項目、手で確かめる項目、未決事項、課題にしなかった事項を配置する。specifications.md には今の振る舞いだけを書き、バージョンの予定を書かない
  - **docs/{module}/specifications.md** 各モジュールの仕様書を配置する。このドキュメントには実装の詳細を書いてよい
    - **docs/{module}/adr/** そのモジュールの ADR を配置する。ファイル名は `0001-feature-details.md` のように連番の prefix と kebab-case の名前をつける。内容はグローバルの CLAUDE.md の構成（ステータス、文脈、実装すること、実装しないこと、テスト設計、トレードオフ）に従う。ADR は連番の通りに /goal で自動実装される。
  - **docs/adr/** 特定のモジュールに属さない横断的な ADR を配置する。命名と構成はモジュールの ADR と同じ。
  - コミット済みの ADR（`docs/adr/`、`docs/{module}/adr/` とも）はステータスの行を除き変更不可（adr-guard が強制する）。変更が必要な場合は新たな ADR を作成する。
  - 振る舞いを決める ADR は、「不変条件」の節を持つ。どの入力でも成り立つ性質を、テストの述語として書ける形で一つずつ番号を付けて書き、境界の入力（空、一つ、ちょうど収まる、一つあふれる、など）の表を添える。テストの名前には、その番号を入れる（[docs/adr/0204](docs/adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)）。不変条件を書けない ADR（設定の値や手順だけを決めるもの）は、その節に「なし」と理由を書く。
  - ADR は行頭が `ステータス:` のステータスの行をちょうど1つ持つ（adr-guard の pre-commit と `adr-guard check-status` が検査する）。
  - ADR からソースコード（`modules/`、`scripts/`、`.github/` などのファイル）を参照するときは、コミットのハッシュを含む GitHub の URL で書く（例: `https://github.com/tett23/golem/blob/<コミットのハッシュ>/modules/golem-layout/src/Golem/Layout/Paginate.hs#L209-L215`）。ファイルの全体を指すときも、行を指すときも同じ形にする。main は rebase も force push もしないので、ハッシュの URL は変わらない。GitHub から移るときは、adr-guard を変えるか、URL を書き換えて対応する。
  - **docs/audit/**、**docs/audits/**、**docs/benchmarks/**、**docs/benchmark/** 監査と性能計測の記録。コミット済みのものは変更、削除、移動不可（adr-guard が強制する）。`docs/ci-timings/` など別の名前の記録は検査されないが、同じくコミット後は変更しない。
- **modules/** 各モジュールを配置する

## skills

- 日本語の文章を書くときは cognitive-rhythm-writing japanese-tech-writing スキルを使用する。
