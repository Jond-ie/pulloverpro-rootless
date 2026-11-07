# PullOver Pro (Rootless)

Pin any app to a small handle on the side of the screen and pull it over whatever you're doing, live.

- Pull the handle to slide the pinned app in, push it back to tuck it away.
- Long-press the handle for QuickSwitch: recent apps or favorites. Drag one to the middle to open it full screen.
- Settings apply right away, no respring.

Get it from the [Jond_ie repo](https://jond-ie.github.io/repo/). Rootless and RootHide jailbreaks, iOS 15 to 27.

## Building

Theos, Rootless scheme:

```
make package THEOS_PACKAGE_SCHEME=rootless
```

The favorites picker uses [AltList](https://github.com/opa334/AltList) at runtime (package dependency).

<details>
<summary>Credits and licence</summary>

PullOver Pro by c1d3r ([@c1d3rdev](https://x.com/c1d3rdev), [source](https://github.com/c1d3rdev/PullOver-Pro)), released under the GPL-3.0. iOS 13 support by [@akusio_RR](https://x.com/akusio_RR). iOS 15 to 27 Rootless and RootHide support by Jond-ie ([@Jond_ie](https://x.com/Jond_ie)): scene hosting rewritten for iOS 15+, settings rebuilt on AltList, the paid unlock removed.

This port is released under the same GPL-3.0 licence (see LICENSE).
</details>
