# Freeloader
-------

### An interactive reading tool for GEN-Z hyperactivists.

---

## Build & install (macOS)

Requires Xcode. Build the Release app and copy it into `/Applications`:

```sh
xcodebuild -project Freeloader.xcodeproj \
  -scheme Freeloader \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/local \
  clean build

cp -R build/local/Build/Products/Release/Freeloader.app /Applications/
```

The app is signed to run locally ("Sign to Run Locally"), so no developer account is needed. Launch it from `/Applications` or with `open /Applications/Freeloader.app`.

---

*freeloader* - wahringer oss
