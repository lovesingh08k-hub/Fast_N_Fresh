// Business-day boundaries in the cafe's timezone (India, UTC+5:30, no DST),
// independent of the server's own timezone. Render runs in UTC, so using the
// server's local midnight would make "today" start at 05:30 IST and push
// late-night sales into the previous day.
const BUSINESS_TIME_ZONE = 'Asia/Kolkata';
const IST_OFFSET_MS = 330 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

// A Date whose UTC fields read as the IST wall-clock time of `date`.
function toIst(date) {
  return new Date(new Date(date).getTime() + IST_OFFSET_MS);
}

function startOfDay(date = new Date()) {
  const ist = toIst(date);
  return new Date(Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth(), ist.getUTCDate()) - IST_OFFSET_MS);
}

function endOfDay(date = new Date()) {
  return new Date(startOfDay(date).getTime() + DAY_MS - 1);
}

function daysAgo(n) {
  return new Date(Date.now() - n * DAY_MS);
}

function startOfWeek(date = new Date()) {
  const day = toIst(date).getUTCDay(); // 0 = Sunday
  return new Date(startOfDay(date).getTime() - day * DAY_MS);
}

function startOfMonth(date = new Date()) {
  const ist = toIst(date);
  return new Date(Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth(), 1) - IST_OFFSET_MS);
}

// YYYY-MM-DD business date in IST.
function businessDate(date = new Date()) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: BUSINESS_TIME_ZONE }).format(new Date(date));
}

module.exports = { BUSINESS_TIME_ZONE, startOfDay, endOfDay, daysAgo, startOfWeek, startOfMonth, businessDate };
