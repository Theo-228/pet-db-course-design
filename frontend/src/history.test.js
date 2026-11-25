import test from "node:test";
import assert from "node:assert/strict";
import {
  dateInShanghai,
  shiftDay,
  groupHistory,
  isAdditive,
} from "./history.js";

test("Shanghai dates and leap day match database calendar boundaries", () => {
  assert.equal(dateInShanghai(new Date("2026-11-24T16:00:00Z")), "2026-11-25");
  assert.equal(shiftDay("2024-03-01", -1), "2024-02-29");
});
test("weekly averages are weighted by record count, with Monday boundaries", () => {
  const rows = [
    { day: "2026-11-22", count: 1, total: 2, minimum: 2, maximum: 2 },
    { day: "2026-11-23", count: 1, total: 4, minimum: 4, maximum: 4 },
    { day: "2026-11-25", count: 3, total: 24, minimum: 7, maximum: 9 },
  ];
  const result = groupHistory(rows, "week");
  assert.equal(result[0].label, "2026-11-16");
  assert.deepEqual(result[1], {
    label: "2026-11-23",
    count: 4,
    total: 28,
    minimum: 4,
    maximum: 9,
    average: 7,
  });
  assert.equal(groupHistory(rows, "day").length, 3); // Missing days stay missing.
  assert.deepEqual(groupHistory([], "day"), []);
});
test("only quantities with cumulative semantics are added in charts", () => {
  assert.equal(isAdditive("weight_kg"), false);
  assert.equal(isAdditive("temperature_c"), false);
  assert.equal(isAdditive("food_intake_g"), true);
  assert.equal(isAdditive("activity_minutes"), true);
});
