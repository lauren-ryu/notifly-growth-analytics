"""
Notifly Measurement — Privacy-safe lead matching

Purpose
- Standardize two lead-form exports and a separate matching log.
- Match form submissions to captured GA identifiers by time proximity.
- Hash direct identifiers before analysis.
- Remove raw PII from the analytical dataframe.
- Build a privacy-safe Form 1 -> Form 2 journey table in memory.

Public-repository note
- No CSV files are included.
- No Google Drive paths are included.
- No private key map is created.
- No files are written or downloaded by this script.

Local prerequisites:
    pip install pandas numpy

Environment variables:
    NOTIFLY_LEAD_FORM1_CSV
    NOTIFLY_LEAD_FORM2_CSV
    NOTIFLY_MATCH_LOG_CSV
    NOTIFLY_HASH_SALT
"""

import os
import hashlib

import numpy as np
import pandas as pd


# ============================================================
# 0. Configuration
# ============================================================

LEAD1_CSV_PATH = os.getenv("NOTIFLY_LEAD_FORM1_CSV")
LEAD2_CSV_PATH = os.getenv("NOTIFLY_LEAD_FORM2_CSV")
LOG_CSV_PATH = os.getenv("NOTIFLY_MATCH_LOG_CSV")
HASH_SALT = os.getenv("NOTIFLY_HASH_SALT")

required_env = {
    "NOTIFLY_LEAD_FORM1_CSV": LEAD1_CSV_PATH,
    "NOTIFLY_LEAD_FORM2_CSV": LEAD2_CSV_PATH,
    "NOTIFLY_MATCH_LOG_CSV": LOG_CSV_PATH,
    "NOTIFLY_HASH_SALT": HASH_SALT,
}

missing = [name for name, value in required_env.items() if not value]

if missing:
    raise RuntimeError(
        "Missing required environment variables: " + ", ".join(missing)
    )

# Set these locally to the period you want to analyze.
START_DATE_KST = "2026-06-17 00:00:00"
END_DATE_KST = "2026-06-23 23:59:59"

MATCH_TOLERANCE_SECONDS = 300


# ============================================================
# 1. Load local inputs
# ============================================================

lead1_raw = pd.read_csv(LEAD1_CSV_PATH)
lead2_raw = pd.read_csv(LEAD2_CSV_PATH)
log_raw = pd.read_csv(LOG_CSV_PATH)

print("lead1_raw:", lead1_raw.shape)
print("lead2_raw:", lead2_raw.shape)
print("log_raw:", log_raw.shape)


# ============================================================
# 2. Shared helpers
# ============================================================

def clean_colnames(df):
    df = df.copy()
    df.columns = [str(col).strip() for col in df.columns]
    return df


def coalesce_duplicate_columns(df):
    """
    If multiple source columns are renamed to the same target name,
    keep the first non-null value per row.
    """
    df = df.copy()
    df.columns = [str(col).strip() for col in df.columns]

    result = pd.DataFrame(index=df.index)

    for col in pd.unique(df.columns):
        same_cols = df.loc[:, df.columns == col]

        if same_cols.shape[1] == 1:
            result[col] = same_cols.iloc[:, 0]
        else:
            temp = same_cols.replace("", np.nan)
            result[col] = temp.bfill(axis=1).iloc[:, 0]

    return result


def parse_kst_datetime(series):
    """
    Handles:
    - ISO timestamps such as 2026-06-12T02:26:11Z as UTC, then converts to KST
    - Local timestamps without Z as already-KST local time
    """
    values = series.astype(str).str.strip()

    has_z = values.str.contains("T", na=False) & values.str.contains("Z", na=False)

    out = pd.Series(
        pd.NaT,
        index=series.index,
        dtype="datetime64[ns, Asia/Seoul]",
    )

    if has_z.any():
        out.loc[has_z] = (
            pd.to_datetime(values.loc[has_z], errors="coerce", utc=True)
            .dt.tz_convert("Asia/Seoul")
        )

    if (~has_z).any():
        parsed = pd.to_datetime(values.loc[~has_z], errors="coerce")
        out.loc[~has_z] = parsed.dt.tz_localize(
            "Asia/Seoul",
            nonexistent="shift_forward",
            ambiguous="NaT",
        )

    return out


def to_bool_on(value):
    if pd.isna(value):
        return False

    return str(value).strip().lower() in {
        "on",
        "true",
        "yes",
        "y",
        "1",
        "동의",
    }


def normalize_text(value):
    if pd.isna(value):
        return np.nan

    value = str(value).strip()

    if value == "" or value.lower() == "nan":
        return np.nan

    return value


