import { z } from "zod";
import { badRequest } from "./errors.js";

export function parse<T extends z.ZodTypeAny>(schema: T, data: unknown): z.infer<T> {
	const result = schema.safeParse(data);
	if (!result.success) {
		throw badRequest(
			"Invalid request",
			result.error.issues.map((issue) => ({ path: issue.path.join("."), message: issue.message })),
		);
	}
	return result.data;
}

/** A snowflake sent as a decimal string (JSON numbers can't hold 64 bits). */
export const snowflake = z
	.string()
	.regex(/^[0-9]{1,19}$/, "Expected an id")
	.transform((value) => BigInt(value))
	.refine((value) => value > 0n && value < 1n << 63n, "Expected an id");

export const idParams = <K extends string>(...keys: K[]) =>
	z.object(Object.fromEntries(keys.map((key) => [key, snowflake])) as Record<K, typeof snowflake>);

/** Trims, normalises to NFC and drops control characters (newlines and tabs are kept). */
export const text = (max: number, min = 0) =>
	z
		.string()
		.transform((value) => value.normalize("NFC").replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "").trim())
		.pipe(z.string().min(min).max(max));

/** One-line names: no line breaks either. */
export const name = (max: number, min = 1) =>
	z
		.string()
		.transform((value) => value.normalize("NFC").replace(/[\u0000-\u001F\u007F]/g, "").replace(/\s+/g, " ").trim())
		.pipe(z.string().min(min).max(max));

export const username = z
	.string()
	.transform((value) => value.trim())
	.pipe(
		z
			.string()
			.min(3)
			.max(32)
			.regex(/^[A-Za-z0-9_.]+$/, "Letters, digits, _ and . only"),
	);

export const httpsUrl = z
	.string()
	.max(2048)
	.url()
	.refine((value) => value.startsWith("https://") || value.startsWith("rbxassetid://"), "Must be an https:// URL");

export const limit = (fallback: number, max: number) => z.coerce.number().int().min(1).max(max).default(fallback);

/** "123" or 123 to bigint permissions. */
export const permissionBits = z
	.union([z.string().regex(/^[0-9]{1,19}$/), z.number().int().nonnegative()])
	.transform((value) => BigInt(value));
