"""Notifly session clustering with lead labels.

Loads session-level GA4 data and privacy-safe lead data, links leads to sessions,
clusters sessions using behavioral, acquisition, device, and lead-submission
features, and uses privacy-safe lead attributes for cluster interpretation.
"""

from pathlib import Path
import warnings

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA
from sklearn.metrics import silhouette_score
from sklearn.preprocessing import StandardScaler

warnings.filterwarnings("ignore")


# ---------------------------------------------------------------------
# Input files
# ---------------------------------------------------------------------

SESSION_FILE = Path("10_session_cluster_input.csv")
LEAD_FILE = Path("leads_matched_safe.csv")

MATCH_TOLERANCE_SEC = 300
FORCE_K = 3
RANDOM_STATE = 42


session_dtypes = {
    "user_pseudo_id": str,
    "ga_session_id": str,
    "ga_session_number": str,
    "session_key": str,
    "source": str,
    "medium": str,
    "campaign": str,
    "content": str,
    "traffic_group": str,
}

lead_dtypes = {
    "ga_client_id": str,
    "ga_session_id": str,
    "lead_id": str,
    "lead_row_id": str,
    "form_name": str,
    "email_hash": str,
    "company_hash": str,
    "phone_hash": str,
    "contact_name_hash": str,
}


# ---------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------

sessions = pd.read_csv(SESSION_FILE, dtype=session_dtypes)
leads = pd.read_csv(LEAD_FILE, dtype=lead_dtypes)


# ---------------------------------------------------------------------
# Time and ID normalization
# ---------------------------------------------------------------------

def parse_session_time(series):
    return pd.to_datetime(series, errors="coerce")


def parse_lead_time(series):
    parsed = pd.to_datetime(series, errors="coerce", utc=True)
    return parsed.dt.tz_convert("Asia/Seoul").dt.tz_localize(None)


for col in [
    "session_start_kst",
    "session_end_kst",
    "lead1_submit_at_kst",
    "lead2_submit_at_kst",
]:
    if col in sessions.columns:
        sessions[col] = parse_session_time(sessions[col])


for col in [
    "captured_at_kst",
    "submitted_at_kst",
    "submitted_at",
]:
    if col in leads.columns:
        leads[col + "_parsed"] = parse_lead_time(leads[col])


def choose_lead_time(row):
    for col in [
        "captured_at_kst_parsed",
        "submitted_at_kst_parsed",
        "submitted_at_parsed",
    ]:
        if col in row.index and pd.notna(row[col]):
            return row[col]
    return pd.NaT


leads["lead_time_kst"] = leads.apply(choose_lead_time, axis=1)


def normalize_id(value):
    if pd.isna(value):
        return np.nan

    value = str(value).strip().replace(" ", "")

    if value.endswith(".0"):
        value = value[:-2]

    return value if value else np.nan


def client_prefix(value):
    value = normalize_id(value)

    if pd.isna(value):
        return np.nan

    return value.split(".")[0] if "." in value else value


sessions["user_pseudo_id_str"] = sessions["user_pseudo_id"].apply(normalize_id)
sessions["client_prefix"] = sessions["user_pseudo_id"].apply(client_prefix)

leads["ga_client_id_str"] = leads["ga_client_id"].apply(normalize_id)
leads["client_prefix"] = leads["ga_client_id"].apply(client_prefix)

if "ga_session_id" in sessions.columns:
    sessions["ga_session_id_str"] = sessions["ga_session_id"].apply(normalize_id)

if "ga_session_id" in leads.columns:
    leads["ga_session_id_str"] = leads["ga_session_id"].apply(normalize_id)


# ---------------------------------------------------------------------
# Lead-to-session matching
# ---------------------------------------------------------------------

def get_submit_col(form_name):
    if form_name == "lead_form_1":
        return "lead1_submit_at_kst"

    if form_name == "lead_form_2":
        return "lead2_submit_at_kst"

    return None


def time_diff_seconds(a, b):
    if pd.isna(a) or pd.isna(b):
        return np.nan

    return abs((a - b).total_seconds())