def hash_value(value, salt=HASH_SALT, length=16):
    if pd.isna(value):
        return np.nan

    value = str(value).strip().lower()

    if value == "" or value == "nan":
        return np.nan

    digest = hashlib.sha256(
        (salt + "|" + value).encode("utf-8")
    ).hexdigest()

    return digest[:length]


# ============================================================
# 3. Standardize lead-form tables
# ============================================================

lead1 = clean_colnames(lead1_raw)
lead2 = clean_colnames(lead2_raw)

lead1_rename = {
    "Date": "submitted_at",
    "Email": "email",
    "Agreement": "privacy_consent",
    "기업명": "company_name",
    "담당자이름": "contact_name",
    "담당자명": "contact_name",
    "Marketing": "marketing_consent",
}

lead2_rename = {
    "Date": "submitted_at",
    "Newsletter": "newsletter_consent",
    "담당자명": "contact_name",
    "전화번호": "phone",
    "이메일": "email",
    "Email": "email",
    "문의 목적": "inquiry_purpose",
    "기업명": "company_name",
    "Agreement": "privacy_consent",
    "기타 상세": "inquiry_detail",
}

lead1 = lead1.rename(
    columns={key: value for key, value in lead1_rename.items() if key in lead1.columns}
)
lead2 = lead2.rename(
    columns={key: value for key, value in lead2_rename.items() if key in lead2.columns}
)

lead1 = coalesce_duplicate_columns(lead1)
lead2 = coalesce_duplicate_columns(lead2)

lead1["form_name"] = "lead_form_1"
lead1["expected_form_page"] = "/"
lead1["source_form_file"] = "lead_form_1_sheet"

lead2["form_name"] = "lead_form_2"
lead2["expected_form_page"] = "/welcome"
lead2["source_form_file"] = "lead_form_2_sheet"

leads = pd.concat([lead1, lead2], ignore_index=True)
leads["submitted_at_kst"] = parse_kst_datetime(leads["submitted_at"])


# ============================================================
# 4. Standardize matching log
# ============================================================

logs = clean_colnames(log_raw)
logs = coalesce_duplicate_columns(logs)

required_log_cols = [
    "captured_at",
    "form_name",
    "form_page",
    "ga_client_id",
    "ga_session_id",
    "lead_id",
    "page_location",
    "user_agent",
]

for col in required_log_cols:
    if col not in logs.columns:
        logs[col] = np.nan

logs["captured_at_kst"] = parse_kst_datetime(logs["captured_at"])

logs = logs[
    ~(
        logs["form_name"].isna()
        & logs["ga_client_id"].isna()
        & logs["lead_id"].isna()
    )
].copy()

for col in [
    "form_name",
    "form_page",
    "ga_client_id",
    "ga_session_id",
    "lead_id",
    "page_location",
]:
    logs[col] = logs[col].apply(normalize_text)


# ============================================================
# 5. Restrict to analysis period
# ============================================================

start_kst = pd.Timestamp(START_DATE_KST, tz="Asia/Seoul")
end_kst = pd.Timestamp(END_DATE_KST, tz="Asia/Seoul")

leads_period = leads[
    (leads["submitted_at_kst"] >= start_kst)
    & (leads["submitted_at_kst"] <= end_kst)
].copy()

logs_period = logs[
    (logs["captured_at_kst"] >= start_kst)
    & (logs["captured_at_kst"] <= end_kst)
].copy()

print("leads_period:", leads_period.shape)
print("logs_period:", logs_period.shape)


# ============================================================
# 6. Match lead rows to logging rows by nearest time
# ============================================================

