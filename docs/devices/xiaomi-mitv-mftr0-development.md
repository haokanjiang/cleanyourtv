# MiTV-MFTR0 development profile

This fork has an explicit device profile for the China-market Xiaomi **MiTV-MFTR0 / freeguy**.
The first phase deliberately does **not** debloat the TV and does **not** disable
`com.mitv.tvhome`.

The profile lives at:

```text
launcher/app/src/main/assets/device-profiles/xiaomi-mftr0.json
```

It currently owns the firmware-specific pieces already verified on the real device:

- Xiaomi Settings and Wi-Fi Settings activities.
- HDMI 1/2/3 via Xiaomi's `EXTSRC_PLAY` activity and integer input IDs 23/24/25.
- AV via the same activity with input ID 2.
- ATV and DTMB via their dedicated Xiaomi activities.
- App enumeration from both `LEANBACK_LAUNCHER` and ordinary `LAUNCHER`, preferring the TV entry
  when a package exposes both.
- The duplicate AOSP Settings tile is hidden in favour of Xiaomi Settings.

The generic launcher behaviour remains the fallback for every TV that does not match a profile.

## Safe first-run validation

Use the validation script instead of `build-and-install` while developing the MFTR0 adaptation.
It builds and installs the APK, opens it once, and restores the previous Home component if Android
forgets the default merely because another HOME-capable package was installed. It never disables a
package.

Windows:

```powershell
python -m venv tools\venv
tools\venv\Scripts\python.exe -m pip install -r tools\requirements.txt
powershell -ExecutionPolicy Bypass -File launcher\build-and-test.ps1 -TvHost <TV_IP>
```

macOS / Linux:

```bash
python3 -m venv tools/venv
tools/venv/bin/pip install -r tools/requirements.txt
TV_HOST=<TV_IP> launcher/build-and-test.sh
```

Expected result for this phase:

1. CleanYourTV opens and the physical Home button still returns to the original Xiaomi launcher.
2. Xiaomi Settings and Wi-Fi Settings open their native firmware pages.
3. Inputs shows exactly HDMI 1, HDMI 2 · eARC, HDMI 3, AV, TV / ATV and DTMB; no phantom HW8 entry.
4. Each input route opens the verified Xiaomi destination.
5. Ordinary China-market launcher apps appear alongside TV apps without duplicate package tiles.
6. D-pad navigation and launching normal apps still behave like upstream CleanYourTV.

Only after those checks pass on the real TV should the fork move on to Home takeover or debloat work.
