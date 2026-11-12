import { describe, expect, test } from "vitest";
import { s3Storage } from "../src/infra/storage.js";

describe("S3 signed URLs", () => {
	const storage = s3Storage({
		endpoint: "https://s3.example.com",
		region: "us-east-1",
		bucket: "teamchat",
		accessKeyId: "AKIAEXAMPLE",
		secretAccessKey: "secret",
		forcePathStyle: true,
	});

	test("uploads are signed for one key, type and size, and expire", async () => {
		const url = new URL(await storage.uploadUrl("attachments/1/2/map.png", "image/png", 1234, 900));
		expect(url.pathname).toBe("/teamchat/attachments/1/2/map.png");
		expect(url.searchParams.get("X-Amz-Expires")).toBe("900");
		expect(url.searchParams.get("X-Amz-Signature")).toMatch(/^[0-9a-f]{64}$/);
		// The client can't send a bigger file or another type than it declared
		expect(url.searchParams.get("X-Amz-SignedHeaders")?.split(";")).toEqual(expect.arrayContaining(["content-length", "content-type", "host"]));
	});

	test("downloads are short-lived and force a download with the original name", async () => {
		const url = new URL(await storage.downloadUrl("attachments/1/2/x.html", "notes <1>.html", 300));
		expect(url.searchParams.get("X-Amz-Expires")).toBe("300");
		expect(url.searchParams.get("response-content-disposition")).toBe("attachment; filename*=UTF-8''notes%20%3C1%3E.html");
	});
});
