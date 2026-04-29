cask "miclock" do
  version "1.6.7"
  sha256 "f6722dc97f848a3ddc52339e3b2b3a3fa0d487132a7c99d44d396f79e44ce444"

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
