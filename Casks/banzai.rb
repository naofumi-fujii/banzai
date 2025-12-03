cask "banzai" do
  version "0.7.0"
  sha256 "d0cacde044dd2caf9d8b6d6879da2a0f93572b71ed1bd09ca1f014dd81cc3112"

  url "https://github.com/naofumi-fujii/banzai/releases/download/v#{version}/Banzai-v#{version}.zip"
  name "Banzai"
  desc "macOS menu bar clipboard history monitor"
  homepage "https://github.com/naofumi-fujii/banzai"

  app "Banzai.app"

  zap trash: [
    "~/Library/Application Support/banzai",
  ]
end
