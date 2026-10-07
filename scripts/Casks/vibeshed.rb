cask "vibeshed" do
  version "0.8.0"
  sha256 "d85e6e9ed5ae869d5c9165b7e60e4c4a95dfe4d553fc1c2b91240793c5c5173b"

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
