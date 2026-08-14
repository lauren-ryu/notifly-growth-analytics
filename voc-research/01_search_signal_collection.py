"""
Notifly VOC Research — Stage 1
Broad search-signal collection using the Naver Search API.

Purpose
- Collect CRM / retention / marketing-automation search results.
- Tag likely barriers, alternatives, funnel stages, and LP-use themes.
- Remove duplicate URLs.
- Flag ad-like results.
- Keep a broad set of valid candidates for deeper review.

Security
- API credentials are read from environment variables.
- No credentials, raw lead data, or local private paths are stored in this file.
"""

import os
import re
import time
from datetime import datetime
from html import unescape
from urllib.parse import urlparse

import pandas as pd
import requests


# ============================================================
# 0. Configuration
# ============================================================

NAVER_CLIENT_ID = os.getenv("NAVER_CLIENT_ID")
NAVER_CLIENT_SECRET = os.getenv("NAVER_CLIENT_SECRET")

if not NAVER_CLIENT_ID or not NAVER_CLIENT_SECRET:
    raise RuntimeError(
        "Set NAVER_CLIENT_ID and NAVER_CLIENT_SECRET as environment variables."
    )

WEBKR_ENDPOINT = "https://openapi.naver.com/v1/search/webkr.json"

DISPLAY_PER_QUERY = 20
SORT = "sim"
SLEEP_SEC = 0.3

collected_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")


# ============================================================
# 1. Helpers
# ============================================================

def clean_html(text):
    if text is None:
        return ""
    text = unescape(str(text))
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def fetch_naver_api(endpoint, query, display=20, start=1, sort="sim"):
    headers = {
        "X-Naver-Client-Id": NAVER_CLIENT_ID,
        "X-Naver-Client-Secret": NAVER_CLIENT_SECRET,
    }
    params = {
        "query": query,
        "display": display,
        "start": start,
        "sort": sort,
    }

    response = requests.get(
        endpoint,
        headers=headers,
        params=params,
        timeout=10,
    )

    if response.status_code != 200:
        print("API Error:", response.status_code, response.text[:200])
        return []

    return response.json().get("items", [])


def get_domain(url):
    try:
        return urlparse(str(url)).netloc.lower().replace("www.", "")
    except Exception:
        return ""


def contains_any(text, keywords):
    text = str(text).lower()
    return any(str(keyword).lower() in text for keyword in keywords)


# ============================================================
# 2. Search keyword design
# ============================================================

KEYWORDS = [
    # A. Problem awareness
    ("문제인식", "회원가입 후 이탈"),
    ("문제인식", "가입 후 미사용"),
    ("문제인식", "온보딩 이탈"),
    ("문제인식", "첫 구매 전 이탈"),
    ("문제인식", "장바구니 이탈"),
    ("문제인식", "재방문율 낮음"),
    ("문제인식", "리텐션 개선"),
    ("문제인식", "고객 이탈 방지"),
    ("문제인식", "앱 유저 이탈"),
    ("문제인식", "고객 행동 기반 마케팅"),

    # B. Comparison / evaluation
    ("비교검토", "CRM 솔루션 비교"),
    ("비교검토", "CRM 마케팅 툴 추천"),
    ("비교검토", "마케팅 자동화 툴 비교"),
    ("비교검토", "Braze 대체"),
    ("비교검토", "Braze 후기"),
    ("비교검토", "빅인 후기"),
    ("비교검토", "데이터라이즈 후기"),
    ("비교검토", "채널톡 CRM"),
    ("비교검토", "푸시 알림 솔루션 비교"),
    ("비교검토", "알림톡 자동화 솔루션"),

    # C. Adoption barriers
    ("도입장벽", "CRM 솔루션 가격"),
    ("도입장벽", "마케팅 자동화 비용"),
    ("도입장벽", "CRM 세팅 어려움"),
    ("도입장벽", "Braze 세팅"),
    ("도입장벽", "개발자 없이 CRM"),
    ("도입장벽", "CRM 데이터 연동"),
    ("도입장벽", "CRM 캠페인 성과 측정"),
    ("도입장벽", "알림톡 전환 추적"),
    ("도입장벽", "푸시 A/B 테스트"),
    ("도입장벽", "CRM 도입 제안서"),

    # D. Alternatives / selection criteria
    ("대체행동", "카카오톡 채널 CRM"),
    ("대체행동", "엑셀 고객 관리"),
    ("대체행동", "문자 마케팅 자동화"),
    ("대체행동", "이메일 마케팅 자동화"),
    ("대체행동", "GA4 리텐션 분석"),
    ("대체행동", "Amplitude 리텐션 분석"),
    ("대체행동", "Mixpanel 코호트 분석"),
    ("대체행동", "자체 CRM 구축"),
    ("선택기준", "CRM 솔루션 선택 기준"),
    ("선택기준", "마케팅 자동화 체크리스트"),
]


