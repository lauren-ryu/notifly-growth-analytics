"""
Notifly VOC Research — Stage 2
Question-led expansion, body validation, evidence extraction, and tagging.

This public version preserves the analysis logic used in the project while
removing credentials, private paths, and all file-export / download steps.

Local prerequisites:
    pip install pandas requests beautifulsoup4 lxml tqdm trafilatura

Environment variables:
    NAVER_CLIENT_ID
    NAVER_CLIENT_SECRET

Optional:
    NOTIFLY_STAGE1_CSV
        Local path to the Stage 1 candidate CSV if you want to combine it
        with the additional question-led search results. The CSV itself is
        not included in this repository.
"""

import os
import re
import time
from datetime import datetime
from html import unescape
from urllib.parse import urlparse

import pandas as pd
import requests
import trafilatura
from bs4 import BeautifulSoup
from tqdm import tqdm


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

DISPLAY_PER_QUERY = 15
SORT = "sim"
SLEEP_SEC = 0.4
MAX_BODY_URLS = 120

# Optional local Stage 1 file. No data file is included in the public repo.
EXISTING_CSV = os.getenv("NOTIFLY_STAGE1_CSV")

collected_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0 Safari/537.36"
    )
}


# ============================================================
# 1. Shared helpers
# ============================================================

def clean_html(text):
    if text is None:
        return ""
    text = unescape(str(text))
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def fetch_naver_api(endpoint, query, display=15, start=1, sort="sim"):
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

    try:
        response = requests.get(
            endpoint,
            headers=headers,
            params=params,
            timeout=12,
        )
        if response.status_code != 200:
            print("API Error:", response.status_code, response.text[:200])
            return []
        return response.json().get("items", [])
    except requests.RequestException as exc:
        print("API Exception:", exc)
        return []


def get_domain(url):
    try:
        return urlparse(str(url)).netloc.lower().replace("www.", "")
    except Exception:
        return ""


def contains_any(text, terms):
    text = str(text).lower()
    return any(str(term).lower() in text for term in terms)


def tag_by_rules(text, rules, default="미분류"):
    tags = []
    for label, keywords in rules.items():
        if contains_any(text, keywords):
            tags.append(label)
    return ", ".join(tags) if tags else default


def classify_source_type(domain):
    domain = str(domain).lower()

    if "i-boss.co.kr" in domain:
        return "마케팅커뮤니티"
    if "cafe.naver.com" in domain:
        return "커뮤니티/카페"
    if "blog.naver.com" in domain or "m.blog.naver.com" in domain:
        return "블로그"
    if "brunch.co.kr" in domain:
        return "콘텐츠플랫폼"
    if "yozm.wishket.com" in domain:
        return "IT콘텐츠미디어"
    if "disquiet.io" in domain:
        return "스타트업/프로덕트커뮤니티"
    if "linkedin.com" in domain:
        return "실무자/기업SNS"
    if any(
        name in domain
        for name in [
            "notifly.tech",
            "braze.com",
            "bigin.io",
            "datarize.ai",
            "flarelane.com",
            "solapi.com",
            "hackle.io",
            "channel.io",
        ]
    ):
        return "공급자/경쟁사"

    return "일반웹"


# ============================================================
# 2. Research questions and search design
# ============================================================

RESEARCH_QUESTIONS = {
    "RQ1_페르소나": "누가 노티플라이의 실제 전환 가능성이 높은 페르소나인가?",
    "RQ2_대체방식": "이들은 지금 어떤 방식으로 CRM/리텐션 문제를 해결하고 있는가?",
    "RQ3_도입장벽": "왜 기존 방식을 계속 쓰고 있으며, 왜 바로 CRM 툴을 도입하지 않는가?",
    "RQ4_선택기준": "어떤 정보가 있어야 노티플라이를 검토할 수 있는가?",
    "RQ5_리드마그넷": "어떤 혜택을 주면 리드 제출이 자연스러워지는가?",
    "RQ6_시퀀스": "리드 제출 후 어떤 순서로 설득해야 상담까지 이어지는가?",
}

