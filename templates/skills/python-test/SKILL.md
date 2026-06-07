---
name: python-test
description: |
  Python プロジェクトの pytest 実行・virtualenv 管理・依存解決を支援する skill。
  user が pytest / venv / pip 等を依頼したときに起動。
---

# python-test

Python プロジェクトの test 実行 / 仮想環境 (virtualenv = 仮想環境) 管理を支援する。

## 起動条件

user の依頼に以下のキーワードが含まれるとき:
- 「pytest」「test」「テスト」
- 「venv」「virtualenv」「仮想環境」
- 「pip」「poetry」「pipenv」「requirements」

## 主要コマンド

### venv
```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1           # Windows PowerShell
deactivate                             # 退出
```

### Test
```powershell
pytest                                 # 全 test
pytest tests/test_module.py            # 個別 file
pytest -k "test_name"                  # 名前 filter
pytest --cov=src                       # coverage
```

### 依存
```powershell
pip install -r requirements.txt
pip install -e .                       # editable (development) install
pip freeze > requirements.txt
```

## 制約

- 必ず venv (or conda) で隔離する (system Python を汚さない)
- requirements.txt は pinning を保持 (`==` で version 固定)
- poetry / pipenv / uv 使用の場合はそれぞれの慣例に従う

## Refs

- pytest docs: https://docs.pytest.org/
- venv: https://docs.python.org/3/library/venv.html