def match_leads_to_logs(leads_df, logs_df, tolerance_seconds=300):
    matched_parts = []

    for form_name in sorted(leads_df["form_name"].dropna().unique()):
        lead_part = leads_df[
            leads_df["form_name"] == form_name
        ].copy()

        log_part = logs_df[
            logs_df["form_name"] == form_name
        ].copy()

        lead_part = (
            lead_part
            .sort_values("submitted_at_kst")
            .reset_index(drop=False)
            .rename(columns={"index": "lead_row_id"})
        )

        log_part = (
            log_part
            .sort_values("captured_at_kst")
            .reset_index(drop=False)
            .rename(columns={"index": "log_row_id"})
        )

        if log_part.empty:
            lead_part["log_row_id"] = np.nan
            lead_part["captured_at_kst"] = pd.NaT
            lead_part["ga_client_id"] = np.nan
            lead_part["ga_session_id"] = np.nan
            lead_part["lead_id"] = np.nan
            lead_part["page_location"] = np.nan
            lead_part["match_time_diff_sec"] = np.nan
            lead_part["match_status"] = "no_log_candidate"

            matched_parts.append(lead_part)
            continue

        merged = pd.merge_asof(
            lead_part,
            log_part[
                [
                    "log_row_id",
                    "captured_at_kst",
                    "form_name",
                    "form_page",
                    "ga_client_id",
                    "ga_session_id",
                    "lead_id",
                    "page_location",
                ]
            ].sort_values("captured_at_kst"),
            left_on="submitted_at_kst",
            right_on="captured_at_kst",
            by="form_name",
            direction="nearest",
            tolerance=pd.Timedelta(seconds=tolerance_seconds),
            suffixes=("", "_log"),
        )

        merged["match_time_diff_sec"] = (
            merged["submitted_at_kst"]
            - merged["captured_at_kst"]
        ).dt.total_seconds().abs()

        merged["match_status"] = np.where(
            merged["captured_at_kst"].notna(),
            "matched_by_time_nearest",
            "no_log_within_tolerance",
        )

        matched_parts.append(merged)

    if not matched_parts:
        return pd.DataFrame()

    return pd.concat(matched_parts, ignore_index=True)


leads_matched = match_leads_to_logs(
    leads_period,
    logs_period,
    tolerance_seconds=MATCH_TOLERANCE_SECONDS,
)

print("\nMatch status:")
print(leads_matched["match_status"].value_counts(dropna=False))


# ============================================================
# 7. Create privacy-safe analytical dataframe
# ============================================================

safe = leads_matched.copy()

for col in [
    "email",
    "phone",
    "contact_name",
    "company_name",
    "inquiry_detail",
    "inquiry_purpose",
]:
    if col in safe.columns:
        safe[col] = safe[col].apply(normalize_text)

safe["email_hash"] = (
    safe["email"].apply(hash_value)
    if "email" in safe.columns
    else np.nan
)

safe["company_hash"] = (
    safe["company_name"].apply(hash_value)
    if "company_name" in safe.columns
    else np.nan
)

safe["phone_hash"] = (
    safe["phone"].apply(hash_value)
    if "phone" in safe.columns
    else np.nan
)

safe["contact_name_hash"] = (
    safe["contact_name"].apply(hash_value)
    if "contact_name" in safe.columns
    else np.nan
)

for col in [
    "privacy_consent",
    "marketing_consent",
    "newsletter_consent",
]:
    safe[col + "_bool"] = (
        safe[col].apply(to_bool_on)
        if col in safe.columns
        else False
    )

if "inquiry_detail" in safe.columns:
    safe["inquiry_detail_length"] = (
        safe["inquiry_detail"]
        .fillna("")
        .astype(str)
        .str.len()
    )
    safe["has_inquiry_detail"] = (
        safe["inquiry_detail_length"] > 0
    )
else:
    safe["inquiry_detail_length"] = 0
    safe["has_inquiry_detail"] = False

if "inquiry_purpose" not in safe.columns:
    safe["inquiry_purpose"] = np.nan


# ============================================================
# 8. Remove raw PII and unnecessary raw fields
# ============================================================

pii_cols = [
    "email",
    "Email",
    "이메일",
    "phone",
    "전화번호",
    "contact_name",
    "담당자명",
    "담당자이름",
    "company_name",
    "기업명",
    "inquiry_detail",
    "user_agent",
]

leads_matched_safe = safe.drop(
    columns=[col for col in pii_cols if col in safe.columns],
    errors="ignore",
)

preferred_cols = [
    "lead_id",
    "form_name",
    "expected_form_page",
    "form_page",
    "submitted_at_kst",
    "captured_at_kst",
    "match_time_diff_sec",
    "match_status",
    "ga_client_id",
    "ga_session_id",
    "page_location",
    "email_hash",
    "company_hash",
    "email_domain",
    "privacy_consent_bool",
    "marketing_consent_bool",
    "newsletter_consent_bool",
    "inquiry_purpose",
    "has_inquiry_detail",
    "inquiry_detail_length",
    "source_form_file",
]

ordered_cols = [
    col
    for col in preferred_cols
    if col in leads_matched_safe.columns
]

other_cols = [
    col
    for col in leads_matched_safe.columns
    if col not in ordered_cols
]

leads_matched_safe = leads_matched_safe[
    ordered_cols + other_cols
]


# ============================================================
# 9. Build privacy-safe Form 1 -> Form 2 journey
# ============================================================

lead_f1 = leads_matched_safe[
    leads_matched_safe["form_name"] == "lead_form_1"
].copy()

lead_f2 = leads_matched_safe[
    leads_matched_safe["form_name"] == "lead_form_2"
].copy()