QUESTION_KEYWORDS = [
    # Persona validation
    ("페르소나검증", "CRM 마케터 고민"),
    ("페르소나검증", "그로스 마케터 리텐션"),
    ("페르소나검증", "앱 마케팅 푸시 알림"),
    ("페르소나검증", "이커머스 CRM 마케팅"),
    ("페르소나검증", "스타트업 리텐션 마케팅"),
    ("페르소나검증", "B2C 마케팅 자동화"),
    ("페르소나검증", "쇼핑몰 CRM 마케팅"),
    ("페르소나검증", "앱 온보딩 마케팅"),
    ("페르소나검증", "SaaS 온보딩 메시지"),
    ("페르소나검증", "고객 재방문 마케팅"),

    # Existing alternatives
    ("대체방식검증", "카카오톡 채널 고객 관리"),
    ("대체방식검증", "알림톡 마케팅 자동화"),
    ("대체방식검증", "문자 마케팅 자동화"),
    ("대체방식검증", "이메일 마케팅 자동화"),
    ("대체방식검증", "엑셀 고객 관리 CRM"),
    ("대체방식검증", "구글시트 고객 관리"),
    ("대체방식검증", "GA4 리텐션 분석"),
    ("대체방식검증", "Amplitude 리텐션 분석"),
    ("대체방식검증", "Mixpanel 코호트 분석"),
    ("대체방식검증", "자체 CRM 구축"),
    ("대체방식검증", "CRM 시스템 구축"),

    # Adoption barriers
    ("도입장벽검증", "CRM 솔루션 도입 고민"),
    ("도입장벽검증", "CRM 솔루션 가격 부담"),
    ("도입장벽검증", "마케팅 자동화 비용"),
    ("도입장벽검증", "CRM 데이터 연동 어려움"),
    ("도입장벽검증", "CRM 세팅 어려움"),
    ("도입장벽검증", "Braze 세팅 어려움"),
    ("도입장벽검증", "개발자 없이 CRM 가능"),
    ("도입장벽검증", "CRM 도입 실패"),
    ("도입장벽검증", "CRM 도입 필요성 설득"),
    ("도입장벽검증", "CRM 캠페인 성과 측정"),
    ("도입장벽검증", "알림톡 전환 추적"),
    ("도입장벽검증", "푸시 알림 효과 측정"),

    # Selection criteria
    ("선택기준검증", "CRM 솔루션 선택 기준"),
    ("선택기준검증", "CRM 솔루션 비교표"),
    ("선택기준검증", "마케팅 자동화 툴 선택"),
    ("선택기준검증", "마케팅 자동화 체크리스트"),
    ("선택기준검증", "CRM 도입 체크리스트"),
    ("선택기준검증", "CRM 마케팅 KPI"),
    ("선택기준검증", "리텐션 마케팅 KPI"),
    ("선택기준검증", "CRM 캠페인 설계"),
    ("선택기준검증", "CRM 시나리오 설계"),
    ("선택기준검증", "고객 세그먼트 설계"),

    # Lead-magnet validation
    ("리드마그넷검증", "CRM 진단 체크리스트"),
    ("리드마그넷검증", "마케팅 자동화 체크리스트"),
    ("리드마그넷검증", "CRM 도입 가이드"),
    ("리드마그넷검증", "CRM 솔루션 비교 가이드"),
    ("리드마그넷검증", "리텐션 개선 사례"),
    ("리드마그넷검증", "푸시 알림 캠페인 사례"),
    ("리드마그넷검증", "알림톡 마케팅 사례"),
    ("리드마그넷검증", "CRM 캠페인 템플릿"),
    ("리드마그넷검증", "CRM 도입 제안서"),
    ("리드마그넷검증", "리텐션 마케팅 보고서"),
]

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
# 3. Tagging rules
# ============================================================

PERSONA_RULES = {
    "CRM마케터": ["CRM 마케터", "CRM마케터", "CRM 담당자", "CRM 마케팅", "CRM 캠페인"],
    "그로스마케터": ["그로스", "growth", "리텐션", "퍼널", "A/B", "AB테스트", "전환율"],
    "앱서비스마케터/PM": ["앱", "푸시", "온보딩", "유저", "인앱", "모바일"],
    "이커머스마케터": ["쇼핑몰", "이커머스", "구매", "장바구니", "재구매", "커머스"],
    "B2B/SaaS마케터": ["SaaS", "B2B", "리드", "세일즈", "ABM", "도입 상담"],
    "소규모운영자/대표": ["대표", "소상공인", "스몰 브랜드", "운영자", "1인", "소규모"],
}

