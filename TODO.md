# ClawReach TODO

## In Progress
- [ ] **Persistent CI signing key** — upload keystore in GitHub Secrets so builds don't change signing key (no more uninstall/reinstall)
- [ ] **Single pairing for both roles** — node connection waits for operator pairing, reuses same approval (one pairing instead of two)
- [ ] **Hot-reload pairing** — gateway watches devices.json for changes, picks up approvals without restart
- [ ] Canvas/A2UI — fix Column children format, test full round-trip
- [ ] Test canvas.hide / canvas.eval / canvas.snapshot / canvas.a2ui.reset

## Connection & Pairing Improvements
- [ ] **QR code pairing** — gateway web UI shows QR with `clawreach://connect?url=...&token=...`, scan to configure
- [ ] **mDNS/Bonjour discovery** — scan LAN for `_openclaw._tcp` service, auto-find gateway IP
- [ ] **Deep link pairing** — `clawreach://connect?...` URI scheme, can be sent via Signal/message
- [ ] **Token-free LAN pairing** — auto-trust devices on same subnet with on-device confirmation prompt
- [ ] **Persistent connection service** — Android foreground service to keep node connection alive when app is closed

## Backlog
- [ ] Onboarding — guided first-run flow (gateway URL, token, pairing walkthrough)
- [ ] Chat UI polish — swipe to reply, markdown rendering, image previews
- [ ] Handle canvas overlay dismiss/re-show properly on navigation
- [ ] Screen recording capability (advertise to gateway)
- [ ] Microphone permission + voice note support

## Done
- [x] Ed25519 crypto, WebSocket gateway, auto-reconnect
- [x] Dark theme, fox emoji launcher icon + splash
- [x] Dual WebSocket (operator + node)
- [x] Chat interface with streaming
- [x] Camera (front/back snap)
- [x] Push notifications
- [x] Location sharing
- [x] Canvas/A2UI WebView integration + JS bridge
- [x] Settings — smart URL fallback (local + Tailscale)
- [x] Connection status badge (green dot + route label)
- [x] Pairing flow — UX feedback (banner, states, validation)
- [x] Auto-connect on settings save
- [x] Generic placeholder URLs in settings
