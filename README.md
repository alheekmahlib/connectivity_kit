# connectivity_kit

Lightweight internet connection monitoring and offline task queuing for Flutter
apps, built on top of
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
- **Offline task queue** — enqueue anything that needs the internet (sending a
  note, syncing, …). Tasks persist across app restarts and execute
  automatically in strict FIFO order once connectivity returns — retries,
  backoff, and failure states included, with no user intervention.
- **GetX integration** — `ConnectionController` exposes reactive
  `connectionStatus`, `isOnline`, and `isCellular`; `TaskQueueController`
  exposes reactive queue stats (`pendingCount`, `failedCount`, `isDraining`).
- **UI-agnostic core** — the services are framework-free apart from Flutter
  logging; show your own snackbars/banners in the consuming app.

## Installation

Add the git dependency to your app's `pubspec.yaml`:

```yaml
dependencies:
  connectivity_kit:
    git:
      url: https://github.com/alheekmahlib/connectivity_kit.git
      ref: v0.2.0
```

To upgrade, bump the `ref` to a newer tag (or use `flutter pub upgrade --force-git`).

## Usage: connection monitoring

Initialize once (e.g. in `main`) before first use:

```dart
final service = ConnectionService(
  options: const ConnectionOptions(enableReachability: true),
);
await service.init();

Get.put(service, permanent: true);
Get.put(ConnectionController(), permanent: true);
```

React to the status in your UI:

```dart
Obx(() {
  final controller = ConnectionController.instance;
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
final service = Get.find<ConnectionService>(); // or hold your own instance
service.connectionStream.listen((status) {
  debugPrint('Connection changed: $status');
});
```

### Connection options

All options have sensible defaults and live in `ConnectionOptions`:

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

## Usage: offline task queue

The queue turns "send this when the internet is back" into a one-liner. Tasks
are serializable data (a `type` + JSON `payload`) executed by handlers you
register, so they survive app restarts.

Set it up after the connection service, **registering handlers before
`init()`**:

```dart
final queue = TaskQueueService(connectionService: service);
queue.registerHandler('send_note', (payload) async {
  await api.post('/notes', body: payload); // your network call
});
await queue.init();
Get.put(queue, permanent: true);
Get.put(TaskQueueController(), permanent: true);
```

Enqueue work from anywhere — online it executes immediately (in FIFO order),
offline it waits:

```dart
await queue.enqueue(
  type: 'send_note',
  payload: {'title': '…', 'body': '…'},
  groupId: 'note_42', // optional: replaces an older pending task with the
                      // same key (latest-wins)
);
```

Observe progress in the UI:

```dart
Obx(() {
  final controller = TaskQueueController.instance;
  return Badge(
    label: Text('${controller.pendingCount.value}'),
    child: const Icon(Icons.schedule),
  );
});
```

Or react to lifecycle events (for snackbars, local DB updates, etc.):

```dart
queue.events.listen((event) {
  switch (event) {
    case QueueTaskSucceeded():
      debugPrint('sent: ${event.task.id}');
    case QueueTaskRetrying(attempt: var n, error: var e):
      debugPrint('attempt $n failed: $e');
    case QueueTaskFailedPermanently(error: var e):
      debugPrint('gave up: $e');
    case QueueTaskEnqueued() || QueueDrained():
      break;
  }
});
```

Failed tasks stay stored with their `lastError`; retry them individually
(`queue.retryTask(id)` / `controller.retryTask(id)`) or drop them
(`clearFailed()`).

### Queue options

Defaults live in `TaskQueueOptions`:

| Option | Default | Description |
| --- | --- | --- |
| `maxAttempts` | `3` | Attempts before a task is marked `failed` permanently. |
| `initialRetryDelay` | `5s` | Delay before the first retry; doubles each attempt. |
| `retryDelayFactor` | `2` | Backoff multiplier between retries. |
| `maxRetryDelay` | `60s` | Backoff cap. |
| `taskTimeout` | `30s` | Per-execution timeout (counts as a failed attempt) — keeps a hung task from blocking the serial queue. |

Behavior notes:

- Execution is **strictly serial FIFO**; a task that failed with attempts left
  keeps its position but is skipped until its retry time, so it never blocks
  the tasks behind it.
- An unregistered task type is treated as a retryable failure — registering
  handlers slightly after `init()` is safe within the attempt budget.
- On **web**, persistence uses `shared_preferences` (localStorage); very large
  queues could hit storage limits.

### Storage & privacy

The default `SharedPreferencesQueueStore` persists the queue as versioned JSON
under a single key. It is **not encrypted** on most platforms — for sensitive
payloads, implement `QueueStore` yourself (wrapping e.g.
`flutter_secure_storage` or an encrypted database) and inject it:

```dart
final queue = TaskQueueService(
  connectionService: service,
  store: MySecureQueueStore(),
);
```

## Testing your app

The connectivity source, the reachability probe, and the queue store are all
injectable, so you can drive fake states in widget/unit tests without platform
channels:

```dart
final service = ConnectionService(
  connectivitySource: FakeConnectivitySource(), // implements ConnectivitySource
  reachabilityProbe: FakeReachabilityProbe(),   // implements ReachabilityProbe
);

final queue = TaskQueueService(
  connectionService: service,
  store: FakeQueueStore(),                      // implements QueueStore
);
```

See `test/helpers/fakes.dart` for ready-made fakes.

## Platforms

Android, iOS, macOS, Windows, Linux, and web (reachability probe is a no-op on
web; queue persistence uses localStorage).

## License

MIT — see [LICENSE](LICENSE).
