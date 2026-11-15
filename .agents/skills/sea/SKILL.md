---
name: sea
description: Opt-in SEA (Subtract, Enhance, Add) workflow lens. Activate ONLY when the user explicitly writes /sea or "SEA" in their prompt (including "auto gg SEA ...").
---

# SEA (`/sea`) — Subtract, Enhance, Add

When explicitly invoked via `/sea [target]`, `SEA [target]`, or `auto gg SEA [target]`, evaluate, grill, and execute strictly in **S → E → A** order:

1. **S — Subtract First**: Remove duplicate UI controls, disabled zero-state chrome, stale copy, and dead/unreferenced code before building anything new.
2. **E — Enhance Second**: Harden reliability, eliminate warnings/errors, and streamline existing flows on the surviving surface.
3. **A — Add Last (Minimal)**: Add at most `1` high-leverage capability that Subtract + Enhance cannot solve (or `0` additions when Subtract + Enhance suffices).