COMPANY_CONTEXT_RULES = {
    "이커머스/쇼핑몰": ["쇼핑몰", "이커머스", "커머스", "구매", "장바구니", "재구매", "상품"],
    "앱서비스": ["앱", "모바일", "푸시", "인앱", "유저", "설치", "앱푸시"],
    "SaaS/B2B": ["SaaS", "B2B", "리드", "세일즈", "도입", "상담", "ABM"],
    "교육/콘텐츠": ["교육", "강의", "수강", "콘텐츠", "구독"],
    "스타트업/초기서비스": ["스타트업", "초기", "런칭", "MVP", "메이커", "프로덕트"],
    "일반마케팅": ["마케팅", "고객", "캠페인", "CRM"],
}

FUNNEL_PROBLEM_RULES = {
    "가입후미사용/온보딩": ["가입 후", "미사용", "온보딩", "첫 행동", "활성화"],
    "첫구매전이탈": ["첫 구매", "구매 전", "장바구니", "결제 전", "전환"],
    "재방문/리텐션": ["재방문", "리텐션", "잔존", "유지", "retention"],
    "재구매/구매전환": ["재구매", "구매전환", "구매 전환", "매출", "객단가"],
    "휴면/이탈": ["휴면", "이탈", "churn", "탈퇴", "비활성"],
    "성과측정": ["성과", "측정", "전환율", "클릭률", "오픈율", "ROI", "ROAS"],
}

CURRENT_SOLUTION_RULES = {
    "알림톡/문자/SMS": ["알림톡", "문자", "SMS", "친구톡", "카카오"],
    "이메일/뉴스레터": ["이메일", "뉴스레터", "스티비", "Stibee", "메일"],
    "푸시/인앱메시지": ["푸시", "앱푸시", "인앱", "notification", "push"],
    "분석툴": ["GA4", "Google Analytics", "Amplitude", "Mixpanel", "코호트", "퍼널 분석"],
    "수동운영": ["엑셀", "구글시트", "수동", "스프레드시트", "리스트"],
    "대형CRM": ["Braze", "브레이즈", "Salesforce", "SFMC", "세일즈포스"],
    "국내CRM/자동화툴": [
        "빅인", "Bigin", "데이터라이즈", "Datarize",
        "채널톡", "Hackle", "핵클", "그루비", "Groobee",
    ],
    "자체개발": ["자체 개발", "자체 구축", "CRM 시스템 구축", "내부 개발", "사내 시스템"],
}

ADOPTION_BARRIER_RULES = {
    "필요성불확실": ["왜 필요", "필요성", "해야 하나", "꼭 해야", "필요할까"],
    "비교기준부족": ["비교", "추천", "선택 기준", "체크리스트", "후기", "대체", "비교표"],
    "비용부담": ["가격", "비용", "요금", "비싸", "견적", "플랜", "과금"],
    "세팅난이도": ["세팅", "설정", "어려움", "복잡", "구축", "초기 세팅", "셋업"],
    "개발의존": ["개발자", "개발팀", "API", "연동", "SDK", "데이터 연동", "개발 리소스"],
    "성과불확실": ["성과", "전환율", "ROAS", "ROI", "측정", "추적", "기여", "효과"],
    "내부설득": ["제안서", "도입 필요성", "설득", "보고", "팀장", "대표", "내부 공유", "의사결정"],
    "기존툴대체": ["카카오톡 채널", "엑셀", "구글시트", "문자", "이메일", "수동", "GA4"],
}

DECISION_STAGE_RULES = {
    "문제인식": ["이탈", "재방문", "리텐션", "온보딩", "필요성", "고민"],
    "비교검토": ["비교", "추천", "후기", "대체", "선택 기준", "비교표"],
    "도입검토": ["가격", "비용", "도입", "제안서", "연동", "세팅", "구축"],
    "사용/운영": ["성과 측정", "전환 추적", "A/B", "캠페인", "운영", "시나리오"],
    "리드전환": ["가이드", "체크리스트", "진단", "템플릿", "사례집", "보고서"],
}

NEEDED_ASSET_RULES = {
    "무료CRM진단": ["진단", "체크리스트", "준비도", "필요성", "우리 팀"],
    "솔루션비교가이드": ["비교", "선택 기준", "추천", "비교표", "대체", "후기"],
    "리텐션개선사례집": ["사례", "리텐션", "재방문", "재구매", "이탈", "개선"],
    "첫캠페인템플릿": ["시나리오", "캠페인", "템플릿", "A/B", "푸시", "알림톡"],
    "팀공유용도입PDF": ["제안서", "도입 필요성", "설득", "보고", "ROI", "내부 공유"],
    "개발자없이도입체크리스트": ["개발자", "개발팀", "연동", "API", "세팅", "구축"],
}

