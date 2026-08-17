# Rail Notes — native app

Voice-first capture for cocktail ideas. Speak or type a thought, and it flags
which ingredients you have already used and where, reading your recipe history
out of a Google Sheet. Nothing is generated or suggested — it only recalls.

One web codebase (`www/index.html`), wrapped by Capacitor into a real iOS and
Android app.

```
www/index.html        the whole app — UI, recall engine, Sheets sync
capacitor.config.json native shell config (CapacitorHttp on, so Sheets calls skip CORS)
ios/                  generated Xcode project + the native dictation plugin
android/              generated Android Studio project
scripts/              pbxproj patcher, re-runnable
.github/workflows/    cloud builds: Android APK, iOS → TestFlight
```

## What you need

| | Required | Cost |
|---|---|---|
| Android APK | a GitHub account | free |
| iOS TestFlight | Apple Developer Program | 99 USD/year |
| A Mac | **no** — both builds run on cloud runners | — |

## Getting the Android app

```bash
git init && git add -A && git commit -m "Rail Notes"
gh repo create rail-notes --private --source=. --push
```

Then **Actions → Android APK → Run workflow**. It produces a
`rail-notes-apk` artifact — download it on your phone and open it to install
(Android will ask you to allow installs from your browser).

It is a debug-signed build, which installs fine by sideloading. For the Play
Store you need a release keystore and a signing block in
`android/app/build.gradle`.

## Getting it onto your iPhone via TestFlight

Full setup steps are in the header comment of
[`.github/workflows/ios-testflight.yml`](.github/workflows/ios-testflight.yml).
The short version:

1. Enrol in the Apple Developer Program.
2. Register the bundle ID `com.jackrussell.railnotes`, then create the app
   record in App Store Connect.
3. Generate an App Store Connect API key (App Manager role) and save the `.p8`.
4. Add four repo secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`,
   `APPLE_TEAM_ID`.
5. **Actions → iOS TestFlight → Run workflow**, giving a build number.

Signing certificates are created automatically by Xcode through the API key, so
there is nothing to export by hand on a Mac you do not have.

## Connecting your Google Sheet

The app talks to a small Apps Script web app bound to your spreadsheet — see
`../sheets-bridge.gs`. Deploy it, then paste the `/exec` URL and your shared key
into **Library → Google Sheets** in the app.

`CapacitorHttp` is enabled, so requests go through the native HTTP stack and
CORS never applies. **Pull recipes** reads your sheet; **Push ideas** appends new
ones and never duplicates, because rows are matched on note ID.

## Dictation

Both platforms use the OS speech engine rather than the browser API:

- **Android** — `@capacitor-community/speech-recognition`
- **iOS** — `ios/App/App/SpeechRecognitionPlugin.swift`, written for this project
  because the community plugin ships no `Package.swift` and Capacitor 8's iOS
  build is SPM-only, so it would silently not compile in. It exposes the same JS
  API, so `www/index.html` needs no per-platform branching. Recognition runs
  on-device wherever iOS supports it.

`npx cap add ios` regenerates the Xcode project from a template and drops that
plugin's file reference, so re-run `npm run ios:prepare` afterwards. The script
is idempotent and fails loudly if the template changes rather than guessing.

## Working on it

```bash
npm install
npm run sync            # after editing www/index.html
npm run ios:prepare     # after any cap add ios
```

`www/index.html` opens directly in a browser for UI work — the native bits are
all feature-detected, and it falls back to the Web Speech API there.
