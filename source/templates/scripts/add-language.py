#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Add a new language to Android project.

Usage:
  python3 scripts/add-language.py <lang_id>

Example:
  python3 scripts/add-language.py es    # Add Spanish
  python3 scripts/add-language.py ru    # Add Russian

Reference:
  ~/.claude-kit/config/i18n-languages.yaml (master language list)
  config/i18n-config.yaml (project language config)
  docs/i18n-android-standard.md (policy)
"""

import yaml
import subprocess
import shutil
import sys
import io
from pathlib import Path

# Force UTF-8 output on Windows
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')


def load_master_languages():
    """Load master language list from engineer-claude-kit."""
    kit_home = Path.home() / '.claude-kit'
    lang_master_path = kit_home / 'config' / 'i18n-languages.yaml'

    if not lang_master_path.exists():
        print(f"❌ マスター言語リストが見つかりません: {lang_master_path}")
        return None

    try:
        with open(lang_master_path, encoding='utf-8') as f:
            data = yaml.safe_load(f)
        return data.get('languages_master', {})
    except Exception as e:
        print(f"❌ マスター言語リストの読み込みに失敗: {e}")
        return None


def load_project_config():
    """Load project i18n config."""
    config_path = Path('config/i18n-config.yaml')
    if not config_path.exists():
        print(f"❌ プロジェクト設定が見つかりません: {config_path}")
        return None

    try:
        with open(config_path, encoding='utf-8') as f:
            return yaml.safe_load(f)
    except Exception as e:
        print(f"❌ プロジェクト設定の読み込みに失敗: {e}")
        return None


def save_project_config(config):
    """Save project i18n config."""
    config_path = Path('config/i18n-config.yaml')
    try:
        with open(config_path, 'w', encoding='utf-8') as f:
            yaml.dump(config, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    except Exception as e:
        print(f"❌ プロジェクト設定の保存に失敗: {e}")
        return False
    return True


def add_language(lang_id):
    """Add a language to the project."""

    # Load master and project configs
    master = load_master_languages()
    if not master:
        return False

    config = load_project_config()
    if not config:
        return False

    # Check if language exists in master
    if lang_id not in master:
        print(f"❌ 言語 '{lang_id}' はマスターリストに存在しません")
        print(f"   利用可能な言語: {', '.join(sorted(master.keys()))}")
        return False

    lang_info = master[lang_id]
    tier = f"tier{lang_info['tier']}"

    # Check if already exists in project
    for tier_key in ['tier1', 'tier2', 'tier3']:
        for lang in config['i18n']['languages'].get(tier_key, []):
            if lang['id'] == lang_id:
                print(f"⚠️ '{lang_id}' は既に {tier_key} に存在します")
                return True

    # Add to config
    if tier not in config['i18n']['languages']:
        config['i18n']['languages'][tier] = []

    config['i18n']['languages'][tier].append({
        'id': lang_id,
        'name': lang_info['name_native'],
        'longitude': lang_info['longitude']
    })

    # Sort by longitude within tier
    config['i18n']['languages'][tier].sort(key=lambda x: x['longitude'])

    if not save_project_config(config):
        return False

    # Create strings.xml file (copy from English)
    values_dir = lang_info['values_dir']
    if values_dir == '(root)':
        print(f"ℹ️ English (root) は既に存在します")
        return True

    res_dir = Path('app/src/main/res') / values_dir
    try:
        res_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy(
            'app/src/main/res/values/strings.xml',
            res_dir / 'strings.xml'
        )
    except Exception as e:
        print(f"❌ strings.xml の作成に失敗: {e}")
        return False

    # Run regen_columns.py
    try:
        result = subprocess.run(['python3', 'regen_columns.py'],
                              capture_output=True, text=True, check=True)
        print(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"❌ regen_columns.py の実行に失敗: {e.stderr}")
        return False

    # Git commit
    try:
        subprocess.run(['git', 'add',
                       'config/i18n-config.yaml',
                       str(res_dir / 'strings.xml'),
                       'string_columns.json'],
                      check=True, capture_output=True)
        subprocess.run(['git', 'commit', '--no-verify',
                       '-m', f'feat(i18n): Add {lang_id} ({lang_info["name_native"]})'],
                      check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        print(f"⚠️ git コミットに失敗: {e.stderr.decode() if e.stderr else e}")
        return False

    print(f"✅ '{lang_id}' ({lang_info['name_native']}) を {tier} に追加しました")
    return True


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f"使用法: python3 {sys.argv[0]} <lang_id>")
        print(f"例: python3 {sys.argv[0]} es")
        sys.exit(1)

    lang_id = sys.argv[1]
    success = add_language(lang_id)
    sys.exit(0 if success else 1)
