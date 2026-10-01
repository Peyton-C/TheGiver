# The Giver
An application picker for macOS and Linux that gets the job done.

The Giver is a clone of [Junction](https://github.com/sonnyp/Junction). Make it the default application for a kind of file or for web links, and opening one shows a row of the applications that can take it, above the path or URL, which you can edit first.

## Build
### macOS
Needs macOS 26 and Xcode, not just the Command Line Tools, which lack SwiftUI's macros:

```sh
macos/bundle.sh            # build/macos/The Giver.app
macos/bundle.sh --install  # and copy it to /Applications
```

### Linux
Needs GTK 4.12+ and Meson:

```sh
meson setup build
ninja -C build
./build/linux/the-giver song.stem.mp4
sudo ninja -C build install   # optional: installs the app and its desktop entry
```

## Setup
The Giver only appears for things it is the default application for.

On macOS, open The Giver on its own for its settings. Use The Giver for Web Links makes it the default browser. Choose a File makes it the default for every file of that kind, and the list above the button gives a kind back to the application that had it before.

On Linux, choose The Giver in Settings under Default Applications, in a file's Open With dialog, or with `xdg-mime default io.github.peyton_c.TheGiver.desktop video/mp4`.

## Keys

| Key | What |
| --- | --- |
| Left, Right | Move between applications |
| Return | Open with the selected application |
| 1 to 9 | Open with the application in that place |
| Command (Control on Linux) with Return, a digit or a click | Open and keep the picker |
| Escape | Close |

## Arrangement
On macOS, drag an application to move it, or right-click it for Move Left, Move Right and Hide. Hidden applications come back from the picker's menu. The Giver keeps the order and the hidden applications per kind of file and per link scheme, so hiding Books for MPEG-4 movies leaves it in place for EPUBs.

macOS types a file by its last extension, so a `.stem.mp4` is just another MPEG-4 movie. The Giver treats the name endings listed in its settings as kinds of their own, `.stem.mp4` among them from the start, so you can hide QuickTime Player for stems and Track 10 for videos.

The Linux frontend cannot rearrange or hide applications yet.

## Layout

| Path | What |
| --- | --- |
| `macos/` | SwiftUI frontend |
| `linux/` | GTK 4 frontend |
