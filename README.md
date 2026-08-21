# connectivity_kit

Lightweight internet connection monitoring for Flutter apps, built on top of
[`connectivity_plus`](https://pub.dev/packages/connectivity_plus) with a ready
GetX controller. Share one implementation across all your apps instead of
copy-pasting connectivity files into every project.

## Features

- **Single `ConnectivityStatus` stream** — `wifi` (Wi-Fi / Ethernet / VPN),
  `cellular` (mobile data), or `offline`; only actual changes are emitted.
- **Disconnect debouncing** — transient network flaps are ignored for a
  configurable duration (default 3s).
- **Optional reachability probing** — `connectivity_plus` only reports the
  network *interface*; a device behind a captive portal still shows as
  "connected". When enabled, the service verifies real internet access with a
  direct TCP probe before reporting an online state.
- **GetX integration** — an `InternetConnectionController` exposes reactive
  `connectionStatus`, `isOnline`, and `isCellular` for `Obx` widgets.
- **UI-agnostic core** — the service is framework-free apart from Flutter
  logging; show your own snackbars/banners in the consuming app.

## Installation

Add the git dependency to your app's `pubspec.yaml`:

```yaml
dependencies:
  connectivity_kit:
    git:
      url: https://github.com/alheekmahlib/connectivity_kit.git
      ref: v0.1.0
```

To upgrade, bump the `ref` to a newer tag (or use `flutter pub upgrade --force-git`).

## Usage

Initialize once (e.g. in `main`) before first use:

```dart
final service = InternetConnectionService(
  options: const InternetConnectionOptions(enableReachability: true),
);
await service.init();

Get.put(service, permanent: true);
Get.put(InternetConnectionController(), permanent: true);
```

React to the status in your UI:

```dart
Obx(() {
  final controller = InternetConnectionController.instance;
  return controller.isOnline
      ? const MainView()
      : const NoInternetView();
});

// Or match on the exact status:
switch (controller.connectionStatus.value) {
  case ConnectivityStatus.wifi: // Wi-Fi / Ethernet / VPN
  case ConnectivityStatus.cellular: // mobile data
  case ConnectivityStatus.offline:
}
```

Without GetX, listen to the service stream directly:

```dart
final service = Get.find<InternetConnectionService>(); // or hold your own instance
service.connectionStream.listen((status) {
  debugPrint('Connection changed: $status');
});
```

### Options

All options have sensible defaults and live in `InternetConnectionOptions`:

| Option | Default | Description |
| --- | --- | --- |
| `disconnectDebounce` | `3s` | How long a disconnect must persist before `offline` is emitted. |
| `enableReachability` | `false` | Verify real internet access (TCP probe) before reporting online. |
| `reachabilityTimeout` | `5s` | Timeout for the reachability probe. |
| `probeHost` / `probePort` | `1.1.1.1` / `53` | Probe target (direct TCP, no HTTP overhead). |

Notes:

- With `enableReachability: true` on the **web**, the probe is a no-op and the
  interface status is trusted (direct sockets are unavailable in browsers).
- Showing user-facing messages (snackbars, banners) is intentionally left to
  the consuming app — subscribe to `connectionStream` or observe
  `connectionStatus`.

## Testing your app

Both the connectivity source and the reachability probe are injectable, so you
can drive fake states in widget/unit tests without platform channels:

```dart
final service = InternetConnectionService(
  connectivitySource: FakeConnectivitySource(), // implements ConnectivitySource
  reachabilityProbe: FakeReachabilityProbe(),   // implements ReachabilityProbe
);
```

See `test/` for ready-made fakes.

## Platforms

Android, iOS, macOS, Windows, Linux, and web (reachability probe is a no-op on
web).

## License

MIT — see [LICENSE](LICENSE).
