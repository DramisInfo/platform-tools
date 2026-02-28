import { connect, StringCodec } from "nats";

const NATS_URL = process.env.NATS_URL || "nats://nats.cace-2-dev.dramisinfo.com:4222";
const SUBJECT   = process.env.SUBJECT   || "loadtest.cross";
const QUEUE     = process.env.NATS_QUEUE || "";   // set to enable competing-consumers mode
const STATS_INTERVAL_MS = parseInt(process.env.STATS_INTERVAL_MS || "2000");

const sc = StringCodec();

let totalReceived  = 0;
let windowReceived = 0;
let latencies      = [];   // rolling window (ms)
let lastStatsAt    = Date.now();

function printStats(force = false) {
  const now   = Date.now();
  const elapsedS = (now - lastStatsAt) / 1000;

  if (!force && elapsedS < STATS_INTERVAL_MS / 1000) return;

  const rps = (windowReceived / elapsedS).toFixed(1);
  const avgLat = latencies.length
    ? (latencies.reduce((a, b) => a + b, 0) / latencies.length).toFixed(2)
    : "N/A";
  const maxLat = latencies.length ? Math.max(...latencies).toFixed(2) : "N/A";
  const minLat = latencies.length ? Math.min(...latencies).toFixed(2) : "N/A";

  console.log(
    `[SUBSCRIBER] total=${totalReceived}  window_rps=${rps}/s` +
    `  lat_avg=${avgLat}ms  lat_min=${minLat}ms  lat_max=${maxLat}ms` +
    `  (${SUBJECT} @ ${NATS_URL})`
  );

  windowReceived = 0;
  latencies      = [];
  lastStatsAt    = now;
}

async function main() {
  console.log(`[SUBSCRIBER] Connecting to ${NATS_URL} ...`);
  const nc = await connect({ servers: NATS_URL });
  console.log(`[SUBSCRIBER] Connected. Subscribing to '${SUBJECT}'${QUEUE ? ` (queue group: ${QUEUE})` : ""} ...`);

  const subOpts = QUEUE ? { queue: QUEUE } : {};
  const sub = nc.subscribe(SUBJECT, subOpts);

  // Periodic stats
  const statsTimer = setInterval(printStats, STATS_INTERVAL_MS);

  // Graceful shutdown
  const shutdown = async (signal) => {
    console.log(`\n[SUBSCRIBER] ${signal} received — shutting down`);
    clearInterval(statsTimer);
    printStats(true);
    sub.unsubscribe();
    await nc.drain();
    process.exit(0);
  };
  process.on("SIGINT",  () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));

  for await (const msg of sub) {
    const receivedAt = Date.now();
    totalReceived++;
    windowReceived++;

    try {
      // Publisher embeds: { sentAt: <epoch ms>, payload: "..." }
      const data = JSON.parse(sc.decode(msg.data));
      if (data.sentAt) {
        latencies.push(receivedAt - data.sentAt);
      }
    } catch {
      // message is not JSON — that's fine, just count it
    }
  }
}

main().catch((err) => {
  console.error("[SUBSCRIBER] Fatal:", err);
  process.exit(1);
});
