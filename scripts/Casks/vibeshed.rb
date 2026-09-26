cask "vibeshed" do
  version "0.4.0"
  sha256 "c6bc071fa515d8eaa481bcc5491bd5d749e513e7181b835ba98e8d526072814f"

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