MESSAGE_ANGLE_RULES = {
    "선택기준형": ["비교", "선택 기준", "체크리스트", "추천", "비교표"],
    "기존방식한계형": ["엑셀", "구글시트", "수동", "카카오톡 채널", "알림톡", "문자", "이메일"],
    "개발자없이실행형": ["개발자", "개발팀", "연동", "API", "SDK", "세팅"],
    "성과검증형": ["성과", "전환율", "ROI", "ROAS", "측정", "추적", "클릭률"],
    "낮은리스크체험형": ["무료", "체험", "크레딧", "30일", "도입"],
    "내부설득지원형": ["제안서", "보고", "설득", "대표", "팀장", "내부 공유"],
}

HYPOTHESIS_RULES = {
    "H1_비교검토층가설": [
        "CRM 솔루션 비교", "마케팅 자동화 툴 비교", "알림톡 자동화",
        "GA4", "엑셀", "Braze 대체", "비교", "대체",
    ],
    "H2_개발리소스장벽가설": ["개발자", "개발팀", "연동", "API", "SDK", "세팅", "구축", "데이터 연동"],
    "H3_성과확신부족가설": ["성과", "전환율", "클릭률", "오픈율", "ROI", "ROAS", "측정", "추적", "KPI"],
    "H4_내부설득자료부족가설": ["제안서", "도입 필요성", "설득", "보고", "대표", "팀장", "내부 공유", "ROI"],
}

AD_LIKE_TERMS = [
    "문의하세요", "상담 문의", "도입 문의", "무료 상담", "견적",
    "전문 업체", "저희", "당사", "서비스를 제공합니다",
    "공식 파트너", "프로모션", "이벤트", "할인", "마케팅 대행",
]

BAD_TITLE_TERMS = [
    "채용", "회사소개", "고객센터", "도움말",
    "리드 양식", "카페24 스토어", "광고 도구 작동",
]


# ============================================================
# 4. Question-led expansion
# ============================================================

rows = []

for keyword_group, keyword in QUESTION_KEYWORDS:
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

            rows.append(
                {
                    "수집일시": collected_at,
                    "데이터출처": "질문형추가크롤링",
                    "사이트그룹": site_name,
                    "소스타입": classify_source_type(domain),
                    "키워드그룹": keyword_group,
                    "검색키워드": keyword,
                    "검색쿼리": query,
                    "순위": rank,
                    "제목": title,
                    "요약문": description,
                    "URL": url,
                    "도메인": domain,
                }
            )

        time.sleep(SLEEP_SEC)

df_new = pd.DataFrame(rows)
df_new = df_new.drop_duplicates(subset=["URL"]).reset_index(drop=True)

print("Question-led collection:", len(df_new))


# ============================================================
# 5. Optional combination with Stage 1 candidates
# ============================================================

frames = [df_new]

if EXISTING_CSV and os.path.exists(EXISTING_CSV):
    df_existing = pd.read_csv(EXISTING_CSV)
    df_existing["데이터출처"] = "기존검색결과"

    for col in df_new.columns:
        if col not in df_existing.columns:
            df_existing[col] = ""

    for col in df_existing.columns:
        if col not in df_new.columns:
            df_new[col] = ""

    df_existing = df_existing[df_new.columns]
    frames.append(df_existing)

    print("Combined Stage 1 candidates:", len(df_existing))
else:
    print("No Stage 1 CSV supplied; using new question-led results only.")

df_all = pd.concat(frames, ignore_index=True)
df_all = df_all.drop_duplicates(subset=["URL"]).reset_index(drop=True)

print("Total candidate URLs:", len(df_all))


# ============================================================
# 6. Initial scoring and tagging
# ============================================================

def combined_text(row):
    return f"{row.get('제목', '')} {row.get('요약문', '')} {row.get('본문', '')}"


def is_ad_like(text):
    return contains_any(text, AD_LIKE_TERMS)


def calculate_relevance(text):
    rule_groups = [
        PERSONA_RULES,
        COMPANY_CONTEXT_RULES,
        FUNNEL_PROBLEM_RULES,
        CURRENT_SOLUTION_RULES,
        ADOPTION_BARRIER_RULES,
        DECISION_STAGE_RULES,
        NEEDED_ASSET_RULES,
        MESSAGE_ANGLE_RULES,
        HYPOTHESIS_RULES,
    ]

    score = 0
    lowered = str(text).lower()

    for rules in rule_groups:
        for keywords in rules.values():
            for keyword in keywords:
                if str(keyword).lower() in lowered:
                    score += 1

    return min(score, 20)


