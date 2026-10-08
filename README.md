# Rigs

Control a **Dr. Dabber Switch 2** and a **Puffco Peak Pro** from one screen over Bluetooth. No account, no cloud, nothing leaves your device.

**Use it:** https://ijoshi129.github.io/rigs/

- **Android, Mac, Windows, Linux:** open the link in Chrome, Edge, or Brave.
- **iPhone:** open the link in [Bluefy](https://apps.apple.com/app/bluefy-web-ble-browser/id1492822055), Path Browser, or LabLink. Safari has no Web Bluetooth.
- Close the official Puffco or Dr. Dabber app first; each rig accepts one connection at a time.

Try it without hardware: https://ijoshi129.github.io/rigs/?mock&demo

## What's here

| Folder | What |
| --- | --- |
| `web/` | The web app (Vite, React, TypeScript, Tailwind). Deployed to GitHub Pages on every push. |
| `web/src/rigkit/` | Both protocols in TypeScript: Switch 2 packets, Puffco's Lorax handshake and paths, device drivers, simulators, tests. |
| `RigKit/` | The same protocol layer as a Swift package, with tests. |
| `Rigs/` | A native iOS app on top of RigKit (SwiftUI). Built with XcodeGen from `project.yml`. Sideload or TestFlight only; Apple does not admit this category to the App Store. |

## Develop

```bash
cd web
npm install
npm run dev        # http://localhost:5173/rigs/?mock&demo for simulated rigs
npm test
```

Real Bluetooth needs a secure context: `localhost` counts, so the dev server works as is.

## Protocols

Both protocols were reverse-engineered from the vendors' own shipping software and from prior open-source work. The Switch 2 protocol was read from the official web app's JavaScript. The Peak Pro protocol builds on [puffco-py](https://github.com/SoyMilkIsOk/puffco-py), [home-assistant-puffco](https://github.com/SRVR-JOE/home-assistant-puffco), and [Fr0st3h's writeup](https://github.com/Fr0st3h/Puffco-Reverse-Engineering-Writeup).

Not affiliated with Puffco or Dr. Dabber. Dr. Dabber states that third-party app use may void the warranty. Firmware updates can change either protocol. Use at your own risk.

## License

MIT
