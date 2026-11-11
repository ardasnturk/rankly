# Rankly local API (v1)

Rankly exposes a small HTTP API on this Mac so other tools — [Vitrin](https://github.com/ardasnturk/vitrin), scripts and MCP clients such as Claude Code — can use its rank tracking and analyses.

- Address: `http://127.0.0.1:47390` (if busy, the next free port up to `47394`; shown in **Settings → Integrations**)
- Only listens on `127.0.0.1`. Requests with an `Origin` header (browsers) or a foreign `Host` header are rejected.
- Everything except `GET /v1/status` and `POST /v1/pair` needs `Authorization: Bearer <token>`.
- Can be turned off in **Settings → Integrations**. Paired clients are listed there and can be revoked.
- JSON in, JSON out. Dates are ISO 8601. Errors: `{"error": "…"}` with a 4xx/5xx status.
- App Store requests made on your behalf go through Rankly's paced client; if Apple temporarily blocks search, endpoints that need it answer `503`.

## Pairing

```http
POST /v1/pair
{"client": "Vitrin"}
```

Rankly shows a dialog (“Allow “Vitrin” to connect to Rankly?”). The request waits for the answer:

- `200 {"token": "rk_…", "client": "Vitrin"}` — store the token; it is never shown again.
- `403` — the user denied. `409` — another pairing dialog is open.

Only a SHA-256 hash of the token is stored in Rankly.

## Endpoints

| Method | Path | Body / query | Result |
| --- | --- | --- | --- |
| GET | `/v1/status` | — | `{app, version, api, authorized, client?}` |
| GET | `/v1/apps` | — | `{apps: [{appId, bundleId?, name, developer, iconURL?, competitor, keywordCount, countries}]}` |
| GET | `/v1/apps/resolve` | `?bundleId=` or `?appId=`, `&country=` | `{appId, bundleId, name, tracked, competitor}` (looks up the App Store when not tracked) |
| POST | `/v1/apps` | `{appId? \| bundleId?, competitor?, country?}` | Tracks an app |
| GET | `/v1/keywords` | `?appId=` (or `bundleId`), `&country=` optional | `{keywords: [{term, country, rank, change, popularity, difficulty, lastCheckedAt, error, history: [{date, rank}]}]}` |
| POST | `/v1/keywords` | `{appId? \| bundleId?, country, terms: [..]}` | Adds keywords to daily tracking (adds the app if needed) and refreshes them: `{appId, added, existing}` |
| POST | `/v1/ranks` | `{appId? \| bundleId?, country, terms: [..≤60], rivals?: [appId]}` | Live App Store search ranks: `{appId, country, source, ranks: {term: {rank, results, rivals?}}}` |
| GET | `/v1/analysis` | `?appId=&country=` | `{analysis: AnalysisResult \| null, running: {phase, fraction, error}?}` |
| GET | `/v1/analysis/countries` | `?appId=` | `{countries: [{country, createdAt, ranked, opportunities, competitors}]}` |
| POST | `/v1/analysis` | `{appId? \| bundleId?, countries: [..]}` | Starts a single or multi-country analysis in the background |
| GET | `/v1/analysis/status` | `?appId=` | `{batch?, running: [...]}` |
| GET | `/v1/events` | `?appId=` | Timeline events |
| POST | `/v1/events` | `{appId? \| bundleId?, note, kind?: "release" \| "note", date?, countries?}` | Adds a marker shown on rank charts |
| DELETE | `/v1/events` | `?id=` | Removes a marker |

`popularity` is an estimate (5–100) from App Store autocomplete, not Apple's Search Ads score. `difficulty` is 0–100.

`AnalysisResult` contains `myKeywords` (terms the app ranks for), `missedTitleTerms` (name/subtitle terms it does not rank for), `competitors` (with `sharedKeywords`, `rankedKeywords`, `sameGenre`), `opportunities` (`term`, `myRank`, `competitorRanks`, `popularity`, `difficulty`, `score`) and `keywordField`. Keyword `source` values: `name`, `subtitle`, `description`, `suggestion`, `competitor`.

## MCP

`POST /mcp` speaks the Model Context Protocol (Streamable HTTP, JSON responses). Tools: `list_apps`, `get_keywords`, `get_analysis`, `list_analyses`, `run_analysis`, `analysis_status`, `track_keywords`, `check_ranks`, `add_event`.

**Settings → Integrations → Connect Claude Code (MCP)…** creates a token and shows the command, for example:

```bash
claude mcp add --transport http rankly http://127.0.0.1:47390/mcp --header "Authorization: Bearer rk_…"
```

## Example

```bash
TOKEN=$(curl -s -X POST -d '{"client":"my script"}' http://127.0.0.1:47390/v1/pair | jq -r .token)
curl -s -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:47390/v1/apps/resolve?bundleId=com.example.app"
curl -s -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:47390/v1/analysis?appId=123456789&country=us"
```
