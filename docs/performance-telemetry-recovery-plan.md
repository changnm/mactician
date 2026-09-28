# Performance telemetry recovery plan

Date: 2026-09-11. Phase 1 uses launcher 1.2.3 (build 52) and the compatible
API/report deployed first on September 11 (site commit `8ff7667`). The client
is Developer ID signed and Apple notarized. Phases 2–4 depend on new field evidence.

## Baseline

Read-only production checkpoint audit for September 8–11:

- 1,191 launch attempts; 817 have at least one successful frame measurement.
- 4,918 foreground measurement attempts: 4,123 sampled and 795 missing/invalid.
- 20,216 separate background checks. These are checks, not background duration.
- Sampled windows: 3,375 unknown (81.9%), 623 combat, 73 planning, 52 lobby.
- After 20 minutes, 2,138 of 2,698 windows remain unknown (79.2%).
- 268 launch attempts have recognized gameplay; 526 have only unknown samples.
- 471 configurations; 28 reportable groups, including 24 unknown groups.
- Every reportable group has one variant; none supports a matched comparison.
- Only seven attempts qualify for slow-session fraction in any context; no
  context reaches the existing five-attempt display floor.

Attempts are not unique players. Old events contain neither screenshots nor
loss reasons, so their missing context cannot be reconstructed. Recovering
context and accumulating comparable samples are separate problems.

## Phase 1: explain collection quality

Keep the existing scene/stage rules, sampling cadence and game runtime. Attach
one small versioned block of cumulative, allowlisted counters to each existing
checkpoint; do not add screenshot events or fragment frame histograms by reason.
See [the wire contract](telemetry-contract/performance-diagnostics.md).

Distinguish three levels with separate denominators:

1. Measurement outcomes: sampled frames, focus loss, ADB/TimeStats failure,
   missing/changing layers, reset counters, no frames, invalid duration or
   histogram, and segment limit. Missing measurements are not unknown scenes.
2. Each window endpoint: capture/helper/OCR failures; known non-gameplay;
   insufficient evidence; unreadable stage; unrecognized phase; full context.
3. Accepted-window context: stable gameplay/lobby, failed endpoints, changed
   state/round/phase, one unknown endpoint or both unknown endpoints.

One primary reason accounts for every foreground attempt and every accepted
window, using documented precedence. Endpoint counts can be twice the window
count. Preserve partial stage/phase evidence for diagnostics without promoting
it to gameplay.

Bounded context includes requested game language (not verified UI language),
classifier/diagnostic implementation, actual screenshot-size category and match
to the requested profile. Resolution and UI scale already exist in settings.
Timings cover capture, classifier, TimeStats, whole cycle, screenshot-to-window
gaps and actual measurement interval. Count existing backoff decisions. These
are wall times, not CPU usage or exact guest capture timestamps.

This can test whether slow OCR makes context stale before frame collection and
whether backoff disproportionately reduces coverage on slow configurations.
Only counts and enumerations leave the device: no screenshots, OCR strings,
stderr, player names or board contents.

### API compatibility and report

Deploy server first: legacy clients remain valid and absent diagnostics means
not collected, not zero failures. Validate enums, bounded counts, conservation,
immutable attempt identity and monotonic counters. Keep checkpoint deduplication,
ACK handling, the 32 KiB request limit and 16-attempt / 256 KiB client queue.
Separate collector/classifier implementations in performance comparisons.

Show launch-attempt and window funnels, explicitly separating missing, unknown
and background checks. Keep unknown/lobby in collection quality rather than the
main gameplay tables. Label one-variant rows as descriptive, and show short
configuration summaries. Expose diagnostic breakdowns by version, language,
edition, resolution and UI scale while retaining small-group suppression.
The five-attempt display floor does not establish statistical reliability.

Phase completion requires compatible old/new checkpoints, conserved counters,
readable quality/timing breakdowns and an initial collector-overhead check.
A sustained controlled gameplay check remains necessary before changing cadence
or making claims about collection cost in matches.

## Phase 2: rank the causes

