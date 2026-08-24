# Making DRIFT an .exe

## The short version

On a Windows machine with the project folder:

1. Install Node.js from [nodejs.org](https://nodejs.org) — LTS, accept the defaults.
2. Double-click **`BUILD-WINDOWS.bat`**.

You get `dist/DRIFT-1.0.0-portable.exe`. That's a single self-contained file — no
installer, no runtime to install, double-click and play. It's the right thing to send
someone.

On macOS, double-click `BUILD-MACOS.command` instead. From a terminal on any platform:

```bash
node build.mjs --win --portable
```

The first build downloads Electron (~250MB) and takes a few minutes. Later builds take
seconds.

## Why I can't just hand you the .exe

An `.exe` isn't your game code — it's your game bundled with a whole Chromium runtime,
which is ~250MB of prebuilt Windows binaries that have to be downloaded from Electron's
release servers. The environment I'm working in has no network access, so I can't fetch
them, and I can't fabricate them.

What I've done instead is remove every other obstacle: the icon is generated, the build
config is written, the targets are set, and `build.mjs` checks the things that actually
go wrong and explains them in plain language rather than failing three minutes in with a
stack trace. The only step left genuinely requires your machine and a connection.

## What you get

`node build.mjs --win` produces three things, and they're for different purposes:

| Output | What it's for |
|---|---|
| `DRIFT-1.0.0-portable.exe` | one file, no install — hand this to a friend |
| `DRIFT Setup 1.0.0.exe` | conventional installer with Start-menu and desktop shortcuts |
| `win-unpacked/` | the folder **Steam** wants — SteamPipe uploads a directory, not an installer |

Roughly 90–110MB each. That's Chromium, not your game; the game itself is about 180KB.

## The build is gated on the verifier

`build.mjs` runs `tools/verify.mjs` first and refuses to build if any sector fails. This
is deliberate. Given that three genuinely unsolvable levels shipped to you during
development before the verifier existed, the last place a broken sector should be able to
reach is an executable on someone's desktop.

If you ever need to bypass it, run `npx electron-builder --win` directly — but the gate
is there for a reason.

## The SmartScreen warning

Your unsigned exe will make Windows show *"Windows protected your PC"* the first time
anyone runs it. They have to click "More info" then "Run anyway". This is normal for
every unsigned application and it is not something the build can fix.

Removing it needs a code signing certificate:

- **OV certificate** — roughly $200–400/year. Reduces the warning; reputation still
  builds over time.
- **EV certificate** — roughly $300–600/year, needs a hardware token. Bypasses
  SmartScreen immediately.

Worth it if you're selling. Not worth it for sharing a build with friends or testers, or
for a Steam release — **Steam-installed games don't hit SmartScreen**, because Steam is
the trusted installer. So if Steam is the goal, skip the certificate entirely.

To sign later, set these before building and electron-builder picks them up:

```
CSC_LINK=path\to\cert.pfx
CSC_KEY_PASSWORD=yourpassword
```

## Cross-building

- **Windows exe from Windows** — works, nothing extra needed.
- **Windows exe from macOS or Linux** — the `portable` and `dir` targets work. The NSIS
  *installer* needs Wine (`brew install --cask wine-stable`, or `apt install wine`).
  `--portable` sidesteps this.
- **macOS app from anything but a Mac** — not really possible. Apple's toolchain and
  notarization are Mac-only. Use a Mac or a CI runner.

Building all three at once: `node build.mjs --all`.

## Making it smaller

90MB for a 180KB game is the Electron tax. If that bothers you, the alternatives:

- **Tauri** — uses the OS's built-in webview instead of shipping Chromium. Gets you to
  about 5MB. Costs you a Rust toolchain and some rewiring of the native shell, though the
  game code itself would carry over unchanged since it's plain web tech.
- **NW.js** — same size problem as Electron, no real advantage here.
- **Ship the browser build** — `drift-standalone.html` is 67KB and runs anywhere. For
  itch.io or a web release this is strictly better than an exe.

My honest read: Electron's size is a non-issue for a Steam release, where a 90MB download
is unremarkable. It only matters if you're distributing outside a store and want the
download to feel light. Don't take on a Rust toolchain to save megabytes nobody is
counting.

## The icon

`build/icon.ico` is generated from the game's own palette — the teal airlock ring, the
amber data core, the violet rewind trail — so the taskbar icon, the game, and any future
store art read as the same thing. It carries all seven Windows sizes (16 through 256) and
simplifies itself at small sizes: the ghost trail and outer ring drop away below 64px so
it stays a clean ring-and-diamond in the taskbar rather than turning to mush.

To replace it, overwrite `build/icon.png` at 1024×1024 and regenerate, or drop in your
own `build/icon.ico`.
