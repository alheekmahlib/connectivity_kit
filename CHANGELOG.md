## 0.1.0

Initial release.

- `ConnectivityStatus` (`wifi` / `cellular` / `offline`) with
  `isOnline` / `isCellular` helpers.
- `InternetConnectionService`: broadcast status stream, emits only on change,
  configurable disconnect debouncing, safe `dispose` before `init`,
  initial-state/stream race fix.
- Optional real reachability probing (`enableReachability`) via direct TCP
  probe with injectable `ReachabilityProbe`; no-op on web.
- `InternetConnectionController`: GetX controller with reactive
  `connectionStatus`, injectable service, clear error when the service is not
  registered.
- Injectable `ConnectivitySource` for testing without platform channels.
