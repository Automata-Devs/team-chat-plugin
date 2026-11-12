import { DeleteObjectCommand, HeadObjectCommand, PutObjectCommand, GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

/**
 * Where attachment bytes live. Clients upload and download directly with
 * short-lived signed URLs, so files never pass through the API or Postgres.
 */
export interface ObjectStorage {
	/** A URL the client PUTs the file to. The type and size are part of the signature. */
	uploadUrl(key: string, contentType: string, size: number, expiresInSeconds: number): Promise<string>;
	downloadUrl(key: string, filename: string, expiresInSeconds: number): Promise<string>;
	/** The stored object's size and type, or null when it isn't there. */
	head(key: string): Promise<{ size: number; contentType: string | undefined } | null>;
	delete(key: string): Promise<void>;
}

export class S3Storage implements ObjectStorage {
	constructor(
		private readonly client: S3Client,
		private readonly bucket: string,
	) {}

	uploadUrl(key: string, contentType: string, size: number, expiresIn: number) {
		const command = new PutObjectCommand({
			Bucket: this.bucket,
			Key: key,
			ContentType: contentType,
			ContentLength: size,
		});
		return getSignedUrl(this.client, command, { expiresIn, signableHeaders: new Set(["content-type", "content-length"]) });
	}

	downloadUrl(key: string, filename: string, expiresIn: number) {
		const command = new GetObjectCommand({
			Bucket: this.bucket,
			Key: key,
			ResponseContentDisposition: `attachment; filename*=UTF-8''${encodeURIComponent(filename)}`,
		});
		return getSignedUrl(this.client, command, { expiresIn });
	}

	async head(key: string) {
		try {
			const result = await this.client.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
			return { size: Number(result.ContentLength ?? 0), contentType: result.ContentType };
		} catch (error) {
			const status = (error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode;
			if (status === 404) return null;
			throw error;
		}
	}

	async delete(key: string) {
		await this.client.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
	}
}

export function s3Storage(options: {
	endpoint?: string;
	region: string;
	bucket: string;
	accessKeyId?: string;
	secretAccessKey?: string;
	forcePathStyle: boolean;
}): S3Storage {
	const client = new S3Client({
		endpoint: options.endpoint,
		region: options.region,
		forcePathStyle: options.forcePathStyle,
		credentials:
			options.accessKeyId && options.secretAccessKey
				? { accessKeyId: options.accessKeyId, secretAccessKey: options.secretAccessKey }
				: undefined,
	});
	return new S3Storage(client, options.bucket);
}

/** For tests and local development without S3: "uploads" are recorded with put(). */
export class MemoryStorage implements ObjectStorage {
	readonly objects = new Map<string, { size: number; contentType: string }>();

	async uploadUrl(key: string) {
		return `memory://upload/${encodeURIComponent(key)}`;
	}

	async downloadUrl(key: string) {
		return `memory://download/${encodeURIComponent(key)}`;
	}

	put(key: string, size: number, contentType: string) {
		this.objects.set(key, { size, contentType });
	}

	async head(key: string) {
		return this.objects.get(key) ?? null;
	}

	async delete(key: string) {
		this.objects.delete(key);
	}
}
