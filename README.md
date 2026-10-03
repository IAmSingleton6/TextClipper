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

Press **Escape** to cancel an active selection.

Open **Settings…** from the menu bar to customize the shortcut, launch at login, captured-text preview, and Screen Recording permission.

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