def source_weight(source_type):
    weights = {
        "마케팅커뮤니티": 5,
        "스타트업/프로덕트커뮤니티": 5,
        "커뮤니티/카페": 4,
        "콘텐츠플랫폼": 3,
        "IT콘텐츠미디어": 3,
        "블로그": 2,
        "실무자/기업SNS": 2,
        "공급자/경쟁사": 2,
        "일반웹": 1,
    }
    return weights.get(source_type, 1)


def priority_score(row):
    text = combined_text(row)

    score = calculate_relevance(text)
    score += source_weight(row.get("소스타입", "")) * 2

    if contains_any(row.get("제목", ""), BAD_TITLE_TERMS):
        score -= 8

    if is_ad_like(text):
        score -= 3

    if row.get("키워드그룹", "") in {
        "페르소나검증",
        "대체방식검증",
        "도입장벽검증",
        "선택기준검증",
        "리드마그넷검증",
    }:
        score += 3

    return score


for col in ["제목", "요약문"]:
    if col not in df_all.columns:
        df_all[col] = ""

df_all["자동관련성점수"] = df_all.apply(
    lambda row: calculate_relevance(combined_text(row)),
    axis=1,
)
df_all["광고성추정"] = df_all.apply(
    lambda row: is_ad_like(combined_text(row)),
    axis=1,
)
df_all["본문확인우선점수"] = df_all.apply(priority_score, axis=1)

df_all["persona_final_1차"] = df_all.apply(
    lambda row: tag_by_rules(combined_text(row), PERSONA_RULES),
    axis=1,
)
df_all["company_context_1차"] = df_all.apply(
    lambda row: tag_by_rules(combined_text(row), COMPANY_CONTEXT_RULES),
    axis=1,
)
df_all["funnel_problem_1차"] = df_all.apply(
    lambda row: tag_by_rules(combined_text(row), FUNNEL_PROBLEM_RULES),
    axis=1,
)
df_all["current_solution_1차"] = df_all.apply(
    lambda row: tag_by_rules(combined_text(row), CURRENT_SOLUTION_RULES),
    axis=1,
)
df_all["adoption_barrier_final_1차"] = df_all.apply(
    lambda row: tag_by_rules(combined_text(row), ADOPTION_BARRIER_RULES),
    axis=1,
)
df_all["decision_stage_1차"] = df_all.apply(
    lambda row: tag_by_rules(combined_text(row), DECISION_STAGE_RULES),
    axis=1,
)
df_all["needed_asset_1차"] = df_all.apply(
    lambda row: tag_by_rules(combined_text(row), NEEDED_ASSET_RULES),
    axis=1,
)
df_all["message_angle_1차"] = df_all.apply(
    lambda row: tag_by_rules(combined_text(row), MESSAGE_ANGLE_RULES),
    axis=1,
)
df_all["hypothesis_signal_1차"] = df_all.apply(
    lambda row: tag_by_rules(combined_text(row), HYPOTHESIS_RULES),
    axis=1,
)


# ============================================================
# 7. Body extraction
# ============================================================

def normalize_naver_blog_url(url):
    url = str(url)

    if "blog.naver.com" not in url:
        return url

    match = re.search(r"blog\.naver\.com/([^/?]+)/(\d+)", url)

    if match:
        blog_id, log_no = match.group(1), match.group(2)
        return f"https://m.blog.naver.com/{blog_id}/{log_no}"

    return url


def extract_with_trafilatura(url):
    try:
        downloaded = trafilatura.fetch_url(url)

        if not downloaded:
            return "", "trafilatura_fetch_failed"

        text = trafilatura.extract(
            downloaded,
            include_comments=False,
            include_tables=False,
            favor_precision=True,
        )

        if text and len(text.strip()) > 300:
            return text.strip(), "trafilatura_success"

        return (
            text.strip() if text else "",
            "trafilatura_short_or_empty",
        )

    except Exception as exc:
        return "", f"trafilatura_error:{str(exc)[:80]}"


