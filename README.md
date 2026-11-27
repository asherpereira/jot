# Jot

A local-first homework organiser based on the Pace specification. Capture a homework task in your own words, review the structured draft and save it. When you finish the task, Jot brings its follow-up reminders into Today. Open the repository root in VS Code to work on the shared app.

## Platform projects

| Device | Folder and entry point | Run on your machine |
| --- | --- | --- |
| iPhone and iPad, iOS/iPadOS 16+ | [ios](ios) · [Runner.xcodeproj](ios/Runner.xcodeproj) | On a Mac, use the Runner workspace after installing pods. Select an iPhone or iPad destination. |
| Android phones, tablets and foldables, API 26+ | [android](android) · Kotlin host and Gradle wrapper | Start an emulator or connect a device, then run `flutter run -d <device-id>` from the root. |
| macOS 12+ | [macos](macos) · [Runner.xcodeproj](macos/Runner.xcodeproj) | On a Mac, run `flutter run -d macos` or open the Runner workspace. |
| Windows 10/11, x64 | [windows](windows) · Win32 runner and CMake project | On Windows, install Visual Studio with **Desktop development with C++** and the Windows SDK. Run `flutter run -d windows` from the root. VS Code works as the editor. |
| Apple Watch, watchOS 10+ | [watchos](watchos) · [JotWatch.xcodeproj](watchos/JotWatch.xcodeproj) · SwiftUI | Run Runner on a paired iPhone, then select the JotWatch scheme and its paired watch simulator or device in Xcode. |
| Wear OS 3+, API 30+ | [wearos](wearos) · standalone Gradle project with Compose for Wear OS | Open this folder in Android Studio, select the watch and run the app module. Install the Android phone app on its paired phone. |

The four larger-screen targets share [the Flutter application](lib). iPad uses the universal iOS target. Android phones, tablets and foldables share one Android target that responds to the window size and hinge. Mac and Windows each have a desktop runner.

## Run the core app

The checked-in hosts use Flutter **3.38.5** and its bundled Dart SDK. Install that version for the first run. From the repository root:

```sh
flutter doctor
flutter pub get
flutter devices
flutter run -d <device-id>
```

Core capture, task editing and completion use an on-device Drift/SQLite database. No account, server or Gemini key is required for local capture. On Windows, enable Developer Mode if Flutter requests symlink support. On Android, use JDK 17 and an Android SDK installation including API 36. Wear OS can also be installed from its folder with `./gradlew :app:installDebug` or `gradlew.bat :app:installDebug`.

### Open the Apple projects in Xcode

Install Xcode, its platform SDKs, the Xcode command-line tools and CocoaPods. Run `flutter pub get` at the root first. Prepare the project for your chosen destination:

```sh
# iPhone / iPad / paired Apple Watch
flutter build ios --config-only --debug --no-codesign
(cd ios && pod install)
open ios/Runner.xcworkspace

# Mac
flutter build macos --config-only --debug
(cd macos && pod install)
open macos/Runner.xcworkspace
```

The Xcode projects, shared schemes and workspaces are committed. The iOS project references and embeds the watch app from its own Xcode project. Choose your development team in Signing & Capabilities for physical devices. If you change the iPhone bundle identifier, update the watch bundle identifier and its `WKCompanionAppBundleIdentifier` to match. For Wear OS, build both the watch and phone with the same application ID and signing certificate. Using the same computer's debug keystore is the simplest first run.

## Enable Gemini cloud capture

The [capture relay](server) holds your Gemini Developer API key and requests JSON with a fixed [versioned schema](contracts/capture-v1.schema.json). Only text you explicitly send using **Parse with Gemini** and its calendar context are sent. Drafts remain editable before saving. A relay or model failure leaves you with a local draft.

