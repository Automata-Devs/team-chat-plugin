import { z } from "zod";

const bool = z
	.enum(["true", "false", "1", "0"])
	.transform((value) => value === "true" || value === "1");

const schema = z.object({
	NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
	HOST: z.string().default("0.0.0.0"),
	PORT: z.coerce.number().int().min(0).max(65535).default(8080),
	LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
	/** Public base URL of this API, used for OAuth redirects. */
	PUBLIC_URL: z.string().url().default("http://localhost:8080"),
	/** Trust X-Forwarded-For from a reverse proxy. */
	TRUST_PROXY: bool.default("false"),

	DATABASE_URL: z.string().min(1),
	DATABASE_POOL_MAX: z.coerce.number().int().min(1).max(200).default(20),
	DATABASE_STATEMENT_TIMEOUT_MS: z.coerce.number().int().min(100).default(10_000),

	/** Without it, caching, rate limits and login flows stay inside this one process. */
	REDIS_URL: z.string().optional(),

	/** 0-1023, unique per running instance. Leave empty to lease one from Redis. */
	WORKER_ID: z.coerce.number().int().min(0).max(1023).optional(),

	/** 32 bytes, base64. Encrypts bot signing secrets at rest. */
	ENCRYPTION_KEY: z
		.string()
		.refine((value) => Buffer.from(value, "base64").length === 32, "ENCRYPTION_KEY must be 32 bytes, base64"),

	SESSION_TTL_DAYS: z.coerce.number().int().min(1).max(365).default(30),
	ALLOW_PASSWORD_SIGNUP: bool.default("true"),

	ROBLOX_OAUTH_CLIENT_ID: z.string().optional(),
	ROBLOX_OAUTH_CLIENT_SECRET: z.string().optional(),
	ROBLOX_OAUTH_BASE_URL: z.string().url().default("https://apis.roblox.com/oauth"),

	S3_ENDPOINT: z.string().url().optional(),
	S3_REGION: z.string().default("us-east-1"),
	S3_BUCKET: z.string().optional(),
	S3_ACCESS_KEY_ID: z.string().optional(),
	S3_SECRET_ACCESS_KEY: z.string().optional(),
	S3_FORCE_PATH_STYLE: bool.default("false"),
	MAX_UPLOAD_BYTES: z.coerce.number().int().min(1).default(25 * 1024 * 1024),

	/** Lets bot event URLs use http:// and private addresses. Development only. */
	ALLOW_INSECURE_BOT_URLS: bool.default("false"),

	RUN_JOBS: bool.default("true"),
	/** Multiplies every rate limit (tests and load tests raise it). */
	RATE_LIMIT_SCALE: z.coerce.number().min(0.1).max(10_000).default(1),
});

export type Config = z.infer<typeof schema>;

export function loadConfig(env: Record<string, string | undefined> = process.env): Config {
	// "S3_ENDPOINT=" in a .env file means "not set", not "an empty URL"
	const given = Object.fromEntries(Object.entries(env).filter(([, value]) => value !== undefined && value.trim() !== ""));
	// On Render the service's own address is known: the Roblox sign-in redirect needs it
	if (!given.PUBLIC_URL && given.RENDER_EXTERNAL_URL) given.PUBLIC_URL = given.RENDER_EXTERNAL_URL;
	const parsed = schema.safeParse(given);
	if (!parsed.success) {
		const problems = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`);
		throw new Error(`Invalid configuration:\n  ${problems.join("\n  ")}`);
	}
	return parsed.data;
}
