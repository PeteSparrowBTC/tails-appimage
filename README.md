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

### What is there for handing the artifact over

The same manifest answers the questions that come up once you stop building and start delivering.
These four decide what a user without a terminal can actually do:

| | present? | version |
| --- | --- | --- |
| `zenity` | yes | 4.1.90-1 |
| `file-roller`, the Archive Manager | yes | 44.5-1 |
| `7zip` | yes | 25.01+dfsg-1~deb13u2 |
| `nautilus`, GNOME Files | yes | 48.3-2 |
| `coreutils`, so `sha256sum` | yes | 9.7-3 |
| `gnome-console`, a terminal | yes | 48.0.1-2+b1 |
| **`unzip`** | **no** | |
| **`zip`** | **no** | |

**`unzip` is not installed**, which surprises people who assume it is part of a base system. Zip
extraction on Tails happens through Archive Manager or `7z`, never `unzip`, so any instruction
containing the word `unzip` is wrong for this platform. Extracting through the file manager works
and needs no terminal.

**`zenity` is there**, and that is what makes a script launched from the file manager able to say
anything at all. See the delivery section below.

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
- **Publish the checksum** beside the binary. An AppImage is an opaque blob, and the checksum is
  what a user can check it against without building it themselves. Be precise about what that
  buys: it proves the file is intact and was not altered in transit or on the stick. It is not a
  signature, and it travels with the file it describes, so it cannot establish that neither was
  substituted. Say so, and point at a second source for the hash, such as the build log of the
  tagged run, which prints it at the moment the file was made and cannot be edited afterwards.

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

1. **The executable bit is gone**, because the file crossed a FAT or exFAT stick or came from
   Windows. This is the usual one. `chmod +x`, or Properties and "Executable as Program" in the
   file manager.
2. **The USB may be mounted `noexec`.** Copy to `~` first, which fixes 1 and 2 together.
3. **It is a script rather than a binary.** GNOME Files opens an executable `.sh` in the text
   editor when you double-click it, which looks like nothing happening if the editor is behind
   the window you were watching. Right-click and choose **Run as a Program**. That entry only
   appears when the file is already executable, so a missing entry means problem 1, not a missing
   feature.
4. **Your own pre-flight check is broken.** See below.

An earlier version of this list led with "GNOME Files does not launch binaries on double-click".
**That is wrong for Tails 7**, and it was corrected by testing rather than reasoning: on
2026-08-11, on a Tails session with `nautilus 48.3`, an AppImage carrying its executable bit
launched on a plain double-click with no terminal and no Properties step. The claim was true of
some GNOME versions and it is not true of this one. What GNOME Files will not do is run a
**script** on double-click, which is a different thing and is item 3 above.

The practical consequence is in the delivery section: if the artifact reaches the user with its
mode intact, there is no chmod step at all.

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

## Delivery: ship a zip, because the checksum has to be inside the artifact

Everything above gets you a file that runs. It does not get you a user who checked it, and on
Tails the gap between those two is larger than it looks.

**The problem.** "Download it, verify the SHA-256, copy it to a stick" is an instruction that can
only be followed by someone with a terminal, a browser and a second screen. At the machine where it
matters there is none of that: the session is offline, there is no release page to read, and the
only documentation present is whatever is on the stick. So the verification step is not skipped
through laziness. It is skipped because at that moment it is impossible.

**The fix is to make the artifact carry its own verification.** Ship a zip:

```
yourapp-1.2.3-tails/
  yourapp-1.2.3-x86_64.AppImage     mode 644, deliberately not executable
  SHA256SUMS                        the AppImage's hash, bare filename
  start-here.sh                     mode 755, the only launch path
  READ-THIS-FIRST.txt               plain language, no jargon, no terminal
```

The user extracts it in the file manager, drags the folder to Home, right-clicks `start-here.sh`
and chooses "Run as a Program". The script checks the AppImage against `SHA256SUMS`, refuses to
continue if they disagree, and launches it if they match.

Five things decide whether that is a verification or a decoration.

**Report through `zenity`, never stdout.** A script launched from a file manager has no terminal
attached, so anything it prints goes nowhere. A check that fails silently is worse than no check,
because it teaches the user that silence means success. Tails ships `zenity 4.1.90`. Keep a stderr
fallback for the CI case, where there is no display.

```sh
fail() {
    if command -v zenity >/dev/null 2>&1; then
        zenity --error --width=460 --text="$1"
    else
        printf 'ERROR: %s\n' "$1" >&2
    fi
    exit 1
}
```

**Launch the app on success.** If the script only verifies, the user still has to launch the app
separately, and then verifying is an optional extra step that gets dropped. Launching from inside
the checker makes the checked path the easy path.

**Store the AppImage non-executable, and let the script `chmod` it after the check passes.** This is
the part that is easy to get backwards. A zip built by Info-ZIP stores Unix modes, and Archive
Manager on Tails restores them, so an AppImage stored 755 arrives ready to double-click. That
sounds like a convenience and it is a hole: double-clicking the app is then easier than
right-clicking the script, so the fastest route to the application is the one that skips the
verification. Storing it 644 means the app cannot run until something has checked it. A determined
user can still set the bit by hand, which is fine: that is a deliberate act, not an accident.

**Generate the hash into the bundle at build time, from the file being shipped.** Never copy a hash
between files. If the instructions quote it as well, substitute it from the same value, so a reader
comparing the text against `SHA256SUMS` cannot be shown two different numbers.

**State the limit in the artifact itself.** `SHA256SUMS` sits in the same folder as the app it
describes, so whoever could replace one could replace all three. The check proves the file was not
damaged, half-copied or altered on the stick. It does not prove the download was genuine, and
whoever prepared the stick is who is being trusted for that. Write that in the instructions in
plain words. A bundle that implies more than it delivers is the failure mode this whole document
exists to avoid.

### Build it in CI, and test the refusal

Assemble the zip in the same script your release job and your pull-request job both call, so the
artifact that gets reviewed is the artifact that gets published. Then assert the two things that
are not self-evident:

```bash
# 1. the archive stores the modes it is supposed to. This is a property of the zipping
#    tool, not a certainty.
zipinfo bundle.zip | grep -qE "^-rwxr-xr-x.* start-here\.sh$"      || exit 1
zipinfo bundle.zip | grep -qE "^-rw-r--r--.* yourapp.*\.AppImage$" || exit 1

# 2. the checker refuses a file that does not match. A verification that has never
#    failed is not known to work.
cp -r bundle tampered && printf 'x' >> tampered/yourapp-*.AppImage
if ( cd tampered && ./start-here.sh --check-only ); then exit 1; fi
```

Give the script a `--check-only` flag for exactly that test, so CI can exercise the check without
trying to open a window on a runner with no display.

[`templates/tails-bundle/`](templates/tails-bundle/) has all three files, ready to adapt: the
builder, the launcher, and the instructions with the version and hash substituted in.

### What is verified here and what is not

Field-tested on 2026-08-11, on Tails with `nautilus 48.3` and Archive Manager 44.5:

- Extracting a zip through the file manager restores the stored executable bit. An AppImage stored
  755 extracted from a zip and ran on a plain double-click, with no Properties step.
- A `.sh` extracted with its bit intact runs from the right-click "Run as a Program" entry.
- `unzip` is absent, so extraction is the GUI path or `7z`.

**Not yet field-tested:** the 644 recommendation above, which is reasoned rather than observed. The
`chmod` happens on a file in Home, so there is no plausible failure, but the honest state of it is
untested and this note stays until somebody runs it.

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
