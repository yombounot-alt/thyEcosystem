import { existsSync, rmSync } from "fs";
import * as path from "path";
import request from "supertest";
import {
  addMemberSql,
  createHarness,
  loginWithOtp,
  signupAndCreateBusiness,
  uniquePhone,
  type Harness,
} from "../harness.js";

// 1×1 PNG.
const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
);
// Only the signatures matter: the server identifies the type from the first bytes.
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.from("JFIF-test-bytes")]);
const WEBP = Buffer.concat([
  Buffer.from("RIFF"),
  Buffer.from([0x10, 0x00, 0x00, 0x00]),
  Buffer.from("WEBPVP8 "),
]);

describe("Product images (e2e)", () => {
  let h: Harness;
  let server: any;

  const userA = { phone: uniquePhone(), password: "MotDePasse123!", fullName: "Photographe A" };
  const userB = { phone: uniquePhone(), password: "MotDePasse123!", fullName: "Photographe B" };
  const storageRoot = path.resolve(process.env.STORAGE_LOCAL_PATH ?? "./uploads-test");
  const onDisk = (key: string) => existsSync(path.join(storageRoot, key));

  const signupLoginAndCreateBusiness = (user: { phone: string }, businessName: string) =>
    signupAndCreateBusiness(h, user, businessName);

  beforeAll(async () => {
    h = await createHarness();
    server = h.server;
    rmSync(storageRoot, { recursive: true, force: true });
  });

  afterAll(async () => {
    await h.close();
    rmSync(storageRoot, { recursive: true, force: true });
  });

  let a: { accessToken: string };
  let b: { accessToken: string };
  let productId: string;

  const auth = (who: { accessToken: string }) => ({ Authorization: `Bearer ${who.accessToken}` });
  const upload = (who: { accessToken: string }, id: string, file: Buffer, name = "photo.png") =>
    request(server)
      .put(`/api/v1/products/${id}/image`)
      .set(auth(who))
      .attach("file", file, { filename: name, contentType: "application/octet-stream" });

  it("sets up two businesses and a product for A", async () => {
    a = await signupLoginAndCreateBusiness(userA, "Boutique Photo A");
    b = await signupLoginAndCreateBusiness(userB, "Boutique Photo B");

    const res = await request(server)
      .post("/api/v1/products")
      .set(auth(a))
      .send({ name: "Savon de Marseille", salePrice: 2500 })
      .expect(201);
    productId = res.body.id;
    expect(res.body.imageKey).toBeNull();
  });

  it("no longer accepts a client-supplied image URL", async () => {
    await request(server)
      .post("/api/v1/products")
      .set(auth(a))
      .send({ name: "Faux lien", salePrice: 1, imageUrl: "https://evil.example/x.png" })
      .expect(400);
  });

  it("has no photo yet: reading it is a 404", async () => {
    await request(server).get(`/api/v1/products/${productId}/image`).set(auth(a)).expect(404);
  });

  it("stores a PNG and serves the same bytes back with safe headers", async () => {
    const res = await upload(a, productId, PNG).expect(200);
    expect(res.body.imageKey).toMatch(new RegExp(`/products/${productId}/[0-9a-f-]+\\.png$`));
    expect(onDisk(res.body.imageKey)).toBe(true);

    const img = await request(server)
      .get(`/api/v1/products/${productId}/image`)
      .set(auth(a))
      .expect(200);
    expect(img.headers["content-type"]).toBe("image/png");
    expect(img.headers["cache-control"]).toBe("private, max-age=86400");
    expect(img.headers["x-content-type-options"]).toBe("nosniff");
    expect(Buffer.compare(img.body, PNG)).toBe(0);

    const product = await request(server)
      .get(`/api/v1/products/${productId}`)
      .set(auth(a))
      .expect(200);
    expect(product.body.imageKey).toBe(res.body.imageKey);
  });

  it("replacing the photo serves the new one and removes the old file", async () => {
    const before = await request(server)
      .get(`/api/v1/products/${productId}`)
      .set(auth(a))
      .expect(200);
    const oldKey = before.body.imageKey as string;

    const res = await upload(a, productId, JPEG, "nouvelle.jpg").expect(200);
    expect(res.body.imageKey).not.toBe(oldKey);
    expect(res.body.imageKey.endsWith(".jpg")).toBe(true);
    expect(onDisk(oldKey)).toBe(false);
    expect(onDisk(res.body.imageKey)).toBe(true);

    const img = await request(server)
      .get(`/api/v1/products/${productId}/image`)
      .set(auth(a))
      .expect(200);
    expect(img.headers["content-type"]).toBe("image/jpeg");
    expect(Buffer.compare(img.body, JPEG)).toBe(0);
  });

  it("accepts WebP too", async () => {
    const res = await upload(a, productId, WEBP, "x.webp").expect(200);
    expect(res.body.imageKey.endsWith(".webp")).toBe(true);
    const img = await request(server)
      .get(`/api/v1/products/${productId}/image`)
      .set(auth(a))
      .expect(200);
    expect(img.headers["content-type"]).toBe("image/webp");
  });

  it("rejects files that are not JPEG/PNG/WebP, whatever their name or declared type", async () => {
    const before = await request(server)
      .get(`/api/v1/products/${productId}`)
      .set(auth(a))
      .expect(200);

    await request(server)
      .put(`/api/v1/products/${productId}/image`)
      .set(auth(a))
      .attach("file", Buffer.from("<script>alert(1)</script>"), {
        filename: "photo.png",
        contentType: "image/png",
      })
      .expect(400);

    await upload(a, productId, Buffer.from("GIF89a-not-supported"), "anim.gif").expect(400);

    // The previous photo is untouched.
    const after = await request(server)
      .get(`/api/v1/products/${productId}`)
      .set(auth(a))
      .expect(200);
    expect(after.body.imageKey).toBe(before.body.imageKey);
  });

  it("rejects a request without a file", async () => {
    await request(server).put(`/api/v1/products/${productId}/image`).set(auth(a)).expect(400);
  });

  it("rejects a file over 2 MB", async () => {
    const big = Buffer.concat([PNG, Buffer.alloc(2 * 1024 * 1024)]);
    await upload(a, productId, big).expect(413);
  });

  it("requires authentication", async () => {
    await request(server).get(`/api/v1/products/${productId}/image`).expect(401);
    await request(server)
      .put(`/api/v1/products/${productId}/image`)
      .attach("file", PNG, { filename: "x.png" })
      .expect(401);
    await request(server).delete(`/api/v1/products/${productId}/image`).expect(401);
  });

  it("keeps business A's photo invisible and untouchable for business B (404, not 403)", async () => {
    const before = await request(server)
      .get(`/api/v1/products/${productId}`)
      .set(auth(a))
      .expect(200);

    await request(server).get(`/api/v1/products/${productId}/image`).set(auth(b)).expect(404);
    await upload(b, productId, PNG).expect(404);
    await request(server).delete(`/api/v1/products/${productId}/image`).set(auth(b)).expect(404);

    const after = await request(server)
      .get(`/api/v1/products/${productId}`)
      .set(auth(a))
      .expect(200);
    expect(after.body.imageKey).toBe(before.body.imageKey);
    expect(onDisk(after.body.imageKey)).toBe(true);
  });

  it("removes the photo: key cleared, file deleted, reading it is a 404 again", async () => {
    const before = await request(server)
      .get(`/api/v1/products/${productId}`)
      .set(auth(a))
      .expect(200);
    const key = before.body.imageKey as string;

    const res = await request(server)
      .delete(`/api/v1/products/${productId}/image`)
      .set(auth(a))
      .expect(200);
    expect(res.body.imageKey).toBeNull();
    expect(onDisk(key)).toBe(false);
    await request(server).get(`/api/v1/products/${productId}/image`).set(auth(a)).expect(404);

    // Removing a photo that is already gone is harmless.
    await request(server).delete(`/api/v1/products/${productId}/image`).set(auth(a)).expect(200);
  });
});
