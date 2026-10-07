# PostHog Self-driving setup report

## Summary

PostHog Self-driving is configured for this Rails web application. Session Replay, Error Tracking, and Support are enabled; health, error, support, and the selected GitLab responder are wired into the inbox. Findings should start appearing in the [Self-driving inbox](https://us.posthog.com/project/647060/inbox) within about 30 minutes as scouts begin their first runs.

## AI data processing

Approved by the organization-level setup gate.

## GitHub

The PostHog GitHub App was already connected before this setup run. GitHub Issues was not selected as a Self-driving responder in this run.

## Products enabled

| Product | Result | Notes |
|---|---|---|
| Session Replay | Already enabled | Browser initialization explicitly keeps session recording enabled and masks inputs. |
| Error Tracking | Enabled | Browser initialization does not disable exception capture; the Rails SDK enables exception autocapture. |
| Support (Conversations) | Enabled | An inbound email, inbox, or Slack channel still needs to be connected before tickets can arrive. |

## Signal sources

| Source product | Source type | Action |
|---|---|---|
| `signals_scout` | `cross_source_issue` | On by default; no opt-out row was created. |
| `health_checks` | `health_issue` | Enabled. |
| `error_tracking` | `issue_created` | Enabled. |
| `error_tracking` | `issue_reopened` | Enabled. |
| `error_tracking` | `issue_spiking` | Enabled. |
| `conversations` | `ticket` | Enabled. |
| `gitlab` | `issue` | Enabled as a dormant responder; a GitLab warehouse source was not detected. |
| `session_replay` | retired native source | Deliberately skipped; Replay Vision scanners provide this coverage. |
| `replay_vision` | source row | Deliberately skipped; scanners self-authorize through `emits_signals: true`. |
| `logs` | responder | Deliberately skipped; no v1 native responder exists. |

## Connected tools

| Tool | Outcome |
|---|---|
| GitLab | Selected, but no GitLab warehouse source was detected. The issue responder is enabled and remains dormant until a source is connected. |
| GitHub Issues, Linear, Jira, Sentry, Zendesk, and other catalog tools | Not used in this run. |

## Scout troop

The project has a verified budget of **100 runs/day**, with **0 used** when configured and 100 remaining. The current banner says: “Scouts are in early access. Each project gets up to 100 scout runs a day. Contact team-self-driving@posthog.com if you need more.”

### Enabled (7)

| Scout | Why it is enabled |
|---|---|
| General | Cross-product correlations and surfaces not owned by a specialist. |
| Product analytics | Core flow, lifecycle, and path regressions. |
| Web analytics | Traffic, attribution, landing-page, bounce, and 404 changes. |
| Logs | The Rails application exports PostHog logs. |
| Data warehouse | A production Postgres warehouse source is active. |
| `signals-scout-nudge-outcomes` | Project-specific scheduled encouragement outcomes. |
| `signals-scout-builder-activation` | Project-specific pledge-to-ready-builder activation journey. |

### Disabled (23)

| Scouts | Reason |
|---|---|
| Error tracking | Covered by the enabled native Error Tracking responder. |
| Session replay | Covered by the two Replay Vision scanners below. |
| AI observability, APM, CSP violations, customer analytics, experiments, feature flags, revenue analytics, surveys, web vitals | No evidence that these product surfaces are actively used. Enable later if the product adopts them. |
| Conversations | Support is enabled but has no inbound channel yet; the native ticket responder is already the route for ticket findings. |
| Data pipelines, insight alerts, MCP tool calls, skills store, tasks, workflows | No active corresponding product surface was found. |
| Anomaly detection, observability gaps, PR follow-up, Replay Vision analyst scout | Kept off to keep the troop selective; general, product analytics, and the scanner pipeline cover the relevant current needs. |
| Inbox validation | No resolved Self-driving findings exist yet for it to validate. |

## Custom scouts

| Scout | What it watches | Discriminator | Why it is separate |
|---|---|---|---|
| `signals-scout-nudge-outcomes` | Delivery, engagement, opt-outs, and successful outcomes for scheduled encouragement. | Outcome rate per delivered message and opt-out share versus each metric’s own baseline. | Built-in product analytics can watch broad flow conversion but does not own this message-to-outcome loop. |
| `signals-scout-builder-activation` | Completed onboarding, saved pledge, setup completion, and time-tracking connection. | Entrant volume and the share of pledges reaching downstream milestones within their normal lag. | It catches entry-volume collapse and stalled activation, which a conversion-only watcher can miss. |

The buddy/pomodoro collaboration loop was considered but not proposed: it has start/join events but no sufficiently clear completion or outcome signal for a low-noise recurring scout. Both approved custom scouts are enabled at the default daily cadence. If either becomes noisy, set its config’s `emit` field to `false` in PostHog to leave it running in dry-run mode.

## Replay Vision scanners

A scanner is an LLM that watches individual session recordings on a schedule and pushes qualified findings to the Self-driving inbox. It is the only part of this setup that spends Replay Vision quota. Each scanner finding arrives at half weight, so an inbox report requires corroboration.

| Status | Scanner | Scope | Sampling | Estimated monthly spend |
|---|---|---|---|---|
| Created | [Broken builder activation](https://us.posthog.com/project/647060/replay-vision/01a1176b-2287-7792-85c1-6356161a4a71) | Recordings on `/project`, the completion and ongoing setup destination after a pledge is saved. Watches visibly broken saves, setup, tracker linking, and streak refresh. | 50% | 75 observations / 375 credits |
| Created | [Builder journey frustration](https://us.posthog.com/project/647060/replay-vision/01a1176b-225d-7019-83ae-1c65e1dd1ca3) | Recordings with `$rageclick` only, with no URL filter to keep it distinct from the breakage monitor. Watches visible struggle in onboarding, pledge signing, setup, tracker connection, and buddy pomodoros. | 100% | 1,050 observations / 5,250 credits |

The organization has 2,500 Replay Vision credits remaining for the current period. The approved scanner estimates total 5,625 credits/month; scheduled observations will be constrained by the remaining quota until it resets. Rate early scanner results in the Replay Vision UI with thumbs up/down and a short note to improve their prompts.

## Follow-ups

- [ ] Connect an inbound Support channel (email, inbox, or Slack) so the enabled Conversations ticket responder receives tickets.
- [ ] Add a GitLab warehouse source at [New data warehouse source](https://us.posthog.com/project/647060/pipeline/new/source). The selected GitLab responder is already enabled and will begin once it syncs.
- [ ] Review Replay Vision credit use; the approved scanner configuration is projected above the remaining monthly budget.
- [ ] The MCP connection lacks event/property-definition read scope, so event schema could not be independently queried during setup. The custom scouts are grounded in the repository’s captured-event definitions and validate their event availability at runtime.

## Repository changes

Created:

- `posthog-self-driving-report.md` — this configuration report.

No application source, dependency manifest, or environment file was changed. Existing PostHog initialization already preserves session recording and exception capture.

## What happens next

Fresh scout configurations are picked up by the coordinator within about 30 minutes and draw from the daily run budget. Their findings cluster into reports in the [Self-driving inbox](https://us.posthog.com/project/647060/inbox); immediately actionable reports can start coding tasks.
