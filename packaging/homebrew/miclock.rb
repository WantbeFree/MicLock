cask "miclock" do
  version "1.7.1"
  sha256 "77d2ac266372426224bf60dff84ac51c5bdfd540f1832957e305d9636abd4d1f"

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

  app "MicLock.app"

  zap trash: [
    "~/Library/Preferences/com.wantbefree.miclock.plist",
  ]
end
