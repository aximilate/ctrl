export function nowIso() {
  return new Date().toISOString();
}

export function addMinutes(minutes) {
  return new Date(Date.now() + minutes * 60_000).toISOString();
}

export function addDays(days) {
  return new Date(Date.now() + days * 24 * 60 * 60_000).toISOString();
}
