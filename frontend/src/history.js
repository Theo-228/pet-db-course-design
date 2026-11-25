// All calendar boundaries match the database's Asia/Shanghai reporting timezone.
export function dateInShanghai(date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}
export function shiftDay(day, amount) {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + amount);
  return date.toISOString().slice(0, 10);
}
export const isAdditive = (code) =>
  ["activity_minutes", "food_intake_g", "water_intake_ml"].includes(code);
export function groupHistory(rows, grouping) {
  const groups = new Map();
  for (const row of rows) {
    const weekday = new Date(`${row.day}T00:00:00Z`).getUTCDay();
    const label =
      grouping === "week" ? shiftDay(row.day, -((weekday + 6) % 7)) : row.day;
    const group = groups.get(label) || {
      label,
      count: 0,
      total: 0,
      minimum: Infinity,
      maximum: -Infinity,
    };
    group.count += Number(row.count);
    group.total += Number(row.total);
    group.minimum = Math.min(group.minimum, Number(row.minimum));
    group.maximum = Math.max(group.maximum, Number(row.maximum));
    group.average = group.total / group.count;
    groups.set(label, group);
  }
  return [...groups.values()].sort((a, b) => a.label.localeCompare(b.label));
}
