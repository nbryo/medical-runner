# AI Generated Assets

ここに AI 生成画像を配置すると、該当する障害物 / キャラの見た目が自動で差し替わります。

## 対応ファイル

| ファイル名 | 差し替わる対象 | 期待サイズ |
|---|---|---|
| `senior_nurse.png` | Obstacle の `senior_nurse`(お局様ナース)の Sprite2D | 目安 80x110 前後。上下中央にキャラが収まっていれば `scale = Vector2(0.4, 0.4)` でだいたい合う |

ファイルが存在しない場合は既存の Kenney 画像(`female_stand.png`)で表示されます。
拡張したい場合は `Obstacle.gd` の `_try_apply_ai_senior_nurse_texture()` を参考に同じパターンで追加してください。
