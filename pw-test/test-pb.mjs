import { createHash } from "crypto";

const POCKETBASE = "http://127.0.0.1:8090";

function pbId(uuid) {
  return createHash("sha256").update(uuid).digest("hex").substring(0, 15);
}

async function registerUser(nickname) {
  const userId = crypto.randomUUID();
  const pb = pbId(userId);
  const email = `${pb}@stealth.local`;
  const password = `${pb}_test`;

  try {
    const res = await fetch(`${POCKETBASE}/api/collections/users/records`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, passwordConfirm: password }),
    });
    const data = await res.json();
    console.log("User created:", data.id ? "OK" : "FAIL");
    return { userId, pb, email, password };
  } catch (e) {
    console.log("Error:", e.message);
    return null;
  }
}

const user = await registerUser("TestAlice");
console.log("Result:", JSON.stringify(user));