def match_one_lead_to_session(
    lead_row,
    sessions_df,
    tolerance_sec=MATCH_TOLERANCE_SEC,
):
    form_name = lead_row.get("form_name")
    submit_col = get_submit_col(form_name)
    lead_time = lead_row.get("lead_time_kst")

    lead_client = lead_row.get("ga_client_id_str")
    lead_prefix = lead_row.get("client_prefix")
    lead_session_id = lead_row.get("ga_session_id_str")

    empty_result = {
        "matched_session_key": np.nan,
        "matched_user_pseudo_id": np.nan,
        "matched_ga_session_id": np.nan,
        "matched_time_diff_sec": np.nan,
        "session_match_method": "unmatched",
    }

    if (
        submit_col is None
        or submit_col not in sessions_df.columns
        or pd.isna(lead_time)
    ):
        return pd.Series(empty_result)

    candidate = sessions_df.copy()

    candidate["submit_time_diff_sec"] = candidate[submit_col].apply(
        lambda value: time_diff_seconds(value, lead_time)
    )

    def session_window_diff(row):
        start = row.get("session_start_kst")
        end = row.get("session_end_kst")

        if pd.isna(start) or pd.isna(end):
            return np.nan

        if start <= lead_time <= end:
            return 0.0

        return min(
            abs((lead_time - start).total_seconds()),
            abs((lead_time - end).total_seconds()),
        )

    candidate["session_window_diff_sec"] = candidate.apply(
        session_window_diff,
        axis=1,
    )

    if (
        pd.notna(lead_client)
        and pd.notna(lead_session_id)
        and "ga_session_id_str" in candidate.columns
    ):
        found = candidate[
            (candidate["user_pseudo_id_str"] == lead_client)
            & (candidate["ga_session_id_str"] == lead_session_id)
        ].copy()

        if not found.empty:
            found["best_diff_sec"] = found[
                ["submit_time_diff_sec", "session_window_diff_sec"]
            ].min(axis=1)

            best = found.sort_values("best_diff_sec").iloc[0]

            return pd.Series(
                {
                    "matched_session_key": best["session_key"],
                    "matched_user_pseudo_id": best["user_pseudo_id"],
                    "matched_ga_session_id": best.get("ga_session_id", np.nan),
                    "matched_time_diff_sec": best["best_diff_sec"],
                    "session_match_method": "exact_client_and_session_id",
                }
            )

    if pd.notna(lead_client):
        found = candidate[
            (candidate["user_pseudo_id_str"] == lead_client)
            & (candidate["submit_time_diff_sec"] <= tolerance_sec)
        ].copy()

        if not found.empty:
            best = found.sort_values("submit_time_diff_sec").iloc[0]

            return pd.Series(
                {
                    "matched_session_key": best["session_key"],
                    "matched_user_pseudo_id": best["user_pseudo_id"],
                    "matched_ga_session_id": best.get("ga_session_id", np.nan),
                    "matched_time_diff_sec": best["submit_time_diff_sec"],
                    "session_match_method": "exact_client_id_submit_time",
                }
            )

        found = candidate[
            (candidate["user_pseudo_id_str"] == lead_client)
            & (candidate["session_window_diff_sec"] <= tolerance_sec)
        ].copy()

        if not found.empty:
            best = found.sort_values("session_window_diff_sec").iloc[0]

            return pd.Series(
                {
                    "matched_session_key": best["session_key"],
                    "matched_user_pseudo_id": best["user_pseudo_id"],
                    "matched_ga_session_id": best.get("ga_session_id", np.nan),
                    "matched_time_diff_sec": best["session_window_diff_sec"],
                    "session_match_method": "exact_client_id_session_window",
                }
            )

    if pd.notna(lead_prefix) and len(str(lead_prefix)) >= 6:
        found = candidate[
            (candidate["client_prefix"] == lead_prefix)
            & (candidate["submit_time_diff_sec"] <= tolerance_sec)
        ].copy()

        if not found.empty:
            best = found.sort_values("submit_time_diff_sec").iloc[0]

            return pd.Series(
                {
                    "matched_session_key": best["session_key"],
                    "matched_user_pseudo_id": best["user_pseudo_id"],
                    "matched_ga_session_id": best.get("ga_session_id", np.nan),
                    "matched_time_diff_sec": best["submit_time_diff_sec"],
                    "session_match_method": "prefix_client_id_submit_time",
                }
            )

        found = candidate[
            (candidate["client_prefix"] == lead_prefix)
            & (candidate["session_window_diff_sec"] <= tolerance_sec)
        ].copy()

        if not found.empty:
            best = found.sort_values("session_window_diff_sec").iloc[0]

            return pd.Series(
                {
                    "matched_session_key": best["session_key"],
                    "matched_user_pseudo_id": best["user_pseudo_id"],
                    "matched_ga_session_id": best.get("ga_session_id", np.nan),
                    "matched_time_diff_sec": best["session_window_diff_sec"],
                    "session_match_method": "prefix_client_id_session_window",
                }
            )

    return pd.Series(empty_result)


