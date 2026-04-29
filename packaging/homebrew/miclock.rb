cask "miclock" do
  version "1.6.5"
  sha256 "2ac811b12bc1c847cd624f364198c473e8a057ac5c94165e41673178f4c8311b"

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
