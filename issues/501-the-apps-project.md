# 501 — The app's project: a Kotlin and Compose app, as rmail's

**Phase:** 5 — The Android app
**Blocked by:** — (the owner's Android toolchain)
**Blocks:** 502 to 509

**Needs the Android toolchain on the owner's machine.**  This machine
has a JDK and Gradle but no Android SDK, no Kotlin compiler of its own
and no emulator or phone, and nothing may be installed here; so this
issue is a plan, written 2026-11-06, and none of it is built.  No Kotlin
is written until it can be compiled (501 decision 3).

## Current Behavior

There is no Android app.  Planning section 11: "Android app: Kotlin with
Jetpack Compose, like rmail's app."  Section 8: it "follows the rmail
app's design so the two feel like one family."  rmail's app lives in
`clients/android/` (Gradle 8.2.2, Kotlin 1.9.22, Compose BOM 2024.02.00,
minSdk 26, targetSdk 34, JDK 17, namespace `com.rmail.app`) and is built
by `scripts/compile-android.sh` (`--test` builds, `--push` installs with
`adb`).

## Intended Behavior

- **`clients/android/`**, laid out as rmail's: `app/src/main/kotlin/
  <namespace>/` with `net/`, `crypto/`, `data/`, `sync/`, `ui/screens/`,
  `ui/theme/`; the same Gradle, Kotlin and Compose versions as rmail's at
  the time of building (decision 2), so one toolchain builds both.
- **Namespace and application id `com.raochat.app`** (decision 1).
- **`scripts/compile-android`** (Bash), as rmail's `compile-android.sh`:
  `--test` builds the debug APK, `--push [-s SERIAL]` installs it with
  `adb`, and with neither it does both; it names what is missing (the
  SDK, `adb`, a connected phone) and stops, and it installs nothing.
- **The look of section 8**, defined once in `ui/theme/`: black
  background, goldenrod text `#FFD040`, dim goldenrod `#B89020`, cyan
  accent `#00E5FF`, monospace for messages and addresses, dark only.  The
  values are the web page's palette (`src/web/204-palette.css`), and a
  referee holds the two equal.
- **The app's shell**: the title (the home's name, underlined; tapping it
  goes to Servers), the error strip with "(retrying in Nm)", and the
  bottom bar of text buttons Rooms · People · Settings, each its own
  colour, filled when selected, hidden while the keyboard is open; no
  back arrow at the top level.  The screens behind the tabs are empty
  until 503 to 508.

## Status

Plan only (2026-11-06); not built.

## Rubric

From `notes/rmail-rubric/structure-and-defences.md`: one place for each
value (the palette defined once and read everywhere), and nothing
deleted by a swipe (section 8, a lesson rmail learned).

## Where we differ

- **No reference code is copied from rmail's app**: rmail is a separate
  project with its own history; the app follows its layout and look, and
  its code is read for how, not pasted.  (Where a piece is the same, such
  as the frame layout, 502 ports rao-chat's own Lua, whose referees
  already hold it.)

## Referees

1. **It builds**: `scripts/compile-android --test` makes a debug APK on
   the owner's machine; without the SDK it says what is missing and
   exits 1 having written nothing.
2. **The palette is one**: a JVM unit test reads `204-palette.css` and
   the app's colour table and finds them equal.
3. **The shell**: on a phone or emulator, the three tabs switch screens,
   the bar hides with the keyboard, and there is no back arrow at the top
   level (a Compose UI test).

## Suggested Implementation Steps

1. The Gradle project and `scripts/compile-android`, then a build.
2. The theme and the shell.
3. The referees.

## Blockers that are not the owner's

- None besides the toolchain: the home side the app talks to (phase 3)
  is built.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **`com.raochat.app`**: rmail's pattern (`com.rmail.app`) with the
   project's name; a hyphen cannot be in a package name.
2. **rmail's versions, not newer ones**: one toolchain on the owner's
   machine builds both apps.  When rmail's move, rao-chat's follow.
3. **No Kotlin is committed before it compiles**: code that has never
   been built is a guess.  The issues of phase 5 say what to build and
   how to check it, and the code comes on the owner's machine.
4. **Gradle fetches the Android libraries, as rmail's build does.**  The
   project's rule is to vendor libraries and use no package manager, but
   an Android app is built with the Android Gradle plugin and the AndroidX
   libraries from Google's repository, as rmail's is; vendoring them
   would be thousands of files.  The owner's words for this app ("like
   rmail's app") are taken to decide it; vendoring the AARs into `libs/`
   is the way back if the owner prefers it.
5. **No `adb` or SDK is installed by the script**: it says what is
   missing, as 601 does for the home.

## Related documents

- `notes/vision-planning.md` sections 8 and 11
- `src/web/204-palette.css` (the palette), issue 401