# ============================================================
# 3. Source groups
# ============================================================

SITE_GROUPS = [
    ("전체웹", ""),
    ("아이보스", "i-boss.co.kr"),
    ("브런치", "brunch.co.kr"),
    ("요즘IT", "yozm.wishket.com"),
    ("디스콰이엇", "disquiet.io"),
    ("네이버블로그", "blog.naver.com"),
    ("네이버카페", "cafe.naver.com"),
    ("링크드인", "linkedin.com"),
]


# ============================================================
# 4. Initial tagging rules
# ============================================================

AD_KEYWORDS = [
    "문의하세요", "상담 문의", "도입 문의", "무료 상담", "견적", "대행",
    "전문 업체", "저희", "당사", "서비스를 제공합니다", "공식 파트너",
    "프로모션", "이벤트", "할인", "마케팅 대행",
]

RELEVANCE_KEYWORDS = [
    "crm", "리텐션", "자동화", "마케팅 자동화", "세그먼트", "고객군",
    "푸시", "알림톡", "브랜드 메시지", "이메일", "문자", "캠페인",
    "전환율", "재방문", "이탈", "온보딩", "a/b", "ab테스트",
    "퍼널", "코호트", "고객 행동", "개인화", "도입", "연동",
]

BARRIER_RULES = {
    "비용": ["가격", "비용", "요금", "비싸", "견적", "플랜"],
    "세팅난이도": ["세팅", "설정", "어려움", "복잡", "구축", "초기 세팅"],
    "개발의존": ["개발자", "개발팀", "API", "연동", "SDK", "데이터 연동"],
    "성과불확실": ["성과", "전환율", "ROAS", "ROI", "측정", "추적", "기여"],
    "내부설득": ["제안서", "도입 필요성", "설득", "보고", "팀장", "대표"],
    "기존툴대체": ["카카오톡 채널", "엑셀", "구글시트", "문자", "이메일", "수동"],
    "비교기준부족": ["비교", "추천", "선택 기준", "체크리스트", "후기", "대체"],
}

ALTERNATIVE_RULES = {
    "Braze": ["Braze", "브레이즈"],
    "Bigin": ["Bigin", "빅인", "빅인사이트"],
    "Datarize": ["Datarize", "데이터라이즈"],
    "FlareLane": ["FlareLane", "플레어레인"],
    "Solapi": ["Solapi", "솔라피", "알림톡", "문자"],
    "ChannelTalk": ["채널톡", "Channel Talk", "channel.io"],
    "Hackle": ["Hackle", "핵클"],
    "Salesforce": ["Salesforce", "세일즈포스", "SFMC"],
    "Stibee": ["Stibee", "스티비", "이메일"],
    "GA4/Amplitude/Mixpanel": ["GA4", "Amplitude", "Mixpanel", "코호트", "퍼널"],
    "수동운영": ["엑셀", "구글시트", "수동", "카카오톡 채널"],
}

STAGE_RULES = {
    "문제인식": ["필요성", "왜 필요", "이탈", "재방문", "리텐션", "온보딩"],
    "비교검토": ["비교", "추천", "후기", "대체", "선택 기준"],
    "도입검토": ["가격", "비용", "도입", "제안서", "연동", "세팅"],
    "사용/운영": ["성과 측정", "전환 추적", "A/B", "캠페인", "운영"],
}

LP_USE_RULES = {
    "Hero/문제제기": ["이탈", "재방문", "온보딩", "첫 구매", "장바구니"],
    "비교표": ["비교", "대체", "추천", "후기", "선택 기준"],
    "혜택/CTA": ["무료", "체험", "크레딧", "상담", "도입"],
    "FAQ": ["가격", "비용", "연동", "세팅", "개발자"],
    "성과증거": ["성과", "전환율", "ROAS", "ROI", "측정", "추적"],
}