match_result = leads.apply(
    lambda row: match_one_lead_to_session(
        row,
        sessions,
        MATCH_TOLERANCE_SEC,
    ),
    axis=1,
)

leads_session_matched = pd.concat(
    [leads, match_result],
    axis=1,
)

if "lead_row_id" not in leads_session_matched.columns:
    leads_session_matched["lead_row_id"] = range(
        len(leads_session_matched)
    )

matched_leads = leads_session_matched.dropna(
    subset=["matched_session_key"]
).copy()


# ---------------------------------------------------------------------
# Privacy-safe lead attributes by session
# ---------------------------------------------------------------------

if matched_leads.empty:
    lead_labels = pd.DataFrame(
        columns=[
            "session_key",
            "matched_lead_count",
            "matched_form1_lead_count",
            "matched_form2_lead_count",
            "has_matched_form1_lead",
            "has_matched_form2_lead",
        ]
    )
else:
    lead_labels = (
        matched_leads
        .groupby("matched_session_key")
        .agg(
            matched_lead_count=("lead_row_id", "count"),
            matched_form1_lead_count=(
                "form_name",
                lambda x: int((x == "lead_form_1").sum()),
            ),
            matched_form2_lead_count=(
                "form_name",
                lambda x: int((x == "lead_form_2").sum()),
            ),
            has_matched_form1_lead=(
                "form_name",
                lambda x: int((x == "lead_form_1").any()),
            ),
            has_matched_form2_lead=(
                "form_name",
                lambda x: int((x == "lead_form_2").any()),
            ),
        )
        .reset_index()
        .rename(columns={"matched_session_key": "session_key"})
    )


analysis_df = sessions.merge(
    lead_labels,
    on="session_key",
    how="left",
)

for col in [
    "matched_lead_count",
    "matched_form1_lead_count",
    "matched_form2_lead_count",
    "has_matched_form1_lead",
    "has_matched_form2_lead",
]:
    if col not in analysis_df.columns:
        analysis_df[col] = 0

    analysis_df[col] = (
        analysis_df[col]
        .fillna(0)
        .astype(int)
    )


# Taxonomy-aligned Form 1 / Form 2 submission flags.
if "lead1_submit_flag" in analysis_df.columns:
    analysis_df["lead1_submitted"] = (
        pd.to_numeric(
            analysis_df["lead1_submit_flag"],
            errors="coerce",
        )
        .fillna(0)
        .clip(0, 1)
        .astype(int)
    )
else:
    analysis_df["lead1_submitted"] = (
        analysis_df["has_matched_form1_lead"] > 0
    ).astype(int)


if "lead2_submit_flag" in analysis_df.columns:
    analysis_df["lead2_submitted"] = (
        pd.to_numeric(
            analysis_df["lead2_submit_flag"],
            errors="coerce",
        )
        .fillna(0)
        .clip(0, 1)
        .astype(int)
    )
else:
    analysis_df["lead2_submitted"] = (
        analysis_df["has_matched_form2_lead"] > 0
    ).astype(int)


analysis_df["any_lead_submitted"] = (
    (analysis_df["lead1_submitted"] > 0)
    | (analysis_df["lead2_submitted"] > 0)
).astype(int)


