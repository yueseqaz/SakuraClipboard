cask "sakura-clipboard" do
  version "1.0.2"
  sha256 "baad327a7471432e1e111e1972769c52f8876b77c8f9c52d51cd99dfd4719b7e"

  url "https://github.com/yueseqaz/SakuraClipboard/releases/download/v#{version}/SakuraClipboard.dmg"
  name "SakuraClipboard"
  desc "Lightweight macOS menu bar clipboard history app"
  homepage "https://github.com/yueseqaz/SakuraClipboard"

  depends_on macos: ">= :big_sur"

  app "SakuraClipboard.app"

  zap trash: [
    "~/Library/Application Support/SakuraClipboard",
    "~/Library/Preferences/com.sakura.clipboard.plist",
    "~/Library/Caches/com.sakura.clipboard",
  ]
end