def relevance_score(text):
    score = 0
    for keyword in RELEVANCE_KEYWORDS:
        if keyword.lower() in str(text).lower():
            score += 1
    return min(score, 5)


def tag_by_rules(text, rules, default="미분류"):
    tags = []
    for label, keywords in rules.items():
        if contains_any(text, keywords):
            tags.append(label)
    return ", ".join(tags) if tags else default


def is_ad_like(text):
    return contains_any(text, AD_KEYWORDS)


def classify_source_type(domain):
    if "i-boss.co.kr" in domain:
        return "마케팅커뮤니티"
    if "cafe.naver.com" in domain:
        return "커뮤니티/카페"
    if "blog.naver.com" in domain:
        return "블로그"
    if "brunch.co.kr" in domain:
        return "콘텐츠플랫폼"
    if "yozm.wishket.com" in domain:
        return "IT콘텐츠미디어"
    if "disquiet.io" in domain:
        return "스타트업/프로덕트커뮤니티"
    if "linkedin.com" in domain:
        return "실무자/기업SNS"
    return "일반웹"


# ============================================================
# 5. Collection
# ============================================================

rows = []

for keyword_group, keyword in KEYWORDS:
    for site_name, site_domain in SITE_GROUPS:
        query = f"site:{site_domain} {keyword}" if site_domain else keyword

        print(f"Collecting: {site_name} / {keyword_group} / {keyword}")

        items = fetch_naver_api(
            endpoint=WEBKR_ENDPOINT,
            query=query,
            display=DISPLAY_PER_QUERY,
            start=1,
            sort=SORT,
        )

        for rank, item in enumerate(items, start=1):
            title = clean_html(item.get("title", ""))
            description = clean_html(item.get("description", ""))
            url = item.get("link", "")
            domain = get_domain(url)
            combined_text = f"{title} {description}"

            rows.append(
                {
                    "collected_at": collected_at,
                    "site_group": site_name,
                    "source_type": classify_source_type(domain),
                    "keyword_group": keyword_group,
                    "search_keyword": keyword,
                    "search_query": query,
                    "rank": rank,
                    "title": title,
                    "description": description,
                    "url": url,
                    "domain": domain,
                    "ad_like_estimate": is_ad_like(combined_text),
                    "relevance_score_1to5": relevance_score(combined_text),
                    "barrier_tags": tag_by_rules(combined_text, BARRIER_RULES),
                    "alternative_tags": tag_by_rules(combined_text, ALTERNATIVE_RULES),
                    "customer_stage_tags": tag_by_rules(combined_text, STAGE_RULES),
                    "lp_use_tags": tag_by_rules(combined_text, LP_USE_RULES),
                }
            )

        time.sleep(SLEEP_SEC)

df = pd.DataFrame(rows)


# ============================================================
# 6. Post-processing
# ============================================================

df = df.drop_duplicates(subset=["url"]).reset_index(drop=True)

df["is_valid_candidate"] = (
    (df["relevance_score_1to5"] >= 2)
    & (df["ad_like_estimate"] == False)
)


def priority(row):
    if row["relevance_score_1to5"] >= 4 and row["ad_like_estimate"] == False:
        return "high"
    if row["relevance_score_1to5"] >= 2 and row["ad_like_estimate"] == False:
        return "medium"
    return "low"


df["analysis_priority"] = df.apply(priority, axis=1)

priority_order = pd.CategoricalDtype(
    categories=["high", "medium", "low"],
    ordered=True,
)
df["analysis_priority"] = df["analysis_priority"].astype(priority_order)

df = df.sort_values(
    by=["analysis_priority", "relevance_score_1to5"],
    ascending=[True, False],
).reset_index(drop=True)


# ============================================================
# 7. Optional local export
# ============================================================

# Public repository note:
# No collected CSV files are included in this repository.
# Uncomment locally only if you want to save analysis outputs.
#
# df.to_csv("notifly_research_raw_tagged.csv", index=False, encoding="utf-8-sig")
# df[df["is_valid_candidate"]].to_csv(
#     "notifly_research_valid_candidates.csv",
#     index=False,
#     encoding="utf-8-sig",
# )

print("Collected unique URLs:", len(df))
print("Valid candidates:", int(df["is_valid_candidate"].sum()))
print(df.head(20))
