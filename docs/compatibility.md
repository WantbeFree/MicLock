# MicLock Compatibility

MicLock works with macOS CoreAudio input devices on Apple Silicon Macs. It is most useful when Bluetooth headphones should stay output-only and another microphone should remain selected.

## Headphones

| Device | Status | Notes |
| --- | --- | --- |
| AirPods 1 | Expected | Keep a non-AirPods microphone selected |
| AirPods 2 | Expected | Keep a non-AirPods microphone selected |
| AirPods 3 | Expected | Keep a non-AirPods microphone selected |
| AirPods 4 | Expected | Keep a non-AirPods microphone selected |
| AirPods Pro 1 | Expected | Keep a non-AirPods microphone selected |
| AirPods Pro 2 | Expected | Keep a non-AirPods microphone selected |
| AirPods Pro 3 | Expected | Keep a non-AirPods microphone selected |
| AirPods Max | Expected | Keep a non-AirPods microphone selected |
| Sony WH-1000XM4 | Expected | Prevents Sony headset mic takeover |
| Sony WH-1000XM5 | Expected | Prevents Sony headset mic takeover |
| Sony WH-1000XM6 | Expected | Prevents Sony headset mic takeover |
| Sony WF-1000XM4 | Expected | Prevents Sony earbuds mic takeover |
| Sony WF-1000XM5 | Expected | Prevents Sony earbuds mic takeover |

## Microphones and interfaces

| Device or class | Status | Notes |
| --- | --- | --- |
| MacBook built-in microphone | Supported | Good fallback input |
| Elgato Wave XLR | Supported | Good primary input |
| Focusrite Scarlett | Expected | USB interface via CoreAudio |
| Shure MV7 | Expected | USB microphone via CoreAudio |
| Rode USB microphones | Expected | USB microphone via CoreAudio |
| Studio Display microphone | Expected | Display microphone via CoreAudio |
| Webcam microphones | Expected | USB/UVC microphone via CoreAudio |
| Thunderbolt docks | Expected | May need refresh after sleep |
| USB hubs | Expected | May need refresh after reconnect |

Open a [device compatibility report](https://github.com/WantbeFree/MicLock/issues/new?template=device_compatibility.yml) to add confirmed hardware.

