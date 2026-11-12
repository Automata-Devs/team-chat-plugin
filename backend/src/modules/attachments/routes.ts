import { and, eq, isNull } from "drizzle-orm";
import { z } from "zod";
import type { Services } from "../../context.js";
import { attachments, messages } from "../../db/schema.js";
import { enqueue } from "../../infra/jobs.js";
import { LIMITS } from "../../http/rateLimit.js";
import { actorOf, type Module } from "../../http/types.js";
import { badRequest, conflict, forbidden, notFound, tooLarge, unavailable } from "../../lib/errors.js";
import { Permission, has } from "../../lib/permissions.js";
import { idParams, parse } from "../../lib/validation.js";
import { channelAccess, requireChannelPermission } from "../access.js";

const UPLOAD_SECONDS = 15 * 60;
const DOWNLOAD_SECONDS = 5 * 60;

/** Keeps a name readable but harmless: no paths, control characters or leading dots. */
export function safeFilename(name: string): string {
	const base = name.normalize("NFC").split(/[\\/]/).pop() ?? "";
	const clean = base
		.replace(/[\u0000-\u001F\u007F"<>|:*?]/g, "")
		.replace(/^\.+/, "")
		.trim()
		.slice(0, 200);
	return clean || "file";
}

const Start = z
	.object({
		filename: z.string().min(1).max(255),
		contentType: z
			.string()
			.max(127)
			.regex(/^[a-z0-9][a-z0-9!#$&^_.+-]*\/[a-z0-9][a-z0-9!#$&^_.+-]*$/i, "Expected a MIME type"),
		size: z.number().int().min(1),
	})
	.strict();

function storageOf(services: Services) {
	if (!services.storage) throw unavailable("File uploads aren't set up on this server");
	return services.storage;
}

const view = (a: typeof attachments.$inferSelect) => ({
	id: a.id,
	channelId: a.channelId,
	messageId: a.messageId,
	filename: a.filename,
	contentType: a.contentType,
	size: a.size,
	status: a.status,
	createdAt: a.createdAt,
});

export const attachmentsModule: Module = (app, services) => {
	const any = { auth: "any" as const };

	/**
	 * Step 1 of an upload: records the file and returns a signed URL. The client
	 * PUTs the bytes straight to storage, then calls /complete.
	 */
	app.post("/channels/:channelId/attachments", { config: { ...any, limit: LIMITS.upload } }, async (request, reply) => {
		const storage = storageOf(services);
		const { channelId } = parse(idParams("channelId"), request.params);
		const body = parse(Start, request.body);
		if (body.size > services.config.MAX_UPLOAD_BYTES) throw tooLarge(`Files can be at most ${services.config.MAX_UPLOAD_BYTES} bytes`);
		const actor = actorOf(request);
		await requireChannelPermission(services.db, channelId, actor.userId, Permission.SEND_MESSAGES | Permission.ATTACH_FILES);

		const id = services.ids.next();
		const filename = safeFilename(body.filename);
		const contentType = body.contentType.toLowerCase();
		const storageKey = `attachments/${channelId}/${id}/${encodeURIComponent(filename)}`;
		const [row] = await services.db
			.insert(attachments)
			.values({ id, channelId, uploaderId: actor.userId, filename, contentType, size: body.size, storageKey })
			.returning();
		const url = await storage.uploadUrl(storageKey, contentType, body.size, UPLOAD_SECONDS);
		return reply.status(201).send({
			attachment: view(row),
			upload: {
				url,
				method: "PUT",
				headers: { "Content-Type": contentType, "Content-Length": String(body.size) },
				expiresIn: UPLOAD_SECONDS,
			},
		});
	});

	/** Step 2: checks the stored object matches what was declared. */
	app.post("/attachments/:attachmentId/complete", { config: any }, async (request) => {
		const storage = storageOf(services);
		const { attachmentId } = parse(idParams("attachmentId"), request.params);
		const actor = actorOf(request);
		const [row] = await services.db.select().from(attachments).where(eq(attachments.id, attachmentId));
		if (!row || row.uploaderId !== actor.userId) throw notFound("Attachment");
		if (row.status === "uploaded") return { attachment: view(row) };
		if (row.status !== "pending") throw conflict("This upload was cancelled");

		const stored = await storage.head(row.storageKey);
		if (!stored) throw badRequest("The file hasn't been uploaded yet");
		if (stored.size !== row.size || (stored.contentType && stored.contentType.toLowerCase() !== row.contentType)) {
			await storage.delete(row.storageKey);
			throw badRequest("The uploaded file doesn't match its declared size or type");
		}
		const [done] = await services.db
			.update(attachments)
			.set({ status: "uploaded", uploadedAt: new Date() })
			.where(and(eq(attachments.id, attachmentId), eq(attachments.status, "pending")))
			.returning();
		return { attachment: view(done ?? row) };
	});

	/** A short-lived download link, for people who can read the message it's on (or its uploader, before sending). */
	app.get("/attachments/:attachmentId", { config: any }, async (request) => {
		const storage = storageOf(services);
		const { attachmentId } = parse(idParams("attachmentId"), request.params);
		const actor = actorOf(request);
		const [row] = await services.db
			.select({ attachment: attachments, messageDeleted: messages.deletedAt })
			.from(attachments)
			.leftJoin(messages, eq(messages.id, attachments.messageId))
			.where(eq(attachments.id, attachmentId));
		if (!row || row.attachment.status !== "uploaded") throw notFound("Attachment");
		const file = row.attachment;

		const access = await channelAccess(services.db, file.channelId, actor.userId).catch(() => null);
		const unsentOwn = file.messageId === null && file.uploaderId === actor.userId;
		const onReadableMessage =
			file.messageId !== null && !row.messageDeleted && !!access && has(access.permissions, Permission.READ_MESSAGE_HISTORY);
		if (!access || !(unsentOwn || onReadableMessage)) throw notFound("Attachment");

		const url = await storage.downloadUrl(file.storageKey, file.filename, DOWNLOAD_SECONDS);
		return { attachment: view(file), url, expiresIn: DOWNLOAD_SECONDS };
	});

	/** Cancels an upload that isn't on a message yet. Files on a message go when the message is deleted. */
	app.delete("/attachments/:attachmentId", { config: any }, async (request, reply) => {
		const { attachmentId } = parse(idParams("attachmentId"), request.params);
		const actor = actorOf(request);
		await services.db.transaction(async (tx) => {
			const [row] = await tx.select().from(attachments).where(eq(attachments.id, attachmentId)).for("update");
			if (!row || row.uploaderId !== actor.userId) throw notFound("Attachment");
			if (row.messageId !== null) throw forbidden("Delete the message to delete its files");
			await tx
				.update(attachments)
				.set({ status: "deleted" })
				.where(and(eq(attachments.id, attachmentId), isNull(attachments.messageId)));
			await enqueue(tx, "attachments.purge", { ids: [attachmentId] });
		});
		return reply.status(204).send();
	});
};