lead_f1 = lead_f1.sort_values("submitted_at_kst")
lead_f2 = lead_f2.sort_values("submitted_at_kst")

# 1) Primary link: hashed email
journey_email = lead_f1.merge(
    lead_f2,
    on="email_hash",
    how="left",
    suffixes=("_f1", "_f2"),
)

journey_email["valid_f2_after_f1"] = (
    pd.to_datetime(
        journey_email["submitted_at_kst_f2"],
        errors="coerce",
    )
    > pd.to_datetime(
        journey_email["submitted_at_kst_f1"],
        errors="coerce",
    )
)

journey_email = journey_email[
    journey_email["valid_f2_after_f1"].fillna(False)
].copy()

if not journey_email.empty:
    journey_email = (
        journey_email
        .sort_values(
            ["lead_id_f1", "submitted_at_kst_f2"]
        )
        .drop_duplicates(
            subset=["lead_id_f1"],
            keep="first",
        )
    )
    journey_email["match_method"] = "email_hash"


# 2) Secondary link: GA client ID
f1_ga = lead_f1.dropna(
    subset=["ga_client_id"]
).copy()

f2_ga = lead_f2.dropna(
    subset=["ga_client_id"]
).copy()

journey_ga = f1_ga.merge(
    f2_ga,
    on="ga_client_id",
    how="left",
    suffixes=("_f1", "_f2"),
)

journey_ga["valid_f2_after_f1"] = (
    pd.to_datetime(
        journey_ga["submitted_at_kst_f2"],
        errors="coerce",
    )
    > pd.to_datetime(
        journey_ga["submitted_at_kst_f1"],
        errors="coerce",
    )
)

journey_ga = journey_ga[
    journey_ga["valid_f2_after_f1"].fillna(False)
].copy()

if not journey_ga.empty:
    journey_ga = (
        journey_ga
        .sort_values(
            ["lead_id_f1", "submitted_at_kst_f2"]
        )
        .drop_duplicates(
            subset=["lead_id_f1"],
            keep="first",
        )
    )
    journey_ga["match_method"] = "ga_client_id"


# 3) Prefer email-hash match; use GA only when not already matched
if journey_email.empty and journey_ga.empty:
    lead_journey_safe = pd.DataFrame()

else:
    email_matched_ids = (
        set(journey_email["lead_id_f1"].dropna())
        if not journey_email.empty
        else set()
    )

    journey_ga_only = (
        journey_ga[
            ~journey_ga["lead_id_f1"].isin(email_matched_ids)
        ].copy()
        if not journey_ga.empty
        else pd.DataFrame()
    )

    lead_journey_safe = pd.concat(
        [journey_email, journey_ga_only],
        ignore_index=True,
    )

    keep_cols = [
        "lead_id_f1",
        "lead_id_f2",
        "match_method",
        "email_hash",
        "ga_client_id",
        "submitted_at_kst_f1",
        "submitted_at_kst_f2",
        "captured_at_kst_f1",
        "captured_at_kst_f2",
        "form_page_f1",
        "form_page_f2",
        "page_location_f1",
        "page_location_f2",
        "inquiry_purpose_f2",
        "has_inquiry_detail_f2",
        "inquiry_detail_length_f2",
        "company_hash_f1",
        "company_hash_f2",
    ]

    keep_cols = [
        col
        for col in keep_cols
        if col in lead_journey_safe.columns
    ]

    lead_journey_safe = lead_journey_safe[keep_cols]


# ============================================================
# 10. In-memory validation summaries
# ============================================================

summary_by_form = (
    leads_matched_safe
    .groupby("form_name", dropna=False)
    .agg(
        lead_count=("lead_id", "count"),
        matched_count=(
            "match_status",
            lambda values: (
                values == "matched_by_time_nearest"
            ).sum(),
        ),
        unique_ga_clients=("ga_client_id", "nunique"),
        unique_email_hash=("email_hash", "nunique"),
    )
    .reset_index()
)

summary_by_form["match_rate"] = (
    summary_by_form["matched_count"]
    / summary_by_form["lead_count"]
)

print("\nLead matching summary:")
print(summary_by_form)

print("\nPrivacy-safe analytical columns:")
print(leads_matched_safe.columns.tolist())

if not lead_journey_safe.empty:
    print("\nForm 1 -> Form 2 linked journeys:", len(lead_journey_safe))
    print(
        lead_journey_safe["match_method"]
        .value_counts(dropna=False)
    )
else:
    print("\nNo Form 1 -> Form 2 linked journey in the selected period.")

# Nothing is written to disk in this public-repository version.
