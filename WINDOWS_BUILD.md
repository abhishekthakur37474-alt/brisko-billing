# Brisko Billing — Windows build & packaging (developer)

This is the developer procedure for producing the Windows deployment package. It is **not**
for the client; the client uses `CLIENT_SETUP.md`.

The development machine used so far is a Mac. A Windows **release build cannot be compiled
on macOS** — it must be produced on a Windows 10/11 x64 host with the Flutter Windows
toolchain installed. Everything below runs on that Windows host.

## 1. Prerequisites (Windows host)

- Windows 10 or 11, x64
- Flutter SDK (stable), matching the version used in development (3.47.x)
- Visual Studio 2022 with the **Desktop development with C++** workload
- Confirm the toolchain:

  ```
  flutter doctor -v
  ```

  The "Visual Studio - develop Windows apps" line must be a check, not a cross.

## 2. Fetch dependencies

```
flutter pub get
```

## 3. Build the release

Local-only build (no cloud; the app opens straight to the till, no login screen):

```
flutter build windows --release
```

Cloud-connected build (adds the login screen and Firestore sync). Supply the project's
**client-safe** values as compile-time defines — they are baked into the build, the same
for every terminal, and are never typed into the app:

```
flutter build windows --release ^
  --dart-define=BRISKO_FIREBASE_PROJECT_ID=<your-project-id> ^
  --dart-define=BRISKO_FIREBASE_API_KEY=<your-web-api-key>
```

> The Firebase **service-account key is never used here.** Only the project id and Web API
> key are client-safe. Access is controlled server-side by `firebase/firestore.rules`.
> See `firebase/README.md` for creating the terminal's login user.

The build output is the **complete** application directory:

```
build\windows\x64\runner\Release\
    brisko_billing.exe
    flutter_windows.dll
    *.dll            (plugin + ICU runtime)
    data\            (flutter_assets, incl. the Brisko receipt logo)
```

All of this ships together. `brisko_billing.exe` alone will not start.

## 4. Package for the client (release folder + zip)

From the repository root on the Windows host:

```
powershell -ExecutionPolicy Bypass -File windows\packaging\package_release.ps1
```

This copies the entire release output and produces:

```
dist\Brisko-Billing-Windows-x64-Release\        (unpacked, runnable)
dist\Brisko-Billing-Windows-x64-Release.zip      (hand this to the client)
```

The client unzips it anywhere and double-clicks `brisko_billing.exe`. No developer tools
are required on the client machine. This is the primary, always-works distribution method
and needs no extra packages.

## 5. Optional — MSIX installer (double-click installer)

MSIX is **not configured** in this project today (no installer dependency is present, on
purpose — nothing untested is shipped). If a double-click installer is wanted later, the
established Flutter approach is the `msix` package. On the Windows host:

1. Add to `dev_dependencies` in `pubspec.yaml`:

   ```yaml
   dev_dependencies:
     msix: ^3.16.7   # pin to the current stable at the time
   ```

2. Add an `msix_config` block to `pubspec.yaml`:

   ```yaml
   msix_config:
     display_name: Brisko Billing
     publisher_display_name: Brisko
     identity_name: com.brisko.billing
     msix_version: 1.0.0.0
     logo_path: assets\images\brisko_logo.png
     capabilities: ""      # a till needs no special OS capabilities
   ```

3. Build the release (step 3), then:

   ```
   dart run msix:create
   ```

   which produces `build\windows\x64\runner\Release\brisko_billing.msix`. Rename the
   deliverable to `Brisko-Billing-Setup.msix`.

Installing an unsigned MSIX on the client requires either a code-signing certificate or
enabling sideloading. For a single dedicated POS machine, the packaged release folder
(step 4) is simpler and is the recommended default; MSIX is worth it only if the client
wants Add/Remove Programs integration and auto-update.

## 6. Do not ship

- Debug or profile builds.
- The bare `.exe` without its DLLs and `data\` directory.
