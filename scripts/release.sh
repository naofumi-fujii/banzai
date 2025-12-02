#!/bin/bash
#
# release.sh - Banzaiのリリーススクリプト
#
# 概要:
#   Cargo.tomlからバージョンを読み取り、Gitタグを作成してプッシュする。
#   タグのプッシュにより、GitHub Actionsのリリースワークフローがトリガーされる。
#
# 使い方:
#   ./scripts/release.sh
#
# 前提条件:
#   - 未コミットの変更がないこと
#   - 対象バージョンのタグが存在しないこと
#   - mainブランチがリモートと同期していること
#
set -e

# Cargo.tomlからバージョンを取得
VERSION=$(grep '^version' Cargo.toml | head -1 | sed 's/.*"\(.*\)".*/\1/')
TAG="v$VERSION"

echo "Releasing $TAG..."

# 未コミットの変更がないか確認
if [ -n "$(git status --porcelain)" ]; then
  echo "Error: uncommitted changes exist"
  exit 1
fi

# タグが既に存在するか確認
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Error: tag $TAG already exists"
  exit 1
fi

# pushしてタグを作成
git push
git tag "$TAG"
git push origin "$TAG"

echo "Done! Release $TAG has been triggered."
echo "Check: https://github.com/naofumi-fujii/banzai/actions"
