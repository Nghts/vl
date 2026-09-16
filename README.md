# VolumeBoostAll

Fork of [VolumeBoostYT](https://github.com/candyzp/VolumeBoostYT) generalized
from a YouTube-only tweak to a system-wide one.

## What changed vs. upstream

| Area | Upstream | This version |
|---|---|---|
| `.plist` filter | `Filter = { Executables = ( "YouTube" ); }` | `Filter = { Class = "UIApplication"; }` — loads into every SpringBoard app + SpringBoard itself |
| YouTube settings UI | `YTSettingsGroupData`/`YTSettingsSectionItemManager`/etc. hooks inject a row into YouTube's own Settings screen | Removed entirely. Prefs are read from `NSUserDefaults` (suite `com.yourname.volumeboostall`) since there's no shared in-app settings screen across arbitrary apps |
| Fullscreen/Shorts detection | Checked for `YT`-prefixed class names (`YTReelWatch`, `YTShortsPlayer`, ...) | Generic: fullscreen = landscape window bounds |
| `%ctor` bundle-ID gate | Only initializes if `bundleIdentifier` is `com.google.ios.youtube` or `YTSettings*` classes exist | Removed — always initializes, since the `.plist` filter already restricts *which processes* load the dylib |
| AVFoundation hooks (`AVPlayer`, `AVAudioPlayer`, `AVAudioPlayerNode`, `AVSampleBufferAudioRenderer`) | Same | Unchanged — these are system frameworks, so they already apply to every app once the filter is widened |
| Custom player classes (e.g. lvsplayer) | Not handled | New: a runtime scanner (`VBScanAndHookCustomVolumeClasses`) walks all loaded Objective-C classes ~0.5s after each process launches, finds any class implementing `- (void)setVolume:(float)volume` (checked via type encoding, not just selector name) that isn't one of the four AVFoundation classes above, and swizzles it the same way |

## About the lvsplayer hook specifically

I don't have lvsplayer's actual binary, so I can't know its player class's
real name. Two options are in `Tweak.x`:

1. **Generic scanner (`VBScanAndHookCustomVolumeClasses`)** — works without
   knowing the class name, but depends on the method having exactly the
   signature `- (void)setVolume:(float)`. If lvsplayer instead exposes volume
   as an `@property (nonatomic) float volume;` with a synthesized setter,
   this will still catch it (synthesized setters have the same signature).
   If it uses a different name (`setAudioVolume:`, `setGain:`, a `double`
   instead of `float`, or routes through a C API / audio unit instead of an
   Objective-C setter), the scanner won't find it.

2. **Named `%hook` stub** (commented out near the AVFoundation hooks) — more
   reliable once you know the real class/selector. To find it:
   - Pull the lvsplayer `.ipa`/app bundle and run `class-dump` (or open the
     Mach-O in Hopper/Ghidra) on its main executable and any embedded
     frameworks.
   - Search the class-dump output for `setVolume`, `volume`, `setGain`, or
     similar, and note the class name and argument type.
   - Uncomment the stub, put in the real class name/selector, rebuild.

## Building

Same as upstream — requires [Theos](https://theos.dev/). From this
directory:

```
make package
```

Produces a `.deb` for rootless jailbreak installs, or set `THEOS_PACKAGE_SCHEME=rootless`
appropriately for your target if needed.

## Caveats

- `Class = "UIApplication"` loads this into **every foreground app**, not
  just media players — it costs a small amount of memory/CPU per app launch
  (mainly the one-time class scan). If you only care about a handful of
  apps, list them explicitly instead: `Filter = { Bundles = ( "com.google.ios.youtube", "com.your.lvsplayer.bundleid", ... ); };`
  — narrower filters are lighter and less likely to cause conflicts with
  other tweaks.
- The runtime scanner swizzles *any* class it finds matching the signature —
  if some unrelated class happens to expose `setVolume:(float)` for a
  non-audio purpose, it'll get caught up too. Prefer the named `%hook` once
  you've identified the real class.
- No in-app UI ships with this version. Wire up a Settings.bundle preference
  pane, or a floating settings panel of your own, if you want to change the
  multiplier without shell access.
