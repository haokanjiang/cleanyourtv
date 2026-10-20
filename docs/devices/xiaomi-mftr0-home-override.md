# MFTR0 accessibility Home override experiment

The MFTR0 firmware can return `Success` from `cmd package set-home-activity` while still routing the
physical Home button through Xiaomi firmware. If `com.mitv.tvhome` is disabled, the firmware falls
back to `com.xiaomi.mitv.settings/.entry.FallbackHome` instead of choosing a third-party launcher.

This branch therefore contains an opt-in experiment that leaves both Xiaomi system packages enabled.

The existing `HomeKeyService` now also observes `TYPE_WINDOW_STATE_CHANGED` on MFTR0. The device
profile redirects only these targets:

```text
com.mitv.tvhome
com.xiaomi.mitv.settings/.entry.FallbackHome
```

Other Xiaomi Settings screens are deliberately ignored.

When one of those Home targets appears, the service starts CleanYourTV explicitly with
`ACTION_MAIN + CATEGORY_HOME`. A debounce prevents event loops while firmware windows transition.

## Test

First install the current branch safely:

```powershell
powershell -ExecutionPolicy Bypass -File launcher\build-and-test.ps1 -TvHost <TV_IP>
```

Then enable the experiment:

```powershell
powershell -ExecutionPolicy Bypass -File launcher\test-home-override.ps1 -TvHost <TV_IP>
```

Open another application and press the physical Home button three times.

Expected result:

```text
physical Home
-> Xiaomi Home/FallbackHome is entered by firmware
-> accessibility window event
-> CleanYourTV is explicitly launched as a HOME task
```

A short flash of Xiaomi/FallbackHome is acceptable for this experiment. The Android default Home
remains unchanged and no Xiaomi package is disabled.

Rollback:

```powershell
powershell -ExecutionPolicy Bypass -File launcher\test-home-override.ps1 -TvHost <TV_IP> -Disable
```

If it does not work, inspect `dumpsys accessibility` first. Being present in
`enabled_accessibility_services` does not prove that the service is actually bound on vendor firmware.
