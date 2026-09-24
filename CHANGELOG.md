## 0.2.1

Fix: a failed disk-store creation no longer aborts `TaskQueueService.init()`.
On devices where the `shared_preferences` platform channel is unavailable
(e.g. some old Huawei devices during Impeller's Vulkan→OpenGLES fallback),
`getInstance()` throws inside `init()`, which — awaited in the host app's
`main()` — left the app hung on the splash screen forever.

- `init()` now falls back to a new in-memory `MemoryQueueStore` when creating
  `SharedPreferencesQueueStore` fails: the queue keeps working for the
  session; pending tasks simply don't survive restarts in that degraded case.
- `MemoryQueueStore` is public and injectable for session-only queues.
- `TaskQueueService.defaultStoreFactory` (`@visibleForTesting`) replaces the
  built-in store creation in tests.

## 0.2.0

Offline task queue: enqueue anything that needs the internet (sending notes,
syncing, …) and it executes automatically in the background once connectivity
returns — across app restarts, with no user intervention.

- `TaskQueueService`: persisted serial (strict FIFO) task queue driven by
  `ConnectionService`. Loads saved tasks on `init()` and drains them when
  online; enqueue while offline just waits.
- Tasks are serializable data (`QueuedTask`: type + JSON payload), executed by
  app-registered handlers (`registerHandler`) — survives app restarts.
- Bounded retries with exponential backoff (`5s → 10s → 20s`, capped at 60s),
  default 3 attempts, then the task is marked `failed` (persisted) and a
  `QueueTaskFailedPermanently` event is emitted. A per-task timeout
  (default 30s) keeps one hung task from blocking the queue.
- Optional `groupId` coalescing: a new task replaces an older pending task
  with the same key (latest-wins).
- Injectable `QueueStore` with a default `SharedPreferencesQueueStore`
  (versioned JSON under a single key). Swap in an encrypted store for
  sensitive payloads. New dependency: `shared_preferences`.
- `TaskQueueController`: GetX controller exposing reactive
  `pendingCount` / `failedCount` / `isDraining`, plus `retryTask` /
  `clearFailed` passthroughs.
- Queue events on a broadcast stream (`QueueTaskEnqueued`, `QueueTaskSucceeded`,
  `QueueTaskRetrying`, `QueueTaskFailedPermanently`, `QueueDrained`).
- Manual controls: `removeTask`, `retryTask`, `clearFailed`.
- Docs: README updated to the current `Connection*` class names and covers the
  queue; example app demonstrates sending notes offline.

## 0.1.1

Breaking rename to clarify the public API (old names removed).

- `InternetConnectionService` → `ConnectionService`,
  `InternetConnectionOptions` → `ConnectionOptions`,
  `InternetConnectionController` → `ConnectionController`.
- `ConnectivityStatus` values renamed to `wifi` / `cellular` / `offline`
  (previously `connected` / `phoneData` / `disconnected`).

## 0.1.0

Initial release.

- `ConnectivityStatus` (`wifi` / `cellular` / `offline`) with
  `isOnline` / `isCellular` helpers.
- `ConnectionService`: broadcast status stream, emits only on change,
  configurable disconnect debouncing, safe `dispose` before `init`,
  initial-state/stream race fix.
- Optional real reachability probing (`enableReachability`) via direct TCP
  probe with injectable `ReachabilityProbe`; no-op on web.
- `ConnectionController`: GetX controller with reactive
  `connectionStatus`, injectable service, clear error when the service is not
  registered.
- Injectable `ConnectivitySource` for testing without platform channels.
