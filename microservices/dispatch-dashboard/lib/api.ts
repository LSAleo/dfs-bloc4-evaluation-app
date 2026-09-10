const API_BASE_URL = process.env.LARAVEL_API_BASE_URL ?? "http://localhost:8000/api/v1";
const API_TOKEN = process.env.LARAVEL_API_TOKEN ?? "change-me";

export async function fetchTickets() {
  const response = await fetch(`${API_BASE_URL}/tickets`, {
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${API_TOKEN}`,
    },
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(`Laravel API error: ${response.status}`);
  }

  const payload = await response.json();
  // L'API Laravel renvoie la collection sous la cle `data` (JsonResource).
  return payload.data ?? [];
}