def extract_with_bs4(url):
    try:
        response = requests.get(url, headers=HEADERS, timeout=12)

        if response.status_code != 200:
            return "", f"requests_status_{response.status_code}"

        soup = BeautifulSoup(response.text, "lxml")

        for tag in soup(
            ["script", "style", "noscript", "header", "footer", "nav"]
        ):
            tag.decompose()

        text = soup.get_text(" ", strip=True)
        text = re.sub(r"\s+", " ", text).strip()

        if len(text) > 300:
            return text, "bs4_success"

        return text, "bs4_short_or_empty"

    except requests.RequestException as exc:
        return "", f"bs4_error:{str(exc)[:80]}"


def extract_body(url):
    final_url = normalize_naver_blog_url(url)

    text, status = extract_with_trafilatura(final_url)

    if text and len(text) > 500:
        return text, status, final_url

    fallback_text, fallback_status = extract_with_bs4(final_url)

    if len(fallback_text) > len(text):
        return fallback_text, fallback_status, final_url

    return text, status, final_url


# ============================================================
# 8. Evidence-sentence extraction
# ============================================================

EVIDENCE_TERMS = [
    "이탈", "전환", "리텐션", "재방문", "온보딩",
    "CRM", "crm", "자동화", "세그먼트", "캠페인",
    "성과", "측정", "분석", "비교", "도입",
    "비용", "가격", "연동", "개발자", "개발팀",
    "세팅", "설정", "알림톡", "푸시", "이메일", "문자",
    "수동", "엑셀", "카카오톡 채널", "제안서", "체크리스트",
]


def split_sentences_ko(text):
    text = re.sub(r"\s+", " ", str(text)).strip()
    sentences = re.split(
        r"(?<=[.!?。])\s+|(?<=[다요죠함음됨])\s+",
        text,
    )
    return [
        sentence.strip()
        for sentence in sentences
        if len(sentence.strip()) >= 25
    ]


def extract_evidence_sentences(text, max_sentences=4):
    scored = []

    for sentence in split_sentences_ko(text):
        score = sum(
            1
            for term in EVIDENCE_TERMS
            if term.lower() in sentence.lower()
        )

        if score > 0:
            scored.append((score, sentence))

    scored.sort(key=lambda item: item[0], reverse=True)

    return " / ".join(
        sentence
        for _, sentence in scored[:max_sentences]
    )


# ============================================================
# 9. Prioritized body validation
# ============================================================

shortlist = (
    df_all
    .sort_values("본문확인우선점수", ascending=False)
    .drop_duplicates(subset=["URL"])
    .head(MAX_BODY_URLS)
    .copy()
)

print("URLs selected for body validation:", len(shortlist))

body_rows = []

for _, row in tqdm(shortlist.iterrows(), total=len(shortlist)):
    url = row["URL"]
    body, status, final_url = extract_body(url)

    row_dict = row.to_dict()
    row_dict["최종접속URL"] = final_url
    row_dict["본문추출상태"] = status
    row_dict["본문길이"] = len(body) if body else 0
    row_dict["본문"] = body[:15000] if body else ""
    row_dict["근거문장후보"] = (
        extract_evidence_sentences(body)
        if body
        else ""
    )

    body_rows.append(row_dict)
    time.sleep(0.7)

body_df = pd.DataFrame(body_rows)
body_df["본문검증성공"] = body_df["본문길이"] >= 500

print("\nBody extraction status:")
print(body_df["본문추출상태"].value_counts(dropna=False))
print("Body validation success (>=500 chars):", int(body_df["본문검증성공"].sum()))


# ============================================================
# 10. Final tagging with body evidence
# ============================================================

def full_text(row):
    return (
        f"{row.get('제목', '')} "
        f"{row.get('요약문', '')} "
        f"{row.get('본문', '')} "
        f"{row.get('근거문장후보', '')}"
    )


body_df["persona_final"] = body_df.apply(
    lambda row: tag_by_rules(full_text(row), PERSONA_RULES),
    axis=1,
)
body_df["company_context"] = body_df.apply(
    lambda row: tag_by_rules(full_text(row), COMPANY_CONTEXT_RULES),
    axis=1,
)
body_df["funnel_problem"] = body_df.apply(
    lambda row: tag_by_rules(full_text(row), FUNNEL_PROBLEM_RULES),
    axis=1,
)
body_df["current_solution"] = body_df.apply(
    lambda row: tag_by_rules(full_text(row), CURRENT_SOLUTION_RULES),
    axis=1,
)
body_df["adoption_barrier_final"] = body_df.apply(
    lambda row: tag_by_rules(full_text(row), ADOPTION_BARRIER_RULES),
    axis=1,
)
body_df["decision_stage"] = body_df.apply(
    lambda row: tag_by_rules(full_text(row), DECISION_STAGE_RULES),
    axis=1,
)
body_df["needed_asset"] = body_df.apply(
    lambda row: tag_by_rules(full_text(row), NEEDED_ASSET_RULES),
    axis=1,
)
body_df["message_angle"] = body_df.apply(
    lambda row: tag_by_rules(full_text(row), MESSAGE_ANGLE_RULES),
    axis=1,
)
body_df["hypothesis_signal"] = body_df.apply(
    lambda row: tag_by_rules(full_text(row), HYPOTHESIS_RULES),
    axis=1,
)


