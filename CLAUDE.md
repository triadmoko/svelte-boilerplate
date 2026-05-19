---
description:
alwaysApply: true
---

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Claude Context MCP — WAJIB

> **ATURAN KERAS**: Setiap kali perlu menjelajahi atau memahami kode di repo ini, **WAJIB** gunakan Claude Context MCP terlebih dahulu. DILARANG langsung memakai `grep`, `find`, Bash, atau spawn Agent Explore sebelum mencoba Claude Context.

### Langkah wajib sebelum eksplorasi codebase:

1. Load tool via `ToolSearch` dengan query: `select:mcp__claude-context__search_code,mcp__claude-context__get_indexing_status`
2. Jalankan `get_indexing_status` untuk memastikan index siap
3. Gunakan `search_code` dengan natural-language query dan `path` = absolute path repo ini

### Tool yang tersedia:

- **`search_code`** — Semantic search dengan `query` natural language; set `path` ke absolute path repo ini. Gunakan untuk menemukan fitur, route, use case, handler, entity, dan call site.
- **`get_indexing_status`** — Cek apakah workspace sudah terindeks dan siap; jika belum, jalankan `index_codebase` dulu.
- **`index_codebase`** — Index atau re-index repo ini setelah perubahan besar atau saat search gagal karena belum terindeks.

### Fallback:

Hanya boleh fallback ke `grep`/`find`/Bash/Agent **jika** Claude Context MCP tidak tersedia (server down/disabled) atau hasil search benar-benar tidak cukup setelah beberapa query.

## Commands

Package manager: **bun** (bun.lock; Dockerfile uses `oven/bun:1.2-alpine`). Use `bun install`, `bun run <script>`.

- `bun run dev` — start vite dev server
- `bun run build` — production build (output in `build/`, served via `bun build/index.js`)
- `bun run preview` — preview production build
- `bun run check` — `svelte-kit sync` + `svelte-check` against `tsconfig.json` (this is the type-check; there is no separate `tsc` step)
- `bun run lint` / `bun run format` — Prettier check / write
- `bun run swag` — regenerate `src/lib/api/api.ts` from the staging Swagger spec (`swag-local` points at `192.168.2.79:9001` for local backend). Run this whenever the backend contract changes; do not hand-edit `src/lib/api/api.ts`.

There is no test runner configured.

## Architecture

### Stack

SvelteKit 2 + Svelte 5 with **runes mode forced on** for all non-`node_modules` files (see `svelte.config.js`). TypeScript strict. Tailwind CSS **v4** via `@tailwindcss/vite` — there is no `tailwind.config.*`; tokens are declared as CSS custom properties + `@theme inline` in `src/routes/layout.css`. shadcn-svelte (style `vega`, base color `mist`, icon library `tabler`) provides UI primitives in `src/lib/components/ui/`. Adapter is `svelte-adapter-bun` (production target is Bun, not Node).

Path aliases: `$lib` (SvelteKit default → `src/lib`) and `@/*` → `./src/*` (configured in `svelte.config.js`).

### Feature layout (DDD-ish)

Domain logic lives under `src/lib/features/<feature>/` with four sub-folders:

- `domain/` — types and repository **interfaces** (e.g. `auth.types.ts` declaring `AuthRepository`). No I/O.
- `application/` — pure use-cases and constants (`login.use-case.ts`, `auth.constants.ts`). Validation + orchestration; takes a repository as a parameter.
- `infrastructure/` — repository implementations. Two flavors per feature:
  - `api-*.repository.ts` uses `$lib/server/api-client` (server-only, reads `API_BASE_URL` from `$env/dynamic/private`).
  - `api-*.client.ts` uses `$lib/api/client` (browser-safe, reads `PUBLIC_API_BASE_URL` from `$env/dynamic/public`) and accepts the bearer token via constructor.
  - May also include a `mock-*.repository.ts` for offline/dev.
- `components/` — feature-specific Svelte components.

Each feature exposes a barrel:

- `index.ts` — browser-safe re-exports (constants, types, use-cases, client repo).
- `index.server.ts` — server-only re-exports (server repo). **Never import `index.server.ts` from client code.**

When adding a feature, mirror this shape and keep use-cases free of HTTP/SDK calls — they should depend on the domain interface only.

### Authentication & sessions

- Session is a JSON blob in the `tulip_session` cookie (`httpOnly`, `sameSite: strict`, 12h `maxAge`). Helpers in `src/lib/server/session.ts`.
- `src/hooks.server.ts` reads the cookie on every request, hydrates `event.locals.user` / `event.locals.token` (typed in `src/app.d.ts`), and applies a **sliding 12h window** by re-setting the cookie on each request.
- Route guards live in the same hook: `PROTECTED_PREFIXES = ['/admin', '/profile']` redirect to `/auth/login?redirectTo=…` when unauthenticated; `GUEST_ONLY_PATHS = ['/auth/login']` redirect to `AUTH_ROUTES.home` when already logged in.
- `+layout.server.ts` exposes `{ user, token }` to all pages so client-side feature repos (`api-*.client.ts`) can grab the bearer token via `page.data.token`.
- After login, `src/routes/auth/login/+page.server.ts` chooses the redirect: admins → `/admin`, others → `/`.

### API client

`src/lib/api/api.ts` is **auto-generated** by `swagger-typescript-api` from the backend Swagger doc — regenerate, don't edit. Two singleton wrappers:

- `src/lib/server/api-client.ts` — `new Api({ baseURL: env.API_BASE_URL })` for server-side use (load functions, form actions, `+page.server.ts`).
- `src/lib/api/client.ts` — `new Api({ baseURL: env.PUBLIC_API_BASE_URL ?? '' })` for browser use.

Both export `bearerHeader(token)` which returns the `RequestParams` shape with the `Authorization` header. Server repos read the token from `locals`; client repos receive it via constructor.

### Routes

`(guest)` is a layout group for the public landing page. `admin/` and `profile/` are protected by the hook. Admin pages currently use `ApiAdminClientRepository` (browser-side calls with token from `page.data`) for interactive list/mutate flows; server-side admin repo exists in parallel for SSR loaders.

## Conventions

- **User-facing strings are Indonesian** (see `auth.constants.ts` `AUTH_MESSAGES`, error messages in repositories). Match the existing tone when adding new strings.
- Prettier enforces tabs, single quotes, no trailing comma, `printWidth: 100`. The `prettier-plugin-tailwindcss` reads classes from `src/routes/layout.css` for class sorting. Run `bun run format` before committing.
- Imports use explicit `.js` extensions on relative paths (TS `rewriteRelativeImportExtensions` is on) — follow the existing pattern.
- Repository methods return discriminated unions (`{ ok: true, ... } | { ok: false, code, message }`) instead of throwing. Map HTTP statuses to domain codes (`UNAUTHORIZED`, `FORBIDDEN`, `INVALID_CREDENTIALS`, `VALIDATION_ERROR`, `UNKNOWN_ERROR`) with localized messages — keep new repos consistent with this.
