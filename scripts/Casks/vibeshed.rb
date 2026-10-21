cask "vibeshed" do
  version "0.12.0"
  sha256 "719193e23aa7bea58111378c468884338c3e0bea3c604412ca0485e14077c284"

  url "https://github.com/vibeshed/vibeshed/releases/download/v#{version}/Vibeshed-#{version}.zip"
  name "Vibeshed"
  desc "Keyboard-driven launcher"
  homepage "https://vibeshed.dev"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Vibeshed.app"

  zap trash: [
    "~/.config/vibeshed",
    "~/Library/Application Support/com.ivandmitriev.Vibeshed",
    "~/Library/Caches/com.ivandmitriev.Vibeshed",
    "~/Library/Preferences/com.ivandmitriev.Vibeshed.plist",
    "~/Library/Saved Application State/com.ivandmitriev.Vibeshed.savedState",
  ]
end
