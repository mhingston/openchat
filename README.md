# OpenChat

OpenChat is a Flutter chat client with a ChatGPT-style interface, local conversation history, configurable AI providers (OpenAI-compatible and Anthropic-compatible), attachments, voice input, and optional web search/browsing support for questions that need live context.

## Screenshots

<p align="center">
  <img src="assets/readme/provider-setup.png" alt="Provider setup sheet" width="31%" />
  <img src="assets/readme/home-empty-state.png" alt="OpenChat empty state" width="31%" />
  <img src="assets/readme/chat-with-web-results.png" alt="OpenChat chat with web-backed answer" width="31%" />
</p>

## Current feature set

- Responsive chat UI for mobile, desktop, and web.
- Provider setup flow with presets for OpenAI, Anthropic, OpenCode Go, OpenRouter, Groq, Together AI, DeepSeek, Ollama Cloud, and custom OpenAI-compatible or Anthropic-compatible endpoints. OpenCode Go automatically routes MiniMax models to the Anthropic-compatible endpoint and all other models to the OpenAI-compatible endpoint — no separate provider config needed.
- Model fetching plus cached model lists for previously configured providers.
- Streaming assistant responses with markdown and code block rendering, with auto-scroll to follow new content.
- Attachment support for camera, photos, and files.
- Local conversation history with rename, duplicate/fork, delete (swipe-to-delete on mobile), pin, and search.
- **Prompt library** — save named prompt templates, each with a system message and optional model and temperature overrides. Access from the drawer, tap a prompt to start a new thread with those settings pre-applied. Threads show a badge indicating which prompt they were started from. Prompts are included in JSON export/import.
- Export conversations as JSON or Markdown and import saved chat data.
- Voice input on iOS, Android, and supported web browsers.
- Optional web search with a tiered provider stack that degrades gracefully based on which API keys are configured:
  - **Exa** (highest priority) — neural search with LLM-optimised highlights (10x token efficient). Supports `auto` (~1s), `deep` (5–60s for complex research), and `news` search types. Free tier at dashboard.exa.ai.
  - **Tavily** — single API call returns search results and full page content, handles JS-heavy sites and anti-bot protection.
  - **Brave Search** — reliable JSON search results, replaces DuckDuckGo HTML scraping.
  - **Firecrawl** — content extraction for JS-rendered pages and Cloudflare-protected sites.
  - **Jina AI Reader** — higher rate limits when an API key is configured; used unauthenticated as a fallback.
  - **DuckDuckGo + direct HTTP** — always-available fallback requiring no configuration.

  API keys are optional and configured in Settings → Web Search. Multi-step link-following surfaces article content from news homepages. Web search preference is persisted across sessions.
- Source URL citations shown inline on web-search-backed responses. URLs in assistant messages are tappable.
- Auto-generated conversation titles after the first exchange.
- Inline copy button on assistant messages.
- Starter prompt chips in ready-to-chat empty states for quick composer prefills.
- Theme selection plus desktop/web keyboard shortcuts, with an in-app shortcuts help button in the header.

## Keyboard shortcuts

On desktop and web, use `Cmd` on Apple platforms and `Ctrl` elsewhere:

- `Cmd/Ctrl+N` or `Cmd/Ctrl+K` — new chat
- `Cmd/Ctrl+F` — search conversations
- `Cmd/Ctrl+,` — settings
- `Cmd/Ctrl+[` — previous conversation
- `Cmd/Ctrl+]` — next conversation
- `Cmd/Ctrl+Enter` — send
- `Cmd/Ctrl+/` — toggle web search
- `Esc` — clear the current draft

Use the header shortcuts button to see the same list in-app.

## Local development

### Prerequisites

- Flutter stable
- Dart SDK (bundled with Flutter)

### Install dependencies

```bash
flutter pub get
```

### Run the app

```bash
flutter run
```

### Run the web preview

OpenChat uses a small local proxy during web development so the browser can call provider APIs and fetch public web pages (including Jina Reader at `r.jina.ai`) without CORS issues.

Start the proxy:

```bash
dart run tool/web_cors_proxy.dart
```

Then start the app in web-server mode:

```bash
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8101
```

Open `http://127.0.0.1:8101` in your browser.

By default the proxy listens on `http://127.0.0.1:8081/proxy`.

Useful proxy environment variables:

```bash
OPENCHAT_PROXY_ALLOWED_HOSTS=host1,host2 dart run tool/web_cors_proxy.dart
OPENCHAT_PROXY_PORT=8082 dart run tool/web_cors_proxy.dart
```

The default allowlist already includes:

- `api.openai.com`
- `api.anthropic.com`
- `opencode.ai`
- `openrouter.ai`
- `api.groq.com`
- `api.together.xyz`
- `api.deepseek.com`
- `ollama.com`
- `api.duckduckgo.com`
- `html.duckduckgo.com`
- `api.tavily.com`
- `api.search.brave.com`
- `api.firecrawl.dev`
- `api.exa.ai`

All other public hostnames (including `r.jina.ai`) are permitted automatically via an IP-range check that blocks loopback, link-local, and RFC-1918 addresses.

Common local helper scripts live under `tool/`, including `dart run tool/local_checks.dart` and `dart run tool/top_level_tests.dart`.

## Quality checks

Run the standard local checks:

```bash
dart run tool/local_checks.dart
```

Run the top-level unit/widget tests only:

```bash
dart run tool/top_level_tests.dart
```

Run static analysis:

```bash
flutter analyze
```

Run tests (unit tests only — integration tests require live API credentials):

```bash
flutter test $(find test -maxdepth 1 -name "*_test.dart" | sort | tr '\n' ' ')
```

Run integration/E2E tests against a live provider:

```bash
OPENCHAT_TEST_BASE_URL=https://ollama.com \
OPENCHAT_TEST_API_KEY=<key> \
OPENCHAT_TEST_MODEL=<model> \
OPENCHAT_TEST_PRESET=ollama-cloud \
flutter test test/integration/e2e_test.dart
```

The repository also includes GitHub Actions that run both commands automatically on pushes and pull requests.

## GitHub Actions and release flow

This repository ships with two workflows:

- `CI` installs dependencies, runs `flutter analyze`, and runs `flutter test`.
- `Release Builds` runs for tags matching `v*` and publishes release artifacts to GitHub Releases.

The tagged release workflow currently produces:

- Android APK: `app-release.apk`
- Android App Bundle: `app-release.aab`
- iOS simulator archive: `OpenChat-ios-simulator.zip`

Trigger a release build with:

```bash
git tag v0.1.0
git push origin v0.1.0
```

## Release notes

- Android artifacts are built in CI and are useful for testing, but production signing is not configured yet.
- The iOS artifact is an unsigned simulator build for review/testing, not an App Store or physical-device build.
- Signed store-ready mobile releases still require platform signing credentials and provisioning setup.
