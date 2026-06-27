const http = require("http");
const url = process.argv[2] || "http://127.0.0.1:8092/api/health";
console.log("Fetching:", url);
http.get(url, (res) => {
  let data = "";
  res.on("data", (c) => (data += c));
  res.on("end", () => {
    console.log("Status:", res.statusCode);
    console.log("Headers:", JSON.stringify(res.headers));
    console.log("Body:", data);
  });
}).on("error", (e) => {
  console.log("Error:", e.message);
});
