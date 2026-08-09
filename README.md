# Building an AppImage that actually runs on Tails

Field notes from shipping one. Every claim here was verified rather than recalled, and the
evidence is named so you can re-check it in minutes instead of booting a USB stick.

Written for the next person, or the next agent, who has a .NET or web application and wants a
single file a user can double-click on an offline Tails session.

## The one habit that matters

**What Tails provides is a published fact, not an experiment.** Tails ships a package manifest
for every release. Read it instead of guessing, and instead of asking someone to boot a stick
and report back.

```bash
# current release
curl -s https://tails.net/install/download/ | grep -oE "tails-amd64-[0-9.]+" | sort -u

# its manifest: about 1900 lines of name<TAB>version
curl -s -o tails.packages https://tails.net/torrents/files/tails-amd64-7.10.1.packages

grep -iE "webkit|fuse|gtk-3" tails.packages
```

Everything below came out of that file.

## What Tails 7.10.1 has (Debian 13 "trixie" base, checked 2026-08-09)

| you may be wondering about | present? | version |
| --- | --- | --- |
| `libwebkit2gtk-4.1-0` | yes | 2.52.5-1~deb13u1 |
| `libjavascriptcoregtk-4.1-0` | yes | 2.52.5-1~deb13u1 |
| `libgtk-3-0t64` | yes | 3.24.49-3 |
| `libglib2.0-0t64` | yes | 2.84.4-3~deb13u3 |
| `libsoup-3.0-0` | yes | 3.6.5-3 |
| `librsvg2-2` | yes | 2.60.0+dfsg-1 |
| `libnotify4` | yes | 0.8.6-1 |
| **`libfuse2t64`** | **yes** | 2.9.9-9 |
| `python3` | yes | 3.13.5 |
| `libayatana-appindicator3-1` | **no** | needed only for a system tray |

Three of those deserve comment.

**WebKitGTK is 4.1 only.** Debian 13 dropped the 4.0 series. Anything linking
`libwebkit2gtk-4.0.so.37` will not start on Tails 7, and the failure will look like an
application bug rather than a packaging one. Check with `readelf -d yourbinary | grep NEEDED`
before blaming your code.

**FUSE 2 is present**, which is not true of every modern distribution. AppImages self-mount
through it, and its absence elsewhere is the usual reason an AppImage silently does nothing.
On Tails you do not need `--appimage-extract-and-run`.

**No appindicator.** If your shell wants a system tray, it will not have one. Turn the feature
off rather than bundling the library.

## Do not bundle WebKitGTK

This is the single biggest lever on size, and the default is wrong for Tails.

Measured, same application, same binary, two packagings:

| packaging | size |
| --- | --- |
| Tauri's own bundler, which copies the WebKitGTK and GTK stack in | **83 MB** |
| a hand-built AppDir that bundles nothing | **11.4 MB** |

Bundling exists so an AppImage runs on distributions that lack the engine. Tails is not one of
them. You are shipping 70 MB to solve a problem you already know you do not have, and pinning a
browser engine while you do it.

## The packaging recipe

No packaging library, and none is needed. `dotnet publish` (or your build), four files, and one
external tool.

```
AppDir/
  AppRun                      # the entry point, executable
  yourapp.desktop             # Type, Name, Exec, Icon, Categories, Terminal=false
  yourapp.png                 # RGBA. Tauri rejects non-RGBA outright
  usr/bin/yourapp             # your executable, executable
```

```bash
wget -q "https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage"
echo "ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0  appimagetool-x86_64.AppImage" | sha256sum -c -
chmod +x appimagetool-x86_64.AppImage
ARCH=x86_64 ./appimagetool-x86_64.AppImage --appimage-extract-and-run AppDir yourapp-x86_64.AppImage
sha256sum yourapp-x86_64.AppImage | tee yourapp-x86_64.AppImage.sha256
```

Four details that are easy to get wrong:

- **Pin the tool and verify it.** Not `continuous`. This binary helps produce the artifact your
  users run; fetching an unversioned copy and executing it undermines whatever you were
  planning to say about supply chains.
- **Use `AppImage/appimagetool`, not `AppImage/AppImageKit`.** The latter publishes its
  release-13 assets with an `obsolete-` prefix. The maintained tool moved to its own repository
  and real semantic versions.
