# 福生市 人材資源マップ

福生市で活動する市民団体を、Leafletの地図で見つけるMVPです。
断酒でGO!!とはDB・リポジトリともに独立しています。

## データ生成

tyoの独立DBから、公開用フィールドだけを静的JSONへ出力します。

```bash
python3 scripts/generate_circles_json.py \
  --db /home/maji/fussa_jinzai.db \
  --output /tmp/circles.json
```

出力対象は`circles.is_hidden=0`かつ座標ありの団体だけです。電話、メール、
代表者名、raw_fields、連絡先公開状態はJSONへ出力しません。

## ローカル確認

```bash
python3 -m http.server 8000
```

ブラウザで`http://127.0.0.1:8000/`を開きます。

## テスト

```bash
python3 -m unittest -v tests/test_generate_circles_json.py
```