def define_lead_stage(row):
    if (
        row["has_matched_form1_lead"]
        and row["has_matched_form2_lead"]
    ):
        return "form1_and_form2"

    if row["has_matched_form1_lead"]:
        return "form1_only"

    if row["has_matched_form2_lead"]:
        return "form2_only"

    return "no_matched_lead"


analysis_df["lead_stage"] = analysis_df.apply(
    define_lead_stage,
    axis=1,
)


# ---------------------------------------------------------------------
# Clustering features
# ---------------------------------------------------------------------

numeric_features = [
    "session_duration_sec",
    "total_events",
    "distinct_event_count",
    "page_view_count",
    "total_engagement_time_sec",
    "max_scroll_percent",
    "max_timer_seconds",
    "nav_cta_clicks",
    "hero_cta_clicks",
    "footer_cta_clicks",
    "mobile_cta_clicks",
    "total_cta_clicks",
    "visited_lp1_flag",
    "visited_lp2_flag",
    "visited_thankyou1_flag",
    "visited_thankyou2_flag",
    "scroll_10_flag",
    "scroll_20_flag",
    "scroll_30_flag",
    "scroll_40_flag",
    "scroll_50_flag",
    "scroll_60_flag",
    "scroll_70_flag",
    "scroll_80_flag",
    "scroll_90_flag",
    "scroll_99_flag",
    "timer_5s_flag",
    "timer_10s_flag",
    "timer_20s_flag",
    "timer_40s_flag",
    "timer_60s_flag",
    "lead1_submitted",
    "lead2_submitted",
]

categorical_features = [
    "traffic_group",
    "device_category",
    "operating_system",
    "browser",
    "source",
    "medium",
    "campaign",
    "content",
]

numeric_features = [
    col
    for col in numeric_features
    if col in analysis_df.columns
]

categorical_features = [
    col
    for col in categorical_features
    if col in analysis_df.columns
]

model_df = analysis_df[
    numeric_features + categorical_features
].copy()

for col in numeric_features:
    model_df[col] = (
        pd.to_numeric(
            model_df[col],
            errors="coerce",
        )
        .fillna(0)
    )

for col in categorical_features:
    model_df[col] = (
        model_df[col]
        .fillna("(not set)")
        .astype(str)
    )

model_encoded = pd.get_dummies(
    model_df,
    columns=categorical_features,
    drop_first=False,
)

constant_cols = [
    col
    for col in model_encoded.columns
    if model_encoded[col].nunique() <= 1
]

model_encoded = model_encoded.drop(
    columns=constant_cols
)

if model_encoded.shape[0] < 3:
    raise ValueError("At least 3 sessions are required.")

if model_encoded.shape[1] < 1:
    raise ValueError("No usable clustering features remain.")


# ---------------------------------------------------------------------
# Scaling and K diagnostics
# ---------------------------------------------------------------------

scaler = StandardScaler()
X_scaled = scaler.fit_transform(model_encoded)

n_samples = len(model_encoded)
max_k = min(10, n_samples - 1)

diagnostics = []

for k in range(1, max_k + 1):
    model = KMeans(
        n_clusters=k,
        random_state=RANDOM_STATE,
        n_init=10,
    )

    model.fit(X_scaled)

    row = {
        "k": k,
        "inertia": model.inertia_,
    }

    if (
        k >= 2
        and len(set(model.labels_)) > 1
    ):
        row["silhouette"] = silhouette_score(
            X_scaled,
            model.labels_,
        )

    diagnostics.append(row)

diagnostics_df = pd.DataFrame(diagnostics)

print("\nK diagnostics")
print(diagnostics_df.to_string(index=False))

plt.figure(figsize=(8, 5))
plt.plot(
    diagnostics_df["k"],
    diagnostics_df["inertia"],
    marker="o",
)
plt.xlabel("K")
plt.ylabel("Inertia")
plt.title("Elbow diagnostic")
plt.tight_layout()
plt.show()


# ---------------------------------------------------------------------
# K-Means clustering
# ---------------------------------------------------------------------

K = min(
    max(FORCE_K, 2),
    n_samples - 1,
)

