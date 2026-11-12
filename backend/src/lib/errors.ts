export class AppError extends Error {
	constructor(
		readonly status: number,
		readonly code: string,
		message: string,
		readonly details?: unknown,
	) {
		super(message);
	}
}

export const badRequest = (message: string, details?: unknown) => new AppError(400, "bad_request", message, details);
export const unauthorized = (message = "Sign in first") => new AppError(401, "unauthorized", message);
export const forbidden = (message = "You don't have permission to do that") => new AppError(403, "forbidden", message);
/** Also used when something exists but the caller may not see it, so its existence doesn't leak. */
export const notFound = (what = "Resource") => new AppError(404, "not_found", `${what} not found`);
export const conflict = (message: string) => new AppError(409, "conflict", message);
export const tooLarge = (message: string) => new AppError(413, "too_large", message);
export const unavailable = (message = "Service unavailable, try again shortly") =>
	new AppError(503, "unavailable", message);
