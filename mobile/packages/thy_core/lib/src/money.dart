/// Rounds to 2 decimals — same rule as the backend (numeric(14,2) columns), so client-side
/// totals match what the server computes.
double round2(double value) => (value * 100).roundToDouble() / 100;