kmeans = KMeans(
    n_clusters=K,
    random_state=RANDOM_STATE,
    n_init=10,
)

analysis_df["cluster"] = kmeans.fit_predict(
    X_scaled
)


# ---------------------------------------------------------------------
# PCA projection
# ---------------------------------------------------------------------

pca = PCA(
    n_components=2,
    random_state=RANDOM_STATE,
)

X_2d = pca.fit_transform(X_scaled)

analysis_df["pca_1"] = X_2d[:, 0]
analysis_df["pca_2"] = X_2d[:, 1]

plt.figure(figsize=(8, 6))

for cluster_id in sorted(
    analysis_df["cluster"].unique()
):
    mask = analysis_df["cluster"] == cluster_id

    plt.scatter(
        analysis_df.loc[mask, "pca_1"],
        analysis_df.loc[mask, "pca_2"],
        label=f"Cluster {cluster_id}",
        alpha=0.8,
    )

plt.xlabel("PC1")
plt.ylabel("PC2")
plt.title("Session behavior clusters (PCA projection)")
plt.legend()
plt.tight_layout()
plt.show()


# ---------------------------------------------------------------------
# Cluster summary
# ---------------------------------------------------------------------

summary_metrics = [
    "session_duration_sec",
    "total_events",
    "page_view_count",
    "total_engagement_time_sec",
    "max_scroll_percent",
    "max_timer_seconds",
    "nav_cta_clicks",
    "hero_cta_clicks",
    "footer_cta_clicks",
    "mobile_cta_clicks",
    "total_cta_clicks",
    "lead1_submitted",
    "lead2_submitted",
    "any_lead_submitted",
]

summary_metrics = [
    col
    for col in summary_metrics
    if col in analysis_df.columns
]

cluster_summary = (
    analysis_df
    .groupby("cluster")[summary_metrics]
    .mean()
    .round(3)
    .reset_index()
)

cluster_sizes = (
    analysis_df
    .groupby("cluster")
    .agg(
        sessions=("session_key", "count"),
        users=("user_pseudo_id", "nunique"),
    )
    .reset_index()
)

cluster_summary = cluster_sizes.merge(
    cluster_summary,
    on="cluster",
    how="left",
)

print("\nCluster summary")
print(cluster_summary.to_string(index=False))


# ---------------------------------------------------------------------
# Privacy-safe lead interpretation after clustering
# ---------------------------------------------------------------------

cluster_map = analysis_df[
    ["session_key", "cluster"]
].copy()

lead_interpretation = matched_leads.merge(
    cluster_map,
    left_on="matched_session_key",
    right_on="session_key",
    how="inner",
)

if not lead_interpretation.empty:
    if "inquiry_purpose" in lead_interpretation.columns:
        inquiry_purpose_summary = (
            lead_interpretation
            .dropna(subset=["inquiry_purpose"])
            .groupby(
                ["cluster", "inquiry_purpose"]
            )
            .size()
            .reset_index(name="lead_count")
            .sort_values(
                ["cluster", "lead_count"],
                ascending=[True, False],
            )
        )

        print("\nInquiry purpose by cluster")
        print(
            inquiry_purpose_summary.to_string(
                index=False
            )
        )

    detail_cols = [
        col
        for col in [
            "has_inquiry_detail",
            "inquiry_detail_length",
        ]
        if col in lead_interpretation.columns
    ]

    if detail_cols:
        detail_summary = (
            lead_interpretation
            .groupby("cluster")[detail_cols]
            .mean()
            .round(3)
            .reset_index()
        )

        print("\nLead-detail signals by cluster")
        print(detail_summary.to_string(index=False))

lead_stage_ratio = pd.crosstab(
    analysis_df["cluster"],
    analysis_df["lead_stage"],
    normalize="index",
).round(3)

print("\nMatched lead stage ratio by cluster")
print(lead_stage_ratio.to_string())

print("\nDone.")
print(
    "Clusters:",
    analysis_df["cluster"]
    .value_counts()
    .sort_index()
    .to_dict(),
)
print(
    "PCA explained variance:",
    round(
        float(
            pca.explained_variance_ratio_.sum()
        ),
        3,
    ),
)
