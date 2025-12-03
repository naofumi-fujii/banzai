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

# セマンティックバージョンを比較する関数
# 戻り値: 0 = 等しい, 1 = $1 > $2, 2 = $1 < $2
version_compare() {
  if [ "$1" = "$2" ]; then
    return 0
  fi

  local IFS=.
  local i ver1=($1) ver2=($2)

  # 配列の長さを揃える
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
    ver1[i]=0
  done
  for ((i=${#ver2[@]}; i<${#ver1[@]}; i++)); do
    ver2[i]=0
  done

  for ((i=0; i<${#ver1[@]}; i++)); do
    if ((10#${ver1[i]} > 10#${ver2[i]})); then
      return 1
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]})); then
      return 2
    fi
  done
  return 0
}

# 現在のバージョンを取得
CURRENT_VERSION=$(grep '^version' Cargo.toml | head -1 | sed 's/.*"\(.*\)".*/\1/')

# 指定されたバージョンが現在のバージョン以下かチェック
NEW_VERSION="$1"
version_compare "$NEW_VERSION" "$CURRENT_VERSION" || cmp_result=$?
cmp_result=${cmp_result:-0}

if [ $cmp_result -eq 0 ]; then
  echo "Error: 指定されたバージョン $NEW_VERSION は現在のバージョン $CURRENT_VERSION と同じです"
  exit 1
elif [ $cmp_result -eq 2 ]; then
  echo "Error: 指定されたバージョン $NEW_VERSION は現在のバージョン $CURRENT_VERSION より低いです"
  exit 1
fi

# Cargo.tomlのバージョンを更新
echo "Updating version to $NEW_VERSION..."
sed -i '' "s/^version = \".*\"/version = \"$NEW_VERSION\"/" Cargo.toml
cargo build --quiet 2>/dev/null || cargo build
git add Cargo.toml Cargo.lock
git commit -m "バージョンを${NEW_VERSION}に更新"

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
