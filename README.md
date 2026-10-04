# ScreenText

A lightweight macOS menu bar app that turns anything on your screen into editable text.

Select an area, and ScreenText uses Apple's Vision framework to recognize the text and copy it to your clipboard. Everything is processed on-device.

<p align="center">
 <img src="Screenshots/preview.png" alt="ScreenText">
</p>


1. Move your pointer to the display containing the text.
2. Press **⌘⇧2**, or choose **Capture Text** from the menu bar.
3. Choose **Box** or **Draw**, then select the text.
4. Paste with **⌘V**.

The recognized text is copied to your clipboard automatically.

ScreenText is ready to capture immediately at launch. It uses fast text recognition while preparing its more accurate recognizer in the background, then switches automatically when preparation finishes. Early captures may be less accurate and support fewer languages. For captures taking longer than half a second, ScreenText shows **Reading text… Press Escape to cancel**. Captures still pending after 15 seconds are cancelled with a timeout message so you can try again. Pressing the capture shortcut again during processing keeps the pending capture running.

Press **Escape** to cancel a selection or pending text recognition.

Open **Settings…** from the menu bar to customize the shortcut, launch at login, captured-text preview, and Screen Recording permission.

## Install from a GitHub Release

ScreenText requires macOS 14 or later. Download the universal `.dmg` from [Releases](https://github.com/IAmSingleton6/TextClipper/releases), open it, and drag **ScreenText** into **Applications**. The same download supports Apple Silicon and Intel Macs.

These releases do not have a Developer ID signature and are not notarized by Apple. macOS may block the first launch because it cannot verify the developer. After attempting to open ScreenText, open **System Settings → Privacy & Security → Open Anyway**, then confirm. See [Apple's instructions](https://support.apple.com/en-us/102445).

Grant **Screen Recording** permission when prompted, and restart ScreenText if required.

## Build from source

### Requirements

- macOS 14+
- Xcode 16.4+ with Swift 6.2+
- Homebrew
- Screen Recording permission

Open `ScreenText.xcodeproj` in Xcode, select the **ScreenText** scheme, and press **Run**.

On first launch, grant **Screen Recording** permission when prompted. If required, restart ScreenText after granting access.

For command-line builds and project checks, install the required tools:

```
brew install swiftformat swiftlint
```

The repository includes Git hooks for formatting and linting. Enable them with:

```
git config core.hooksPath .githooks
```

## Notes

The scheme also builds, embeds, and signs the dedicated `AccurateOCRHelper` target. Fast OCR runs in the main app; accurate OCR stays in the persistent helper. This is to allow the app to use fast OCR until the accurate OCR is warm in the separate process.
