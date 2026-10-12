# Rigs

Control a **Dr. Dabber Switch 2** from your phone over Bluetooth. No account, no cloud, nothing leaves your device.

**Use it:** https://ijoshi129.github.io/rigs/

- **Android, Mac, Windows, Linux:** open the link in Chrome, Edge, or Brave.
- **iPhone:** open the link in [Bluefy](https://apps.apple.com/app/bluefy-web-ble-browser/id1492822055), Path Browser, or LabLink. Safari has no Web Bluetooth.
- Close the official Dr. Dabber app first; the rig accepts one connection at a time.

Try it without hardware: https://ijoshi129.github.io/rigs/?mock&demo

## What it does

- Live chamber temperature, hold countdown, and the session's heat trace
- Start, stop, and extend a session; switch presets with one tap
- Edit the five presets: temperature, hold time, heating profile
- Lights: the rig's own LED modes, brightness, haptics, auto shut-off, cleaning assist, rename
- A session log kept on the phone
- Themes: light or dark, wallpaper colors, glass frost and glow, all yours to set

## What's here

| Folder | What |
| --- | --- |
| `web/` | The web app (Vite, React, TypeScript, Tailwind). Deployed to GitHub Pages on every push. |
| `web/src/rigkit/` | The Switch 2 protocol in TypeScript: packets, state, device driver, simulator, tests. |
| `RigKit/`, `Rigs/` | An earlier native iOS prototype and its Swift protocol package. Not maintained; the web app is the product. |

## Develop

```bash
cd web
npm install
npm run dev        # http://localhost:5173/rigs/?mock&demo for a simulated rig
npm test
```

Real Bluetooth needs a secure context: `localhost` counts, so the dev server works as is.

## Protocol

The Switch 2 protocol was reverse-engineered from the official web app's JavaScript at drdabber.app. It is an unauthenticated packet protocol over one write and one notify characteristic; every opcode and status packet the official app uses is implemented in `web/src/rigkit/switch2/`.

Not affiliated with Dr. Dabber. Dr. Dabber states that third-party app use may void the warranty. Firmware updates can change the protocol. Use at your own risk.

## License

MIT