def evidence_strength(row):
    score = 0

    if row.get("본문검증성공", False):
        score += 2

    if row.get("소스타입") in {
        "마케팅커뮤니티",
        "커뮤니티/카페",
        "스타트업/프로덕트커뮤니티",
        "실무자/기업SNS",
    }:
        score += 2

    if row.get("adoption_barrier_final") != "미분류":
        score += 1
    if row.get("current_solution") != "미분류":
        score += 1
    if row.get("persona_final") != "미분류":
        score += 1
    if row.get("광고성추정") is True:
        score -= 1

    if score >= 5:
        return "강"
    if score >= 3:
        return "중"
    return "약"


body_df["evidence_strength"] = body_df.apply(
    evidence_strength,
    axis=1,
)
body_df["use_in_deck"] = body_df["evidence_strength"].apply(
    lambda value: "사용후보"
    if value in {"강", "중"}
    else "보류"
)


# ============================================================
# 11. In-memory summaries
# ============================================================

def count_multitag(dataframe, column):
    tags = []

    for value in dataframe[column].fillna("미분류"):
        for tag in str(value).split(","):
            tag = tag.strip()
            if tag:
                tags.append(tag)

    return (
        pd.Series(tags, name=column)
        .value_counts()
        .rename_axis(column)
        .reset_index(name="count")
    )


summary_persona = count_multitag(body_df, "persona_final")
summary_context = count_multitag(body_df, "company_context")
summary_funnel = count_multitag(body_df, "funnel_problem")
summary_solution = count_multitag(body_df, "current_solution")
summary_barrier = count_multitag(body_df, "adoption_barrier_final")
summary_stage = count_multitag(body_df, "decision_stage")
summary_asset = count_multitag(body_df, "needed_asset")
summary_angle = count_multitag(body_df, "message_angle")
summary_hypothesis = count_multitag(body_df, "hypothesis_signal")


# ============================================================
# 12. Research-question and hypothesis reference tables
# ============================================================

rq_df = pd.DataFrame(
    [
        {
            "리서치질문ID": key,
            "리서치질문": question,
            "확인방법": "질문형 키워드 검색 + 본문 추출 + 태깅",
            "활용": {
                "RQ1_페르소나": "광고 타겟과 LP 카피 좁히기",
                "RQ2_대체방식": "기존 방식 한계와 경쟁/대체재 구조 파악",
                "RQ3_도입장벽": "LP FAQ, 혜택, 상담 메시지 설계",
                "RQ4_선택기준": "리드마그넷과 비교표 설계",
                "RQ5_리드마그넷": "리드 제출 유도 장치 설계",
                "RQ6_시퀀스": "리드 제출 후 CRM 메시지 순서 설계",
            }.get(key, ""),
        }
        for key, question in RESEARCH_QUESTIONS.items()
    ]
)

