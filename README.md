# WakeFox

A simple macOS menubar application to send Wake-on-LAN magic packets to preconfigured interfaces.

## Build and run

This project intentionally does not include Apple code signing or notarization. Build it with Swift Package Manager, then run the generated executable on macOS.

If macOS blocks the downloaded or copied executable, remove the quarantine attribute yourself:

```sh
xattr -dr com.apple.quarantine /path/to/WakeFox
```

No project license has been selected yet.
