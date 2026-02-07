# Local Build + Run (boring.notch)

Use this when you change code and want the app binary to reflect your edits.

## 1) Edit code
Make your changes in this repo:
- `/Users/adamrakab/boring.notch`

## 2) Build to the same app path
Build with Xcode CLI to the same DerivedData location:

```bash
cd /Users/adamrakab/boring.notch
xcodebuild \
  -project boringNotch.xcodeproj \
  -scheme boringNotch \
  -configuration Debug \
  -derivedDataPath "/Users/adamrakab/Library/Developer/Xcode/DerivedData/boringNotch-feftrghknbgxktgrbucxtvvehodk" \
  build
```

If build succeeds, updated app is at:
- `/Users/adamrakab/Library/Developer/Xcode/DerivedData/boringNotch-feftrghknbgxktgrbucxtvvehodk/Build/Products/Debug/boringNotch.app`

## 3) Relaunch app
```bash
pkill -f "boringNotch.app/Contents/MacOS/boringNotch" || true
open -n "/Users/adamrakab/Library/Developer/Xcode/DerivedData/boringNotch-feftrghknbgxktgrbucxtvvehodk/Build/Products/Debug/boringNotch.app"
```

## Signing + keychain prompts
- Do **not** copy only the executable file around. Launch the full `.app` bundle.
- Keep bundle id and app path stable (same as above).
- Build using normal Xcode signing (`Sign to Run Locally` is fine for local dev).

If keychain prompts keep repeating:
1. Quit the app.
2. Open **Keychain Access** and remove old entries for this app (Google/boringNotch related).
3. Relaunch and sign in once again.

## Quick rollback of code changes
If a local edit goes bad and you want to reset repo files:

```bash
cd /Users/adamrakab/boring.notch
git restore --source=HEAD --staged --worktree .
```

(That restores tracked files to latest commit.)