- **`--appimage-extract-and-run`** on CI runners, which have no FUSE. Not needed on Tails.
- **Publish the checksum** beside the binary. An AppImage is an opaque blob; the checksum is
  the only thing a user can check it against.

See [`templates/`](templates/) for a working `AppRun`, `.desktop` and GitHub Actions job.

## Choosing the window: what actually works

For a web-based UI you need something to host a WebView. Measured against Tails specifically:

| | maintained | Tails | size | notes |
| --- | --- | --- | --- | --- |
| **Tauri v2** | very (110k stars, active) | works | **11.4 MB** slim | Rust shell, ~30 lines; serves the frontend in process, no port |
| Photino.Blazor | **no**: last release Jan 2025, "\.NET 8/9 only" | works | 32 MB | .NET-native, hosts Blazor Hybrid |
| Wails v3 | very | should | small | same idea in Go, not tested here |
| Neutralino | active | — | tiny | runs an internal HTTP server, so it binds a port |
| Electron | very | works | ~150 MB | bundles Chromium; the only one that needs nothing from the host |
| MAUI Blazor Hybrid, WPF BlazorWebView | very | **no Linux** | — | rules them out entirely |

**Tauri is the recommendation.** It uses webkit2gtk-4.1, which Tails has; it serves the
frontend through an in-process protocol so nothing binds a port; and the artifact it ships is
your ordinary published static output rather than a second execution path.

Note that swapping shells does **not** remove the WebKitGTK requirement. Tauri, Wails and
Neutralino all use the host engine. Only bundling Chromium avoids it, at ~150 MB.

### If the frontend is Blazor WebAssembly

Two settings decide whether you get an application or a black rectangle:

- **CSP must allow WASM.** `script-src 'self' 'wasm-unsafe-eval'`. Without it the .NET runtime
  cannot start and the window stays empty.
- **`.wasm` must be served with `application/wasm`.** Tauri's asset protocol handles this.

Blazor WebAssembly **cannot** load over `file://`. If you were hoping to skip all of this by
double-clicking an HTML file, you would need a frontend that is plain HTML and JavaScript.

## When it "does nothing" on Tails

In every case encountered, the cause was not a missing library. In order of likelihood:

1. **GNOME Files does not launch binaries on double-click.** Modern GNOME removed that, and
   does it silently. Run it from a terminal to see anything at all.
2. **The executable bit is gone**, because the file crossed a FAT or exFAT stick or came from
   Windows. `chmod +x`.
3. **The USB may be mounted `noexec`.** Copy to `~` first, which fixes 2 and 3 together.
4. **Your own pre-flight check is broken.** See below.

```bash
cp /media/amnesia/*/yourapp-x86_64.AppImage ~/
cd ~ && chmod +x yourapp-x86_64.AppImage
./yourapp-x86_64.AppImage
```

### The pre-flight check that cost the most time

An `AppRun` contained this, meaning well:

```sh
if ! ldconfig -p 2>/dev/null | grep -q "libwebkit2gtk"; then
    echo "libwebkit2gtk was not found" >&2
    exit 1
fi
```

On Tails it printed that message and refused to start, on a system where the library was
installed. `ldconfig` lives in `/usr/sbin` and is **not on a normal user's PATH** on Debian, so
the command did not exist, its error went to the `/dev/null` the check itself supplied, `grep`
matched nothing, and the script called `exit 1`.

**A pre-flight check that can produce a false negative is worse than no check.** Warn and get
out of the way. The dynamic linker names a missing library far more precisely than a shell
script can.

## Proving it works, rather than hoping

A window appearing is not the test. For anything that computes something, the test is that it
computes the right thing:

1. Build in CI and publish the checksum.
2. Download, `sha256sum -c`, copy to the stick.
3. Boot Tails with networking off, copy to `~`, `chmod +x`, run **from a terminal**.
4. Feed it a known input and check a known output, ideally one published by somebody else.

Step 4 is the one people skip. A shell can render perfectly and still be wired to the wrong
thing.

## Sources

- Tails package manifests: `https://tails.net/torrents/files/tails-amd64-<version>.packages`
- appimagetool: <https://github.com/AppImage/appimagetool>
- Tauri Linux prerequisites: <https://tauri.app/start/prerequisites/>
- A worked example, where all of the above came from:
  <https://github.com/PeteSparrowBTC/dice-to-seed>

---

*Collaboration by Claude*
