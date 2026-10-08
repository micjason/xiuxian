import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  vus: 20,
  duration: "30s",
};

const base = __ENV.API_BASE_URL || "http://127.0.0.1:8080";

export default function () {
  const health = http.get(`${base}/healthz`);
  check(health, { "health ok": (response) => response.status === 200 });
  sleep(1);
}
