/**
 * k6 NATS Cross-Cluster Load Test
 *
 * k6 → HTTP POST → publisher (REST API, cace-1-dev) → NATS → subscriber (cace-2-dev)
 *
 * Env vars (set in docker-compose or on the CLI with -e):
 *   PUBLISHER_URL  : base URL of the publisher service  (default: http://publisher:3000)
 *   SUBJECT        : NATS subject                        (default: loadtest.cross)
 *   VUS            : concurrent virtual users            (default: 10)
 *   DURATION       : test duration                       (default: 60s)
 */

import http             from "k6/http";
import { check, sleep } from "k6";
import { Counter, Trend } from "k6/metrics";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const PUBLISHER_URL    = __ENV.PUBLISHER_URL || "http://publisher:3000";
const SUBJECT          = __ENV.SUBJECT       || "loadtest.cross";
const VUS              = parseInt(__ENV.VUS      || "10");
const DURATION         = __ENV.DURATION          || "60s";

const PUBLISH_ENDPOINT = `${PUBLISHER_URL}/publish`;

// Custom metrics
const publishedMessages = new Counter("nats_published_messages");
const publishErrors     = new Counter("nats_publish_errors");
const publishLatency    = new Trend("http_publish_duration_ms", true);

// ---------------------------------------------------------------------------
// k6 options
// ---------------------------------------------------------------------------
export const options = {
  scenarios: {
    nats_load: {
      executor: "constant-vus",
      vus:      VUS,
      duration: DURATION,
    },
  },
  thresholds: {
    // HTTP error rate under 1 %
    http_req_failed:          ["rate<0.01"],
    // p99 round-trip to publisher under 500 ms
    http_publish_duration_ms: ["p(99)<500"],
    // At most 5 logical publish errors
    nats_publish_errors:      ["count<5"],
  },
};

// ---------------------------------------------------------------------------
// Setup — wait for the publisher to be healthy before VUs start
// ---------------------------------------------------------------------------
export function setup() {
  const maxRetries = 20;
  for (let i = 0; i < maxRetries; i++) {
    const res = http.get(`${PUBLISHER_URL}/health`);
    if (res.status === 200) {
      console.log(`[k6] Publisher ready at ${PUBLISHER_URL}`);
      return;
    }
    console.log(`[k6] Waiting for publisher (attempt ${i + 1}/${maxRetries}) ...`);
    sleep(1);
  }
  console.error("[k6] Publisher did not become ready — VUs will likely fail");
}

// ---------------------------------------------------------------------------
// Default function — one iteration per VU
// ---------------------------------------------------------------------------
export default function () {
  const body = JSON.stringify({ subject: SUBJECT });
  const params = {
    headers: { "Content-Type": "application/json" },
    tags:    { name: "publish" },
  };

  const start   = Date.now();
  const res     = http.post(PUBLISH_ENDPOINT, body, params);
  const elapsed = Date.now() - start;

  publishLatency.add(elapsed);

  const ok = check(res, {
    "status 200":   (r) => r.status === 200,
    "ok: true":     (r) => {
      try { return r.json("ok") === true; } catch { return false; }
    },
    "under 500ms":  () => elapsed < 500,
  });

  if (ok) {
    publishedMessages.add(1);
  } else {
    publishErrors.add(1);
    console.error(
      `[k6] publish failed — status=${res.status} body=${res.body} vu=${__VU} iter=${__ITER}`
    );
  }
}
