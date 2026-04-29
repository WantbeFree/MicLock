cask "miclock" do
  version "1.6.6"
  sha256 "56d0aa77a090d1cb5a2853259b15678592585764b1a98932c2a02ad8e97ad47b"

  url "https://github.com/WantbeFree/MicLock/releases/download/v#{version}/MicLock.#{version}-macOS-arm64.zip"
  name "MicLock"
  desc "Keep macOS on the right microphone to avoid Bluetooth headset audio degradation"
  homepage "https://github.com/WantbeFree/MicLock"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"
  depends_on arch: :arm64

  app "MicLock #{version}.app", target: "MicLock.app"

  zap trash: [
    "~/Library/Preferences/com.wantbefree.miclock.plist",
  ]
end
