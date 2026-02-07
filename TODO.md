# ClawReach TODO

## In Progress
- [ ] **Persistent CI signing key** — upload keystore in GitHub Secrets so builds don't change signing key (no more uninstall/reinstall)
- [ ] **Single pairing for both roles** — node connection waits for operator pairing, reuses same approval (one pairing instead of two)
- [ ] **Hot-reload pairing** — gateway watches devices.json for changes, picks up approvals without restart
- [ ] Test full canvas round-trip (eval, snapshot, actions, events)

## Connection & Pairing Improvements
- [x] **Deep link pairing** — `clawreach://connect?url=...&token=...&fallback=...&name=...` URI scheme
- [x] **QR code pairing** — scan JSON or deep link format QR codes to auto-configure
- [x] **mDNS/Bonjour discovery** — scan LAN for `_openclaw._tcp` service + port scan fallback
- [x] **Persistent connection service** — Android foreground service keeps node WebSocket alive
- [ ] **Token-free LAN pairing** — auto-trust devices on same subnet with on-device confirmation prompt

## Backlog
- [ ] Onboarding — guided first-run flow (gateway URL, token, pairing walkthrough)
- [ ] Chat UI polish — swipe to reply, markdown rendering, image previews
- [ ] Handle canvas overlay dismiss/re-show properly on navigation
- [ ] Screen recording capability (advertise to gateway)
- [ ] Microphone permission + voice note support
- [ ] VAPID keys for production web push notifications

## Done
- [x] Ed25519 crypto, WebSocket gateway, auto-reconnect
- [x] Dark theme, fox emoji launcher icon + splash
- [x] Dual WebSocket (operator + node)
- [x] Chat interface with streaming
- [x] Camera (front/back snap)
- [x] Push notifications (enhanced with canvas alerts, message alerts, service workers)
- [x] Location sharing
- [x] Canvas/A2UI WebView integration + JS bridge
- [x] Canvas postMessage bridge for web (bidirectional communication, eval/snapshot support)
- [x] Settings — smart URL fallback (local + Tailscale)
- [x] Connection status badge (green dot + route label)
- [x] Pairing flow — UX feedback (banner, states, validation)
- [x] Auto-connect on settings save
- [x] Generic placeholder URLs in settings
