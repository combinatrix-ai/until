# Homebrew cask for Until, published from the combinatrix-ai/homebrew-tap
# repository as Casks/until.rb. After each release, update `version` and
# `sha256` (shasum -a 256 Until-v<version>.dmg) and push the tap.
cask "until" do
  version "1.2.0"
  sha256 "REPLACE_WITH_SHA256_OF_Until-v1.2.0.dmg"

  url "https://github.com/combinatrix-ai/until/releases/download/v#{version}/Until-v#{version}.dmg"
  name "Until"
  desc "Next meeting countdown, day timeline, and meeting notes in the menu bar"
  homepage "https://until.combinatrix.ai/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :ventura"

  app "Until.app"

  zap trash: [
    "~/Library/Application Support/Until",
    "~/Library/Caches/ai.combinatrix.until",
    "~/Library/Group Containers/3Y275A5TZ8.ai.combinatrix.until",
    "~/Library/HTTPStorages/ai.combinatrix.until",
    "~/Library/Preferences/ai.combinatrix.until.plist",
  ]
end
