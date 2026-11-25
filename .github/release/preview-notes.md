Kronoer Preview {{VERSION}} lets you try Kronoer before it is on the Play Store. It is a trial version of the app: read [Before you install](#before-you-install) first.

## What's new

{{CHANGES}}

## Before you install

- **It is not the app from the Play Store.** Kronoer Preview is a separate app (`app.kronoer.preview`) that sits next to Kronoer from the Play Store, and it never updates into it.
- **Export is your only backup.** Nothing you write leaves your phone. If you uninstall the Preview, reset your phone, or lose it, what you wrote is gone unless you exported it. Export often, from Settings.
- **Moving to Kronoer from the Play Store.** When Kronoer is on the Play Store, export from the Preview and import the Archive into Kronoer. Kronoer imports an Archive from any Preview. Nothing else moves over: not the Preview's own storage, and not its settings.
- **The cryptography has not been reviewed by experts.** Read the [warning in the README](https://github.com/kronoer/kronoer#readme) before you trust it with anything whose exposure would harm you.

## Which APK

- `kronoer-preview-{{VERSION}}-arm64-v8a.apk` for almost every phone.
- `kronoer-preview-{{VERSION}}-armeabi-v7a.apk` only if Android says "App not installed" or "not compatible" for the first one.

## Installing

Download the APK on your phone and open it. Android asks you to allow installs from your browser or file manager.

Kronoer Preview does not come from a verified developer yet. Where Android requires one, as in Indonesia, it installs only in one of two ways:

- **Advanced flow:** turn on Developer options, then allow apps from unverified developers. Android makes you wait 24 hours the first time.
- **ADB:** from a computer, `adb install kronoer-preview-{{VERSION}}-arm64-v8a.apk`.

## Checking for a new version

Once a day, when you open it, Kronoer Preview asks GitHub whether a newer Preview is out, and shows a banner when there is one. The request carries only what every web request does: your IP address and the app's User-Agent, nothing you wrote. You can turn it off in Settings.

## Checking the download

SHA-256 of the APKs:

| File | SHA-256 |
| ---- | ------- |
| `kronoer-preview-{{VERSION}}-arm64-v8a.apk` | `{{ARM64_SHA256}}` |
| `kronoer-preview-{{VERSION}}-armeabi-v7a.apk` | `{{ARMV7_SHA256}}` |

Every Kronoer Preview is signed with the same key. The SHA-256 fingerprint of its certificate:

```text
{{CERT_SHA256}}
```

To check an APK, use `apksigner` from the Android SDK build tools:

```sh
apksigner verify --print-certs kronoer-preview-{{VERSION}}-arm64-v8a.apk
```

`Signer #1 certificate SHA-256 digest` must show the fingerprint above. If it does not, do not install the APK.
