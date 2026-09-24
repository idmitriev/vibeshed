cask "vibeshed" do
  version "0.2.0"
  sha256 "812a9ccf8124a08e086c2a7e7b9b9e402311d284c9b771f47a4c088d82215070"

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
