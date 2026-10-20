package com.gathin.tvhome;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Device-specific integration points that cannot be expressed through the generic Android TV APIs.
 *
 * Profiles live in assets/device-profiles. A profile is selected only when every non-empty matcher
 * (manufacturer/model/device) matches the current Build value. Generic TVs therefore keep the
 * upstream behaviour, while China-market firmware can opt into explicit Settings and input routes.
 */
final class DeviceProfile {
    private static final String TAG = "TvHome.DeviceProfile";
    private static final String DIR = "device-profiles";

    static final DeviceProfile NONE = new DeviceProfile(
            "default", "", false, null, null, Collections.emptyList());

    final String id;
    final String stockLauncherPackage;
    final boolean includeRegularLauncherApps;
    final Target settings;
    final Target wifiSettings;
    final List<Input> inputs;

    private DeviceProfile(String id, String stockLauncherPackage, boolean includeRegularLauncherApps,
                          Target settings, Target wifiSettings, List<Input> inputs) {
        this.id = id;
        this.stockLauncherPackage = stockLauncherPackage;
        this.includeRegularLauncherApps = includeRegularLauncherApps;
        this.settings = settings;
        this.wifiSettings = wifiSettings;
        this.inputs = Collections.unmodifiableList(inputs);
    }

    boolean hasInputs() {
        return !inputs.isEmpty();
    }

    /** Returns the profile's preferred Settings destination, or null when the generic route should be used. */
    Intent settingsIntent(String standardAction) {
        Target target = android.provider.Settings.ACTION_WIFI_SETTINGS.equals(standardAction)
                ? wifiSettings : android.provider.Settings.ACTION_SETTINGS.equals(standardAction) ? settings : null;
        return target == null ? null : target.intent();
    }

    static DeviceProfile load(Context ctx) {
        try {
            String[] files = ctx.getAssets().list(DIR);
            if (files == null) return NONE;
            for (String file : files) {
                if (!file.endsWith(".json")) continue;
                DeviceProfile profile = parse(read(ctx, DIR + "/" + file));
                if (profile != null && profile.matches(Build.MANUFACTURER, Build.MODEL, Build.DEVICE)) {
                    Log.i(TAG, "loaded " + profile.id + " for " + Build.MANUFACTURER + " "
                            + Build.MODEL + " (" + Build.DEVICE + ")");
                    return profile;
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "could not load device profiles", e);
        }
        return NONE;
    }

    boolean matches(String manufacturer, String model, String device) {
        // The parsed match values are kept in synthetic Targets? No: encode them in the id metadata fields below.
        Match m = match;
        return m == null || (matchesValue(m.manufacturer, manufacturer)
                && matchesValue(m.model, model) && matchesValue(m.device, device));
    }

    private static boolean matchesValue(String expected, String actual) {
        return expected == null || expected.isEmpty()
                || (actual != null && expected.equalsIgnoreCase(actual.trim()));
    }

    private Match match;

    private static DeviceProfile parse(String text) {
        try {
            JSONObject root = new JSONObject(text);
            if (root.optInt("schema_version", -1) != 1) return null;
            JSONObject matchJson = root.optJSONObject("match");
            Match match = new Match(
                    string(matchJson, "manufacturer"),
                    string(matchJson, "model"),
                    string(matchJson, "device"));

            JSONObject settingsJson = root.optJSONObject("settings");
            Target mainSettings = target(settingsJson == null ? null : settingsJson.optJSONObject("main"));
            Target wifiSettings = target(settingsJson == null ? null : settingsJson.optJSONObject("wifi"));

            List<Input> inputs = new ArrayList<>();
            JSONArray array = root.optJSONArray("inputs");
            if (array != null) {
                for (int i = 0; i < array.length(); i++) {
                    JSONObject item = array.optJSONObject(i);
                    if (item == null) continue;
                    String label = string(item, "label");
                    Target destination = target(item);
                    if (label.isEmpty() || destination == null) continue;
                    inputs.add(new Input(
                            string(item, "id"),
                            label,
                            string(item, "kind"),
                            string(item, "tv_input_id"),
                            destination));
                }
            }

            DeviceProfile profile = new DeviceProfile(
                    string(root, "id"),
                    string(root, "stock_launcher_package"),
                    root.optBoolean("include_regular_launcher_apps", false),
                    mainSettings,
                    wifiSettings,
                    inputs);
            profile.match = match;
            return profile;
        } catch (Exception e) {
            Log.w(TAG, "ignoring invalid profile: " + e.getMessage());
            return null;
        }
    }

    private static Target target(JSONObject json) {
        if (json == null) return null;
        String action = string(json, "action");
        String component = string(json, "component");
        String extraKey = string(json, "int_extra_key");
        Integer extraValue = json.has("int_extra_value") ? json.optInt("int_extra_value") : null;
        if (action.isEmpty() && component.isEmpty()) return null;
        return new Target(action, component, extraKey, extraValue);
    }

    private static String string(JSONObject json, String key) {
        if (json == null) return "";
        String value = json.optString(key, "");
        return value == null ? "" : value.trim();
    }

    private static String read(Context ctx, String path) throws Exception {
        try (InputStream in = ctx.getAssets().open(path);
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int n;
            while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
            return out.toString(StandardCharsets.UTF_8.name());
        }
    }

    static final class Input {
        final String id;
        final String label;
        final String kind;
        /** TvInputManager id used only for connection-state display; the launch route is the explicit Target. */
        final String tvInputId;
        final Target target;

        Input(String id, String label, String kind, String tvInputId, Target target) {
            this.id = id;
            this.label = label;
            this.kind = kind;
            this.tvInputId = tvInputId;
            this.target = target;
        }

        Intent intent() {
            return target.intent();
        }

        boolean isHdmi() {
            return "hdmi".equals(kind);
        }

        boolean isAv() {
            return "av".equals(kind);
        }
    }

    static final class Target {
        final String action;
        final String component;
        final String intExtraKey;
        final Integer intExtraValue;

        Target(String action, String component, String intExtraKey, Integer intExtraValue) {
            this.action = action;
            this.component = component;
            this.intExtraKey = intExtraKey;
            this.intExtraValue = intExtraValue;
        }

        Intent intent() {
            Intent i = action.isEmpty() ? new Intent() : new Intent(action);
            ComponentName c = ComponentName.unflattenFromString(component);
            if (c != null) i.setComponent(c);
            if (!intExtraKey.isEmpty() && intExtraValue != null) i.putExtra(intExtraKey, intExtraValue);
            return i;
        }
    }

    private static final class Match {
        final String manufacturer;
        final String model;
        final String device;

        Match(String manufacturer, String model, String device) {
            this.manufacturer = manufacturer;
            this.model = model;
            this.device = device;
        }
    }
}
