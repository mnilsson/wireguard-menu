# WireGuard Menu

A small native macOS menu bar app for independent `wg-quick` tunnels, with a privileged helper for password-free tunnel control. No package dependencies.

## Run

Requires macOS 13+, Swift 6+, Homebrew's `wireguard-tools` and `wireguard-go`, and an Apple code-signing identity in your keychain. The build uses the first available identity; set `SIGNING_IDENTITY` to select a different one. The app and helper must be signed by the same team.

```sh
bash build.sh
ditto "dist/WireGuard Menu.app" "/Applications/WireGuard Menu.app"
open "/Applications/WireGuard Menu.app"
```

Click the network icon and choose **Enable password-free control…**. Approve WireGuard Menu under **System Settings → General → Login Items** (called **Login Items & Extensions** on some versions). macOS requires administrator approval for this initial setup. Subsequent Connect, Disconnect, and status checks use the helper without asking for your password. **Helper settings…** opens the same settings if approval is later revoked. Keep the app in `/Applications` so its bundled helper remains accessible after a restart. Distribution to other Macs additionally requires Developer ID signing and notarization.

Choose **Add tunnel…**, and select your office and production `.conf` files. Export configurations from the WireGuard app first if needed; disconnect those profiles in that app and disable their on-demand activation before managing them here.

Each configuration needs a unique filename with 1–15 letters, digits, or `_ = + . -` characters before `.conf`. Adding a configuration copies it into `~/Library/Application Support/WireGuard Menu/Configurations/`. You can then delete the original, including from Downloads. Connect and Show in Finder use the imported copy; edits to the original do not affect it. Entries added with older versions still use their original paths: remove and re-add them to import a copy. Only select configurations you trust: `wg-quick` supports shell hooks that execute with administrator privileges.

The submenu for each tunnel provides separate Connect and Disconnect actions, plus Show in Finder. Disconnect remains available when status cannot be read. Quitting leaves tunnels running. Removing a stopped tunnel from the menu does not delete its configuration. The helper accepts requests only from this app signed by the same team, and only operates on `.conf` paths inside the requesting user's home directory. Re-add older configurations stored elsewhere to import them.

## Status and routing

The icon counts confirmed running tunnels. Status refreshes every three seconds and when opening the menu. The helper reads WireGuard's root-only status files. **Running** means the `wg-quick` mapping, matching control socket, and macOS network interface exist. It does not claim a recent handshake or remote service reachability. A missing or unavailable helper, or unreadable state, is shown as **Status unavailable**. This does not mean the tunnel is stopped; both connection actions remain available when no command is in progress.

This wraps the command-line tools, not profiles managed by the official WireGuard app. The app doesn't modify routes, keys, or DNS settings in configurations. For simultaneous office and AWS access, configure each tunnel's `AllowedIPs` for its destination networks. Overlapping networks/default routes and competing DNS settings need to be resolved in the configurations.

## Verify

```sh
swift test
```

To exercise connections, approve the helper, add real configurations, and use each tunnel's menu. Verify access to an office service and an AWS service with both tunnels running, then disconnect individually. These actions change networking. Tests cover configuration imports, status detection, command arguments, helper request validation, and rejection of XPC clients with the wrong signature without starting a tunnel.
