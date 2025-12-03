#!/usr/bin/env npx tsx
/**
 * release.ts - Banzaiのリリーススクリプト
 *
 * 概要:
 *   複数のファイル(Cargo.toml, package.json, tauri.conf.json)のバージョンを更新し、
 *   Gitタグを作成してプッシュする。
 *   タグのプッシュにより、GitHub Actionsのリリースワークフローがトリガーされる。
 *
 * 使い方:
 *   npx tsx scripts/release.ts
 *
 * 前提条件:
 *   - 対象バージョンのタグが存在しないこと
 *   - mainブランチがリモートと同期していること
 */

import { execSync } from "child_process";
import * as fs from "fs";
import * as path from "path";
import * as readline from "readline";

const ROOT_DIR = path.resolve(import.meta.dirname, "..");
const VERSION_FILES = {
  cargo: path.join(ROOT_DIR, "src-tauri/Cargo.toml"),
  package: path.join(ROOT_DIR, "package.json"),
  tauri: path.join(ROOT_DIR, "src-tauri/tauri.conf.json"),
};

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

function prompt(question: string): Promise<string> {
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      resolve(answer.trim());
    });
  });
}

function exec(command: string): string {
  return execSync(command, { cwd: ROOT_DIR, encoding: "utf-8" }).trim();
}

function execSilent(command: string): string | null {
  try {
    return execSync(command, {
      cwd: ROOT_DIR,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch {
    return null;
  }
}

function getCurrentVersions(): Record<string, string> {
  const versions: Record<string, string> = {};

  // Cargo.toml
  const cargoContent = fs.readFileSync(VERSION_FILES.cargo, "utf-8");
  const cargoMatch = cargoContent.match(/^version\s*=\s*"([^"]+)"/m);
  versions.cargo = cargoMatch?.[1] ?? "unknown";

  // package.json
  const packageJson = JSON.parse(
    fs.readFileSync(VERSION_FILES.package, "utf-8")
  );
  versions.package = packageJson.version;

  // tauri.conf.json
  const tauriJson = JSON.parse(fs.readFileSync(VERSION_FILES.tauri, "utf-8"));
  versions.tauri = tauriJson.version;

  return versions;
}

function validateVersion(version: string): boolean {
  return /^\d+\.\d+\.\d+$/.test(version);
}

function compareVersions(a: string, b: string): number {
  const partsA = a.split(".").map(Number);
  const partsB = b.split(".").map(Number);

  for (let i = 0; i < 3; i++) {
    if (partsA[i] > partsB[i]) return 1;
    if (partsA[i] < partsB[i]) return -1;
  }
  return 0;
}

function updateVersionInFiles(newVersion: string): void {
  // Cargo.toml
  let cargoContent = fs.readFileSync(VERSION_FILES.cargo, "utf-8");
  cargoContent = cargoContent.replace(
    /^version\s*=\s*"[^"]+"/m,
    `version = "${newVersion}"`
  );
  fs.writeFileSync(VERSION_FILES.cargo, cargoContent);

  // package.json
  const packageJson = JSON.parse(
    fs.readFileSync(VERSION_FILES.package, "utf-8")
  );
  packageJson.version = newVersion;
  fs.writeFileSync(
    VERSION_FILES.package,
    JSON.stringify(packageJson, null, 2) + "\n"
  );

  // tauri.conf.json
  const tauriJson = JSON.parse(fs.readFileSync(VERSION_FILES.tauri, "utf-8"));
  tauriJson.version = newVersion;
  fs.writeFileSync(
    VERSION_FILES.tauri,
    JSON.stringify(tauriJson, null, 2) + "\n"
  );
}

async function main() {
  console.log("🚀 Banzai Release Script\n");

  // 現在のバージョンを表示
  const currentVersions = getCurrentVersions();
  console.log("現在のバージョン:");
  console.log(`  Cargo.toml:      ${currentVersions.cargo}`);
  console.log(`  package.json:    ${currentVersions.package}`);
  console.log(`  tauri.conf.json: ${currentVersions.tauri}`);

  // バージョンの不一致をチェック
  const uniqueVersions = new Set(Object.values(currentVersions));
  if (uniqueVersions.size > 1) {
    console.log("\n⚠️  警告: バージョンが一致していません");
  }

  const currentVersion = currentVersions.cargo;
  console.log("");

  // 未コミットの変更をチェック
  const status = exec("git status --porcelain");
  if (status) {
    console.log("⚠️  未コミットの変更があります:");
    console.log(status);
    const proceed = await prompt("\n続行しますか? [y/N]: ");
    if (proceed.toLowerCase() !== "y") {
      console.log("キャンセルしました");
      rl.close();
      process.exit(0);
    }
  }

  // 新しいバージョンを入力
  const newVersion = await prompt(
    `新しいバージョンを入力 (現在: ${currentVersion}): `
  );

  if (!newVersion) {
    console.log("バージョンが入力されませんでした");
    rl.close();
    process.exit(1);
  }

  if (!validateVersion(newVersion)) {
    console.log("❌ 無効なバージョン形式です (例: 0.11.0)");
    rl.close();
    process.exit(1);
  }

  if (compareVersions(newVersion, currentVersion) <= 0) {
    console.log(
      `❌ 新しいバージョン (${newVersion}) は現在のバージョン (${currentVersion}) より大きい必要があります`
    );
    rl.close();
    process.exit(1);
  }

  // タグが既に存在するかチェック
  const tag = `v${newVersion}`;
  if (execSilent(`git rev-parse ${tag}`) !== null) {
    console.log(`❌ タグ ${tag} は既に存在します`);
    rl.close();
    process.exit(1);
  }

  // 実行内容の確認
  console.log("\n以下の操作を実行します:");
  console.log(`  1. バージョンを ${newVersion} に更新`);
  console.log("     - src-tauri/Cargo.toml");
  console.log("     - package.json");
  console.log("     - src-tauri/tauri.conf.json");
  console.log(`  2. cargo build (Cargo.lockを更新)`);
  console.log(`  3. git commit`);
  console.log(`  4. git push`);
  console.log(`  5. git tag ${tag}`);
  console.log(`  6. git push origin ${tag}`);

  const confirm = await prompt("\n続行しますか? [y/N]: ");
  if (confirm.toLowerCase() !== "y") {
    console.log("キャンセルしました");
    rl.close();
    process.exit(0);
  }

  console.log("");

  // バージョンを更新
  console.log("📝 バージョンを更新中...");
  updateVersionInFiles(newVersion);

  // cargo buildでCargo.lockを更新
  console.log("📦 cargo build を実行中...");
  exec("cd src-tauri && cargo build --quiet");

  // git commit
  console.log("📝 変更をコミット中...");
  exec("git add src-tauri/Cargo.toml src-tauri/Cargo.lock package.json src-tauri/tauri.conf.json");
  exec(`git commit -m "バージョンを${newVersion}に更新"`);

  // git push
  console.log("⬆️  コミットをプッシュ中...");
  exec("git push");

  // git tag
  console.log(`🏷️  タグ ${tag} を作成中...`);
  exec(`git tag ${tag}`);

  // git push tag
  console.log(`⬆️  タグ ${tag} をプッシュ中...`);
  exec(`git push origin ${tag}`);

  console.log(`\n✅ リリース ${tag} が完了しました!`);
  console.log("👉 https://github.com/naofumi-fujii/banzai/actions");

  rl.close();
}

main().catch((error) => {
  console.error("❌ エラー:", error.message);
  rl.close();
  process.exit(1);
});