hypothesis_df = pd.DataFrame(
    [
        {
            "가설": "H1_비교검토층가설",
            "내용": (
                "CRM/마케팅 자동화의 필요성을 완전히 모르는 고객보다, "
                "이미 알림톡·이메일·GA4·엑셀·대형 CRM 사이에서 비교 중인 "
                "고객이 노티플라이 리드 전환 가능성이 높다."
            ),
            "검증키워드": (
                "CRM 솔루션 비교, 마케팅 자동화 툴 비교, 알림톡 자동화, "
                "GA4 리텐션 분석, 엑셀 고객 관리, Braze 대체"
            ),
            "봐야할근거": "본문에서 실제 대체재와 비교 표현이 반복되는지",
        },
        {
            "가설": "H2_개발리소스장벽가설",
            "내용": (
                "초기~중견 B2C 서비스의 마케팅 담당자는 고객 행동 기반 CRM을 "
                "하고 싶지만, 개발자·데이터팀 의존 때문에 실행 속도가 느려진다."
            ),
            "검증키워드": (
                "개발자 없이 CRM, CRM 데이터 연동 어려움, "
                "마케팅 자동화 구축, CRM 세팅 어려움, Braze 세팅"
            ),
            "봐야할근거": "연동, SDK, 개발 리소스, 세팅 부담 언급",
        },
        {
            "가설": "H3_성과확신부족가설",
            "내용": (
                "잠재고객은 CRM 메시지를 보내는 것보다, 보낸 뒤 전환·재방문·"
                "구매에 어떤 영향을 줬는지 확인할 수 있는지를 중요하게 본다."
            ),
            "검증키워드": (
                "CRM 캠페인 성과 측정, 알림톡 전환 추적, 푸시 알림 효과 측정, "
                "리텐션 KPI, CRM 마케팅 KPI"
            ),
            "봐야할근거": "클릭률, 전환율, 재방문율, 구매전환, 코호트, ROI 언급",
        },
        {
            "가설": "H4_내부설득자료부족가설",
            "내용": (
                "실무자는 CRM 도입 필요성을 느껴도 대표/팀장/개발팀을 설득할 "
                "자료가 부족해 도입 검토가 지연된다."
            ),
            "검증키워드": (
                "CRM 도입 제안서, CRM 도입 필요성, 마케팅 자동화 ROI, "
                "CRM 도입 체크리스트, CRM 솔루션 선택 기준"
            ),
            "봐야할근거": "보고, 설득, 제안서, 내부 공유, ROI 근거 언급",
        },
    ]
)

leadmagnet_df = pd.DataFrame(
    [
        {
            "정보성혜택": "무료 CRM 진단",
            "해결장벽": "필요성불확실",
            "적합페르소나": "초기 B2C 마케터/대표",
            "리드폼문구": "우리 팀 CRM 준비도 진단받기",
            "활용단계": "메타 광고 유입/LP 활성화",
        },
        {
            "정보성혜택": "CRM 솔루션 비교 가이드",
            "해결장벽": "비교기준부족",
            "적합페르소나": "비교검토 중인 마케터",
            "리드폼문구": "CRM 툴 선택 기준 확인하기",
            "활용단계": "메타 광고 유입/LP 활성화",
        },
        {
            "정보성혜택": "리텐션 개선 사례집",
            "해결장벽": "성과불확실",
            "적합페르소나": "그로스/CRM 담당자",
            "리드폼문구": "리텐션 개선 사례 받아보기",
            "활용단계": "메타 광고 유입/리드 제출 후 CRM",
        },
        {
            "정보성혜택": "첫 캠페인 템플릿",
            "해결장벽": "세팅난이도",
            "적합페르소나": "실무 마케터",
            "리드폼문구": "첫 CRM 캠페인 템플릿 받기",
            "활용단계": "LP 활성화/리드 제출 후 CRM",
        },
        {
            "정보성혜택": "팀 공유용 도입 PDF",
            "해결장벽": "내부설득",
            "적합페르소나": "실무자/팀 리드",
            "리드폼문구": "내부 공유용 CRM 도입 자료 받기",
            "활용단계": "리드 제출 후 상담 전환",
        },
        {
            "정보성혜택": "개발자 없이 도입 체크리스트",
            "해결장벽": "개발의존",
            "적합페르소나": "개발 리소스 부족한 팀",
            "리드폼문구": "개발 없이 가능한 CRM 도입 체크하기",
            "활용단계": "LP 활성화/1:1 상담 전환",
        },
    ]
)


# ============================================================
# 13. Public-version output
# ============================================================

# No CSV/XLSX files are written or downloaded in this public repository version.
# The analysis objects remain in memory for inspection in a local Python session.

print("\nTop adoption barriers:")
print(summary_barrier.head(10))

print("\nTop message angles:")
print(summary_angle.head(10))

print("\nTop hypothesis signals:")
print(summary_hypothesis.head(10))

preview_columns = [
    "제목",
    "소스타입",
    "키워드그룹",
    "본문검증성공",
    "본문길이",
    "persona_final",
    "current_solution",
    "adoption_barrier_final",
    "needed_asset",
    "hypothesis_signal",
    "evidence_strength",
]

available_preview_columns = [
    col for col in preview_columns if col in body_df.columns
]

print("\nValidated candidate preview:")
print(body_df[available_preview_columns].head(20))