1. Install Node.js 22 or later. In `server/`, run `npm ci` and copy `.env.example` to `.env`.
2. Set `GEMINI_API_KEY` to your Google AI Studio API key. Set `JOT_ACCESS_TOKEN` to your own random relay token. Generate one with `node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"`. The relay model is configurable with `GEMINI_MODEL`.
3. Run `npm start` in `server/`. The relay listens on port 8787 on your computer's loopback interface.
4. In the repository root, copy `jot.local.example.json` to `jot.local.json`. Fill in the **relay token** and the address from the table. Keep the **Gemini key** in the relay's environment.
5. From the root, run `flutter run -d <device-id> --dart-define-from-file=jot.local.json`. For an Xcode launch, append the same define flag to the relevant `flutter build ... --config-only` command above, then open the workspace.

| Destination | Relay address |
| --- | --- |
| macOS or Windows app, relay running on that computer | `http://localhost:8787` |
| iOS Simulator, relay running on its Mac | `http://localhost:8787` |
| Android Studio emulator, relay on its host | `http://10.0.2.2:8787` in a debug build |
| Android phone over USB | Run `adb reverse tcp:8787 tcp:8787`, then use `http://localhost:8787` in a debug build. |
| Physical iPhone or a device on another computer | Use an HTTPS endpoint that forwards to your relay and is reachable from that device. |

The access token is for personal development builds. Use per-user authentication and quotas before distributing a client connected to a shared relay. Google manages model availability and billing against the key you configure. [Gemini API keys](https://ai.google.dev/gemini-api/docs/api-key) · [Structured output](https://ai.google.dev/gemini-api/docs/structured-output)

## Your Friday example

> yo i have maths homework due this friday maybe it will take an hour could u also remind me to upload all my work afterwards

Captured on Wednesday 25 November 2026, the expected draft has title **Maths homework**, subject **Maths**, due date **Friday 27 November**, estimate **60 minutes**, and **Upload all my work** under `afterCompletion`. A date without a stated time stays date-only. “This Friday” includes today if today is Friday. The exact expected payload is in [friday.example.json](contracts/friday.example.json).

Save the draft, then mark the homework complete. The upload reminder appears under **After finishing** and persists across restarts until you tick it off. These reminders currently appear inside Jot. Timed operating-system notifications are a later milestone.

## What is in this base

- **Today** highlights the next open task by date, priority and time. It groups other homework by due date and shows outstanding follow-ups.
- **Plan**, **Subjects** and **Insights** show a browsable week, tasks grouped by subject, and counts computed from the local database.
- **Capture and task detail** support editable titles, subjects, date and time, estimates, priority, notes, checkable steps and completion reminders. Tasks can be reopened, edited or deleted with undo.
- **Adaptive layouts** use compact navigation, a rail or sidebar, and list/detail panes. Wide book-style folds place the panes on opposite sides of the hinge. Compact or horizontally divided displays keep content in a usable sub-screen. Cmd/Ctrl+N opens capture.
- **Watch companions** cache up to eight open phone tasks and queue capture or completion actions. WatchConnectivity and the Wear Data Layer carry them to the phone. The phone processes pending actions when Jot opens, resumes or receives an active update. Replayed action IDs are applied once. A watch capture uses the local parser and the original capture date.
- Each phone or computer keeps its own database. Desktop/phone sync, backup and export, focus sessions, scheduled notifications, timetable editing, OCR, widgets and complications are still future work.

## First checks on your machines

1. Start without relay settings. Try the Friday example, review the fields, save it and relaunch.
2. Mark the task complete and confirm that the upload reminder remains available until acknowledged.
3. Configure the relay and repeat with **Parse with Gemini**. Stop the relay and confirm the local draft is still editable.
4. Resize a desktop or tablet window and try a book-style foldable emulator.
5. Pair a watch, capture homework while disconnected, reconnect and open Jot on the phone. Check that the task appears once.

Run `flutter test` in the repository root for the local parser and watch-action persistence fixtures. Run `npm test` in `server/` for the schema and mocked Gemini response fixtures. Live model calls require your key.
