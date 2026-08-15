/**
 * Notifly Measurement — Apps Script matching-log receiver
 *
 * Receives the Framer matching payload and stores it in a Google Sheet
 * for later lead-to-session matching.
 */

function doPost(e) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName("logs");

  if (!sheet) {
    sheet = ss.insertSheet("logs");
    sheet.appendRow([
      "captured_at",
      "form_name",
      "form_page",
      "ga_client_id",
      "ga_session_id",
      "lead_id",
      "page_location"
    ]);
  }

  let data = {};

  try {
    data = JSON.parse(e.postData.contents || "{}");
  } catch (error) {
    data = {};
  }

  sheet.appendRow([
    data.captured_at || new Date().toISOString(),
    data.form_name || "",
    data.form_page || "",
    data.ga_client_id || "",
    data.ga_session_id || "",
    data.lead_id || "",
    data.page_location || ""
  ]);

  return ContentService
    .createTextOutput(JSON.stringify({ status: "ok" }))
    .setMimeType(ContentService.MimeType.JSON);
}
