# Changelog

## 1.1.1

- Project and GitHub repository renamed to MacUtils; update checks and in-app links now use the new repository

## 1.1.0

- Renamed the app to MacUtils, with a new two-colour logo and a new website
- New: Caffeinate menu bar item that keeps your Mac (and optionally the display) awake for a chosen time or indefinitely
- New: clipboard manager. Hold ⌘⇧ and press V to open a picker in the middle of the screen, press V again to change the selection, release to paste
- Settings → General has a new Utilities section for both tools

## 1.0.1

- Fix: the downloaded release crashed at launch ("could not load resource bundle"); it only worked on the machine that built it

## 1.0.0

- First stable release
- README: explains the macOS "could not verify" warning for the unsigned app and how to open it

## 0.0.3

### Menu bar
- Menu bar widgets are now pure white or black (following the menu bar appearance); the colour theme no longer applies there
- CPU activity bars have an outline showing the full 100% extent
- Changing a setting updates the widgets in place instead of removing and re-adding them (no more blinking)

### Popovers
- Warning (orange) and danger (red) colours: disk at 75% / 90%, CPU at 70% / 90%, memory at 75% / 90%, battery at 20% / 10%, temperature at 80° / 95°C
- CPU history graph shows one line per core, each core a different colour in every theme
- Upload and download graphs use clearly different colours
- Text stays in the normal colour; the theme applies to graphs and bars only
- Popovers close when switching Spaces so they can be reopened on the new one
- Vertical scroll bars are hidden

### Widget builder
- Padding around the menu bar preview
- Weather no longer offers a duplicate icon element
- Clearer element names (e.g. "Speeds (stacked)", "Activity bars", "Display count")

### Fixes
- Weather now loads after login when the network isn't up yet: refetches when connectivity returns and retries after failures
- Cmd+Q closes the front window (e.g. Preferences) instead of quitting; quit from the menu bar item
