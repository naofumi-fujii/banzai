# banzai

A macOS menu bar clipboard history manager.

## Features

- Automatically detects and saves clipboard changes
- Runs in the menu bar as a background application
- Persists history in JSONL format
- Removes duplicate entries (keeps the latest)
- Clear history from menu

## Installation

### Homebrew (recommended)

```bash
brew tap naofumi-fujii/banzai https://github.com/naofumi-fujii/banzai
brew install --cask banzai
```

### Build from source

```bash
cargo build --release
```

## Build App Bundle

```bash
cargo install cargo-bundle
cargo bundle --release
```

The app bundle is created at `target/release/bundle/osx/Banzai.app`.

To install to Applications:
```bash
cp -r target/release/bundle/osx/Banzai.app /Applications/
```

## Usage

```bash
# Run directly
cargo run

# Or open the app bundle
open target/release/bundle/osx/Banzai.app
```

After launching, a clipboard icon appears in the menu bar.
Copied content is automatically saved to history.

## History Location

- macOS: `~/Library/Application Support/banzai/clipboard_history.jsonl`

## Release

To create a new release:

1. Update version in `Cargo.toml`
2. Commit the change
3. Run the release script:
   ```bash
   ./scripts/release.sh
   ```

The GitHub Actions workflow will automatically build and publish the release.

