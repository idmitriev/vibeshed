cask "vibeshed" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE"

  url "https://github.com/idmitriev/vibeshed/releases/download/v#{version}/Vibeshed-#{version}.zip"
  name "Vibeshed"
  desc "Keyboard-driven macOS launcher"
  homepage "https://github.com/idmitriev/vibeshed"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Vibeshed.app"

  zap trash: [
    "~/.config/vibeshed",
    "~/Library/Preferences/com.ivandmitriev.Vibeshed.plist",
    "~/Library/Application Support/com.ivandmitriev.Vibeshed",
    "~/Library/Caches/com.ivandmitriev.Vibeshed",
    "~/Library/Saved Application State/com.ivandmitriev.Vibeshed.savedState",
  ]
end
