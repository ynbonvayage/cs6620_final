function formatScanSummary(high, medium, low) {
  const total = high + medium + low;
  return { high, medium, low, total };
}
module.exports = { formatScanSummary };
