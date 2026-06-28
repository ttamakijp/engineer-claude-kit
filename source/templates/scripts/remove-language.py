#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Remove a language from Android project.

Usage:
  python3 scripts/remove-language.py <lang_id>

Example:
  python3 scripts/remove-language.py es    # Remove Spanish

Note:
  Cannot remove languages listed in creator_mandatory_languages.

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


def remove_language(lang_id):
    """Remove a language from the project."""

    # Load master and project configs
    master = load_master_languages()
    if not master:
        return False

    config = load_project_config()
    if not config:
        return False

    # Check if mandatory language
    mandatory = config['i18n'].get('creator_mandatory_languages', [])
    if lang_id in mandatory:
        print(f"❌ '{lang_id}' は必須言語（creator_mandatory_languages）のため削除できません")
        return False

    # Find and remove from config
    found = False
    for tier_key in ['tier1', 'tier2', 'tier3']:
        config['i18n']['languages'][tier_key] = [
            lang for lang in config['i18n']['languages'].get(tier_key, [])
            if lang['id'] != lang_id
        ]
        if len(config['i18n']['languages'][tier_key]) < len(config['i18n']['languages'].get(tier_key, [])):
            found = True

    if not found:
        print(f"⚠️ '{lang_id}' はプロジェクト設定に存在しません")
        return True

    if not save_project_config(config):
        return False

    # Remove strings.xml directory
    if lang_id in master:
        values_dir = master[lang_id]['values_dir']
        if values_dir != '(root)':
            res_dir = Path('app/src/main/res') / values_dir
            try:
                if res_dir.exists():
                    shutil.rmtree(res_dir)
            except Exception as e:
                print(f"⚠️ ディレクトリの削除に失敗: {e}")

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
        subprocess.run(['git', 'add', 'config/i18n-config.yaml', 'string_columns.json'],
                      check=True, capture_output=True)
        if lang_id in master:
            values_dir = master[lang_id]['values_dir']
            if values_dir != '(root)':
                res_dir = Path('app/src/main/res') / values_dir
                subprocess.run(['git', 'rm', '-r', str(res_dir)],
                             check=True, capture_output=True)

        lang_name = master.get(lang_id, {}).get('name_native', lang_id)
        subprocess.run(['git', 'commit', '--no-verify',
                       '-m', f'feat(i18n): Remove {lang_id} ({lang_name})'],
                      check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        print(f"⚠️ git コミットに失敗: {e.stderr.decode() if e.stderr else e}")
        return False

    print(f"✅ '{lang_id}' を削除しました")
    return True


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f"使用法: python3 {sys.argv[0]} <lang_id>")
        print(f"例: python3 {sys.argv[0]} es")
        sys.exit(1)

    lang_id = sys.argv[1]
    success = remove_language(lang_id)
    sys.exit(0 if success else 1)
