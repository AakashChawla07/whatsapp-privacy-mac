# Phase 0 Spikes — Runbook

Four throwaway tools answer the open questions in `docs/ARCHITECTURE.md` §15.1 before Phase 2.
None of them read message text, contact names, titles or values — only roles, frames and window metadata.
Output files go to `spikes-output/` (git-ignored).

## One-time setup

1. **Give your terminal Accessibility access** (the tools run inside it):
   System Settings → Privacy & Security → Accessibility → **+** → add your terminal app
   (Terminal, iTerm, VS Code…) → switch it on → **quit and reopen the terminal**.
2. Open WhatsApp, logged in, main window visible (not minimized), chat list showing several chats.
3. `cd` into the project. The first `swift run` compiles the tools (~30 s).

> Do **not** give the terminal Screen Recording permission — S5 must reflect what the app gets without it.

---

## S1 — What does WhatsApp's accessibility tree expose? (`ax-dump`)

```sh
swift run ax-dump --label light
```
Then switch WhatsApp to dark appearance (System Settings → Appearance, or WhatsApp's own theme setting) and:
```sh
swift run ax-dump --label dark
```
Optional extra captures: make the window narrow (`--label narrow`), scroll the chat list down (`--label scrolled`).

**What to look for in the printed summary**
- *Row-list candidates*: is there a candidate on the left with rows ≈ number of visible chats and a row height ≈ 60–80 pt?
- *Descendants of the first rows*: are there separate `AXStaticText` elements for name / preview / time with sensible frames?
- `none` or rows with 0 text elements → WhatsApp does not expose row detail (MVP will use column coverage).

**Send back:** the printed summary of each run. The JSON files stay in `spikes-output/` — I can read them directly.

---

## S2 — Which blur makes previews unreadable? (`blur-lab`)

```sh
swift run blur-lab
```
A frosted overlay appears over WhatsApp's left sidebar, plus a control window.

1. Use **Sidebar width / Top inset** so the overlay covers the chat list (not the header/search).
2. For **Style = Material blur + tint**, try materials `hudWindow`, `popover`, `sidebar`, `menu`.
   For each, lower **Tint opacity** until previews become *just readable*, then raise it until they are
   clearly unreadable. Note that value.
3. Check from normal distance **and ~1 m away**, in **light and dark** mode.
4. Try **Tint only** — does blur add anything over a tint alone?
5. Try **Left inset ≈ 64–72** — does leaving avatars visible still hide the text?

**Send back:** for light and dark: best material + minimum unreadable tint; how it looks (subtle / ugly / fine).

---

## S3 — Does the overlay stay above WhatsApp and below other apps? (`blur-lab`)

Same tool. Watch the **stacking** line in the control window and the terminal log:
`✓ directly above WhatsApp` · `✗ BELOW WhatsApp — previews EXPOSED` · `△ … also covering other window(s)`.

With **Level = Hybrid** (default):
1. Click WhatsApp, then click another app window that overlaps WhatsApp, then back — several times.
2. Use ⌘-Tab between WhatsApp and other apps.
3. Drag another app's window partly over WhatsApp's sidebar while WhatsApp is in the background.
4. Put WhatsApp in full screen, switch Spaces, come back.

Repeat briefly with **Always .floating** and **Always .normal + order above WA** for comparison.

**Send back:** the terminal log (it includes stacking changes with ms-after-activation timings) and whether you
ever *saw* the previews flash unblurred.

---

## S4 — Which notifications fire during drag / resize / scroll / typing? (`ax-watch`)

```sh
swift run ax-watch
```
Keep it running and do each action slowly, pausing ~2 s between them:
1. Drag the WhatsApp window around for a few seconds.
2. Resize it from a corner.
3. Scroll the chat list up and down.
4. Click into search and type a few letters, then clear it.
5. Click a few different chats.
6. Wait for / send yourself a message so a chat moves to the top.
7. Minimize and restore; ⌘H hide and show; switch to another app and back.

Press **Ctrl+C** for the summary.

**Send back:** the summary block (and the log if something looks odd).

---

## S5 — What does CGWindowList expose without Screen Recording? (`window-list`)

```sh
swift run window-list
swift run window-list --watch     # then minimize, hide, full screen, switch Space, cover it; Ctrl+C to stop
```

**Already observed (2026-09-14, WhatsApp 26.30.77, no Screen Recording):** window number, layer, bounds,
on-screen flag and z-order are available; titles are withheld. WhatsApp owns several extra off-screen
layer-0 windows (1470×33 strips, small squares), so the main window must be matched by AX frame, not
"first WhatsApp window". Re-run after granting Accessibility to confirm the AX ↔ CGWindowID match line.

**Send back:** output of the `--watch` session.

---

## After the spikes

Paste the results in the conversation. They will be used to:
- fill `WhatsAppProfile` (list roles, row heights, header band, avatar gutter),
- set the blur intensity table and legibility floor (F2),
- choose the overlay level policy or occlusion-mask fallback (F8),
- decide whether a live drag sampler is needed (§7.5) and which notifications invalidate layout,
- record findings in `docs/spikes/findings.md` and update `ARCHITECTURE.md`.
