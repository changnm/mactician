# Performance loss diagnostics v1

Optional `performance.diagnostics` is present on newly instrumented attempts and
absent on legacy attempts. It is standard performance collection, independent of
the optional Extended Diagnostics choice. No new event type or histogram segment
dimension is introduced. The canonical example is
`game-session-performance-diagnostics-v2.json`.

`version` is `1`; `implementation` is `screen-bracket-diagnostics-v1`; `language`
is a supported requested game-language code or `unknown`. These fields are fixed
for the attempt. The algorithm identifier remains `screen-bracket-v1`: diagnostic
metadata does not change scene classification. Different implementations remain
separate in performance comparisons.

All maps contain only allowlisted keys. Missing keys mean zero within a present
diagnostics object. An absent object means **not collected**. Counts are cumulative,
nonnegative and cannot decrease or be relabelled in subsequent revisions.

| Map | Denominator / invariant |
| --- | --- |
| `measurements` | Exactly one outcome per foreground measurement attempt; sum equals `windows_attempted`; `sampled` equals attempted minus missing |
| `contexts` | Exactly one outcome per accepted histogram window; sum equals `measurements.sampled`; gameplay/lobby match segment windows |
| `endpoints` | One outcome per attempted boundary classification, up to two per foreground measurement attempt |
| `states` | One coarse screen state per successfully decoded classifier response; sum equals non-error endpoint outcomes |
| `signals` | Overlapping `stage_read`, `phase_read`, `dimensions_match`, `dimensions_mismatch` counts; stage/phase bounded by decoded endpoints; matching and mismatching dimensions sum to dimension observations |
| `dimensions` | Supported size labels (`1920x1080`, `2560x1440`, `2880x1620`, `3200x1800`, `3840x2160`) or `other`, never arbitrary strings |

Measurement reasons: `sampled`, `lost_focus`, `timestats_failed`, `layer_not_found`,
`layer_changed`, `counter_reset`, `no_frames`, `invalid_duration`,
`invalid_histogram`, `segment_limit`, `measurement_failed`.

Endpoint reasons: `gameplay`, `lobby`, `non_gameplay`, `stage_unreadable`,
`phase_unrecognized`, `insufficient_evidence`, `helper_missing`, `capture_failed`,
`helper_timeout`, `helper_failed`, `unsupported_dimensions`, `invalid_image`,
`ocr_failed`, `invalid_response`. A known screen can still be rejected by the
unchanged gameplay classifier: for example patching or a reward-choice overlay.

Context reason precedence: stable gameplay/lobby; endpoint failure; state change;
round change; phase change; stable recognized non-gameplay; one unknown endpoint;
both unknown endpoints. A round change stays unknown even within the same coarse
stage band. Raw stage/phase values only pass between local processes; the uploaded
block contains counts and coarse states, not stage strings or OCR evidence.

`timings` holds noncumulative histograms for `screencap`, `classifier`, `timestats`,
`before_gap`, `after_gap`, `cycle`, `interval`. Upper bounds in milliseconds are
`[100, 500, 1000, 2500, 5000, 10000, 30000, 60000, 180000, 600000, overflow]`.
The API limits observations by the maximum calls per check: two captures and
classifications, four TimeStats calls, one of each gap, one foreground interval,
one cycle (including background checks). These are wall times, not CPU load.

Before gap starts at screenshot acquisition invocation and ends after the frame
baseline. After gap runs from the final frame snapshot to screenshot invocation.
Neither is an exact guest capture timestamp. Interval is between foreground
measurement starts and may span a period in background. `backoff_windows` counts
foreground checks whose overhead extends the existing randomized sampling delay.

Deploy the compatible API before the client. Request size remains 32 KiB; the
latest-checkpoint queue remains at most 16 attempts / 256 KiB. Diagnostic counters
do not participate in frame percentile calculations. Suppression of small report
groups and the distinction between display floors and useful sample sizes remain.