Take the first field snapshot 48–72 hours after diagnostic clients start
reporting. This is a review time, not a guarantee of enough data. Check adoption,
absolute sample counts and affected attempts as well as window percentages.
Rank technical failures, correctly recognized non-gameplay, lost context and
real transitions separately; long attempts should not alone set priorities.

| Hypothesis | Evidence | Next action |
| --- | --- | --- |
| Language gaps | Working helper but concentrated losses by requested language | Collect local examples for the largest affected languages |
| Trials-biased cues | Labelled regular-match frames lose stage/phase despite working OCR | Fix regular-match planning, combat and carousel cues |
| Resolution/UI scale | Persistent loss by actual size or scale | Correct reading regions and normalization |
| Stale context | Large capture gaps and mismatched endpoints | Move captures closer to measurements; evaluate deferred OCR |
| Helper/ADB fault | Missing helper, timeout or bounded failure code | Fix packaging, invocation, protocol or timeout |
| Expensive collector | Backoff and sparse useful windows | Reduce unnecessary OCR work after accuracy validation |

The code offers 23 languages while OCR is configured for English/Russian. Old
payloads lack language; Vietnam edition alone does not prove Vietnamese UI.
These are hypotheses about field losses, not measured root-cause shares.

Deliver two or three prioritized causes, affected counts/configurations and a
local reproduction. Do not wait for every rare unknown to be explained.

## Phase 3: fix causes and verify accuracy

Build a labelled local set from owned test sessions: regular matches, Trials,
non-gameplay, transitions, priority languages and resolutions. Hold out examples
from tuning. Compare old/new classifiers on the same inputs, measuring gameplay
versus non-gameplay accuracy, phase, stage and preserved transition rejection.
Unknown reduction through false gameplay is a regression. Define accuracy and
coverage thresholds against the baseline before evaluating the fix.

Preserve partial knowledge without inferring phase from stage. Partial-context
FPS would need a separate explicit category and comparison rules. Version every
classifier change. Keep diagnostic/classifier releases separate from game
runtime optimization, and measure OCR cost even when rendering stays fixed.

A cause is resolved when the old classifier reproduces it, held-out examples
improve without increased false gameplay, and field counters confirm improvement
at acceptable collection cost.

## Phase 4: enable useful comparisons

Choose a few common configurations and a specific gameplay context, such as
combat frame-interval p95, with attempts, sampled duration and coverage beside it.
Broad hardware summaries remain descriptive; retain exact configuration, game
build, applied settings, scene and compatible collector/classifier for matches.

Check windows per finished attempt. Reduce collection cost before considering
higher frequency. Test cadence changes separately for overhead and selection
bias; never vary frequency by FPS or lower eligibility merely to fill tables.
Start with controlled repeatable scenes, then matched field cohorts. Comparing
releases from different days alone does not establish causation. Frames are not
independent observations and attempts are not unique players.

Completion requires at least two comparable variants, a predefined adequate
sample size and stable coverage.

## Verification of phase 1

- Swift full tests: legacy/new wire fixtures, reason precedence, denominators,
  timing buckets, language persistence, opt-out independence, ACK and recovery.
- Helper self-test and one owned gameplay image at four resolutions, stdin
  1080p and invalid PNG. Old/new scene, stage and phase outputs match.
- Four interleaved runs of each helper on the same local frame: identical
  battle/1-1/planning; medians 0.802 s installed versus 0.798 s diagnostic.
  This limited probe is not a gameplay performance measurement.
- Go 1.25.0 unit/HTTP/storage tests, race and vet: enum/privacy validation,
  counters, immutable language/format and prevention of historical relabelling.
  Conservative payload estimate: 24,210 bytes plus 1,024 bytes reserve < 32 KiB.
- Report visually checked on labelled synthetic legacy/new data with two
  variants. Privacy copy updated; site typecheck, lint and build pass.

No automatic user screenshot collection, new universal ML classifier or external
analytics platform is required. Historical unknown causes remain unavailable.

The diagnostic release uses the published 1.2.2 source as its baseline. All four
pinned APKs, game profiles and packaged runtime resources are byte-identical;
only the performance implementation fingerprint changes among app resources.
Unreleased Taiwan, newer game pins and Vulkan-cache changes are excluded.
