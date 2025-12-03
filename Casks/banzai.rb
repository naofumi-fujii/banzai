cask "banzai" do
  version "0.4.0"
  sha256 "7339d6a8bcddf419563329bfba27938683f642354c05c2343b8a8f53999fc45a"

  url "https://github.com/naofumi-fujii/banzai/releases/download/v#{version}/Banzai-v#{version}.zip"
  name "Banzai"
  desc "macOS menu bar clipboard history monitor"
  homepage "https://github.com/naofumi-fujii/banzai"

  app "Banzai.app"

  zap trash: [
    "~/Library/Application Support/banzai",
  ]
end
