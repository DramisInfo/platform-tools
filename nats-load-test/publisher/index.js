import Fastify from "fastify";
import { connect, StringCodec } from "nats";

const NATS_URL       = process.env.NATS_URL || "nats://nats.cace-1-dev.dramisinfo.com:4222";
const DEFAULT_SUBJECT = process.env.SUBJECT  || "loadtest.cross";
const PORT           = parseInt(process.env.PORT || "3000");

const sc = StringCodec();
let nc;

// ── Connect to NATS ─────────────────────────────────────────────────────────
async function connectNats() {
  console.log(`[publisher] Connecting to NATS at ${NATS_URL} ...`);
  nc = await connect({ servers: NATS_URL });
  console.log(`[publisher] NATS connected (${NATS_URL})`);

  nc.closed().then(() => {
    console.error("[publisher] NATS connection closed unexpectedly");
    process.exit(1);
  });
}

// ── Fastify app ──────────────────────────────────────────────────────────────
const app = Fastify({ logger: false });

/**
 * POST /publish
 * Body (JSON, optional):
 *   { "subject": "loadtest.cross", "payload": "any string" }
 * Both fields fall back to env defaults when omitted.
 */
app.post("/publish", async (req, reply) => {
  const subject = req.body?.subject || DEFAULT_SUBJECT;
  const userPayload = req.body?.payload ?? null;

  const message = JSON.stringify({
    sentAt:  Date.now(),
    subject,
    payload: userPayload,
  });

  try {
    nc.publish(subject, sc.encode(message));
    return reply.code(200).send({ ok: true, subject });
  } catch (err) {
    req.log.error(err);
    return reply.code(500).send({ ok: false, error: String(err) });
  }
});

/** GET /health — used by Docker / k6 wait loop */
app.get("/health", async (_req, reply) => {
  const natsOk = nc && !nc.isClosed();
  return reply
    .code(natsOk ? 200 : 503)
    .send({ ok: natsOk, nats: NATS_URL });
});

// ── Startup ──────────────────────────────────────────────────────────────────
async function main() {
  await connectNats();
  await app.listen({ port: PORT, host: "0.0.0.0" });
  console.log(`[publisher] HTTP listening on :${PORT}`);
}

const shutdown = async (signal) => {
  console.log(`[publisher] ${signal} — shutting down`);
  await app.close();
  await nc?.drain();
  process.exit(0);
};
process.on("SIGINT",  () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

main().catch((err) => {
  console.error("[publisher] Fatal:", err);
  process.exit(1);
});
