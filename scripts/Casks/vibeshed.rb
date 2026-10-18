cask "vibeshed" do
  version "0.11.0"
  sha256 "3628242b06aad433e1d642d279b35772a0659ce9bd9d56da2f09cba7bbb203d6"

  url "https://github.com/idmitriev/vibeshed/releases/download/v#{version}/Vibeshed-#{version}.zip"
  name "Vibeshed"
  desc "Keyboard-driven launcher"
  homepage "https://github.com/idmitriev/vibeshed"

  livecheck do
    url :url
    strategy :github_latest
  end

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
