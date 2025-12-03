#!/bin/bash
#
# release.sh - Banzaiのリリーススクリプト
#
# 概要:
#   Cargo.tomlからバージョンを読み取り、Gitタグを作成してプッシュする。
#   タグのプッシュにより、GitHub Actionsのリリースワークフローがトリガーされる。
#
# 使い方:
#   ./scripts/release.sh          # Cargo.tomlの現在のバージョンでリリース
#   ./scripts/release.sh 0.4.0    # バージョンを0.4.0に更新してリリース
#
# 前提条件:
#   - 対象バージョンのタグが存在しないこと
#   - mainブランチがリモートと同期していること
#
set -e

usage() {
  echo "Usage: $0 VERSION"
  echo ""
  echo "Banzaiのリリーススクリプト"
  echo ""
  echo "引数:"
  echo "  VERSION    新しいバージョン番号 (例: 0.4.0)"
  echo ""
  echo "例:"
  echo "  $0 0.4.0    # バージョンを0.4.0に更新してリリース"
  exit 0
}

if [ -z "$1" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
fi

# Cargo.tomlのバージョンを更新
if [ -n "$1" ]; then
  NEW_VERSION="$1"
  echo "Updating version to $NEW_VERSION..."
  sed -i '' "s/^version = \".*\"/version = \"$NEW_VERSION\"/" Cargo.toml
  cargo build --quiet 2>/dev/null || cargo build
  git add Cargo.toml Cargo.lock
  git commit -m "バージョンを${NEW_VERSION}に更新"
fi

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

# 確認ダイアログ
echo ""
echo "以下の操作を実行します:"
echo "  1. git push (コミットをプッシュ)"
echo "  2. git tag $TAG (タグを作成)"
echo "  3. git push origin $TAG (タグをプッシュ)"
echo ""
read -p "続行しますか? [y/N]: " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
  echo "キャンセルしました"
  exit 0
fi

# pushしてタグを作成
git push
git tag "$TAG"
git push origin "$TAG"

echo "Release $TAG has been triggered."
echo "Check: https://github.com/naofumi-fujii/banzai/actions"
echo ""
echo "GitHub Actionsのリリース完了を待っています..."

# リリースワークフローの完了を待つ
while true; do
  STATUS=$(gh run list --workflow=release.yml --limit=1 --json status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"')
  RUN_STATUS=$(echo "$STATUS" | cut -d' ' -f1)
  CONCLUSION=$(echo "$STATUS" | cut -d' ' -f2)

  if [ "$RUN_STATUS" = "completed" ]; then
    if [ "$CONCLUSION" = "success" ]; then
      echo "リリースワークフローが完了しました"
      break
    else
      echo "Error: リリースワークフローが失敗しました (conclusion: $CONCLUSION)"
      exit 1
    fi
  fi

  echo "  待機中... (status: $RUN_STATUS)"
  sleep 10
done

# Caskファイルを更新
echo ""
echo "Caskファイルを更新しています..."
RELEASE_URL="https://github.com/naofumi-fujii/banzai/releases/download/$TAG/Banzai-$TAG.zip"
SHA256=$(curl -sL "$RELEASE_URL" | shasum -a 256 | cut -d' ' -f1)

if [ -z "$SHA256" ] || [ "$SHA256" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]; then
  echo "Error: SHA256の取得に失敗しました"
  exit 1
fi

sed -i '' "s/^  version \".*\"/  version \"$VERSION\"/" Casks/banzai.rb
sed -i '' "s/^  sha256 \".*\"/  sha256 \"$SHA256\"/" Casks/banzai.rb

git add Casks/banzai.rb
git commit -m "Cask: バージョンを${VERSION}に更新"
git push

echo ""
echo "Done! Caskも更新されました。"
echo "brew upgrade --cask banzai でアップグレードできます。"
