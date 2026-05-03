# godot-101

Godot 4.6 の練習用リポジトリ。Headless CLI ベース (UI を開かずに CLI とスクリプトだけでビルド・テスト・エクスポート・アセット生成を完結させる) のワークフローを試す場。

## ビルドして開く

```bash
tools/rebuild_web.sh                       # smoke → tests → Web export
python3 -m http.server --directory build/web 8000
# → http://localhost:8000/
```

`file://` では Web export は動かないので必ず HTTP で配信する。
表示するシーンは `project.godot` の `run/main_scene` で切り替える:

- `res://main.tscn` — Dialogic で動かす intro の会話デモ
- `res://shotgun_view.tscn` — 自前生成した 3D ショットガンを Y 軸スピン表示 (現状のデフォルト)

## ディレクトリ

```
.agents/skills/   # 自前スキル (後述)
assets/
  modeling/       # Blender Python (procedural 3D)
  models/         # 生成された .glb (gitignore)
  fonts/
features/         # ゲームロジック (キャラ、ダイアログ)
tools/            # CLI 用 shell / GDScript (ビルド、シーン生成、テスト)
```

## 使っているスキル

`.agents/skills/` 配下に 3 つ。Claude Code / codex から「どの状況でどう呼ぶか」を SKILL.md に書いたもの。

### headless-godot

Godot 4.x を CLI で動かす作法集。

- 起動は必ず `--headless --path <PROJECT_DIR>` (cwd 依存を消す)
- ログは `logs/<name>.log` に `tee` で残す
- `.tscn` を生テキストで編集しない。シーンを変えるときは `--script` でパッチか、`tools/create_*.gd` のように `SceneTree` から生成
- `--script` で動かす GDScript は必ず `quit(0|1)` で終わる (ハングしない)
- サンドボックス環境では `XDG_DATA_HOME/CONFIG_HOME/CACHE_HOME` をプロジェクト下に切る

このリポジトリでは `tools/rebuild_web.sh`, `tools/tests/run_tests.gd`, `tools/create_*.gd` がこのルールに従っている。

### blender-asset

Headless Blender (`blender --background --python`) で `.glb` を作るパイプライン。

- スキルが持つのは薄い helper だけ (`scripts/prelude.py` でシーン初期化と argv 解析、`scripts/export.py` で GLB 書き出し)
- プロジェクト固有の生成スクリプトは `assets/modeling/<name>.py` に書く
- 実行: `.agents/skills/blender-asset/build.sh assets/modeling/<name>.py`
- 出力: `assets/models/<name>.glb` (gitignore)、ログ: `logs/build_asset_<name>.log`
- 検証: `godot/check_glb.gd` で headless ロード確認、`godot/render_glb.gd` で 1 フレーム PNG 出力

押さえどころ:

- `bpy.ops.*` は headless context で落ちるので `bpy.data.*` / `bmesh.ops.*` で書く
- 円柱の側面は smooth shading、キャップは flat shading にしないと角張る
- `run(main)` で囲わないと Python 例外でも Blender は exit 0 を返してしまう (CI で気付けない)

実例: `assets/modeling/test_cube.py` (疎通)、`assets/modeling/shotgun.py` (Remington 870 風タクティカルパンプ)。

### image-asset

ラスター画像生成 (ドット絵キャラ、テクスチャ、UI モックなど) を `codex exec` 経由で codex 組み込みの `imagegen` スキルに投げる。

- リポジトリ内には画像生成器を持たず、codex 側に寄せる
- 既定の出力先は `asset/<slug>.png`
- SVG/CSS のプレースホルダで代用せず、ちゃんとビットマップを出す
- 書き出し後は `SAVED: <abs path>` 行で結果を引き取る規約

3D メッシュは `blender-asset`、2D ラスターは `image-asset` で棲み分け。
