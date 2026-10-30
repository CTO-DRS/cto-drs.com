#!/usr/bin/env bash
# ============================================================================
#  spaceship-dns.sh — توجيه cto-drs.com إلى GitHub Pages عبر Spaceship API
#
#  الاستخدام:
#    SS_API_KEY=xxxx SS_API_SECRET=yyyy bash spaceship-dns.sh
#  أو خزّن المفتاحين في ملفين:
#    ~/.spaceship_key  و  ~/.spaceship_secret
#
#  ماذا يفعل:
#    1) يقرأ السجلات الحالية للنطاق
#    2) يستبدل سجلات A للجذر بعناوين GitHub Pages الأربعة
#    3) يستبدل CNAME الخاص بـ www ليشير إلى CTO-DRS.github.io
#    4) يحافظ على بقية السجلات (MX، TXT، …) كما هي
#    5) يعرض الحالة النهائية بعد التحديث
#
#  ملاحظة: لا يحتوي هذا السكربت على أي مفاتيح — يقرؤها من البيئة/الملفات فقط.
# ============================================================================
set -euo pipefail

DOMAIN="cto-drs.com"
API="https://spaceship.dev/api/v1"

# ---------- credentials ----------
KEY="${SS_API_KEY:-}"
SECRET="${SS_API_SECRET:-}"
if [ -z "$KEY" ] && [ -f "$HOME/.spaceship_key" ];    then KEY=$(cat "$HOME/.spaceship_key");    fi
if [ -z "$SECRET" ] && [ -f "$HOME/.spaceship_secret" ]; then SECRET=$(cat "$HOME/.spaceship_secret"); fi
if [ -z "$KEY" ] || [ -z "$SECRET" ]; then
  echo "✖ ينقص المفتاحان: مرّرهما كـ SS_API_KEY و SS_API_SECRET أو ضعهما في ~/.spaceship_key و ~/.spaceship_secret"
  exit 1
fi

AUTH=(-H "X-API-Key: $KEY" -H "X-API-Secret: $SECRET" -H "Content-Type: application/json")

command -v jq >/dev/null 2>&1 || { echo "✖ يلزم تثبيت jq"; exit 1; }

# ---------- 1) current records ----------
echo "⏳ قراءة السجلات الحالية…"
CURRENT=$(curl -sS -m 30 "${AUTH[@]}" "$API/domains/$DOMAIN/records")
echo "$CURRENT" | jq -r '.records[] | "\(.type)\t\(.name)\t\(.value)"' | sed 's/^/   /' || true

# ---------- 2) merge ----------
# GitHub Pages apex IPs (https://docs.github.com/pages)
PAGES_HOST="CTO-DRS.github.io"

# احتفظ بكل السجلات غير المتضاربة (ليست A@ وليست CNAME www)
KEPT=$(echo "$CURRENT" | jq -c '
  [ .records[]
  | select(
      ((.type=="A")     and (.name=="@" or .name=="" or .name=="'"$DOMAIN"'.")) == false and
      ((.type=="CNAME") and (.name=="www" or .name=="www.'"$DOMAIN"'.")) == false
    )
  ]')

PAYLOAD=$(jq -n --argjson kept "$KEPT" '{ force: true, records: (
  $kept + [
    {type:"A",    name:"@",  value:"185.199.108.153", ttl:3600},
    {type:"A",    name:"@",  value:"185.199.109.153", ttl:3600},
    {type:"A",    name:"@",  value:"185.199.110.153", ttl:3600},
    {type:"A",    name:"@",  value:"185.199.111.153", ttl:3600},
    {type:"CNAME",name:"www",value:"CTO-DRS.github.io", ttl:3600}
  ]) }')

# ---------- 3) save ----------
echo "⏳ حفظ السجلات الجديدة…"
RESP=$(curl -sS -m 30 -w "\n%{http_code}" -X PUT "${AUTH[@]}" "$API/domains/$DOMAIN/records" -d "$PAYLOAD")
HTTP=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
if [ "$HTTP" != "200" ]; then
  echo "✖ فشل الحفظ (HTTP $HTTP): $BODY"
  exit 1
fi
echo "✔ حُفظت السجلات"

# ---------- 4) verify ----------
echo "⏳ التحقق النهائي…"
sleep 3
curl -sS -m 30 "${AUTH[@]}" "$API/domains/$DOMAIN/records" | jq -r '.records[] | "\(.type)\t\(.name)\t\(.value)"' | sed 's/^/   /'

cat <<'TIP'

──────────────────────────────────────────────────────────────
الخطوة الأخيرة بعد انتشار DNS (5–30 دقيقة):
  1) افتح https://cto-drs.com — يجب أن يظهر الموقع
  2) فعّل HTTPS من GitHub: Settings → Pages → Enforce HTTPS
     (يظهر الخيار بعد إصدار الشهادة تلقائياً)
──────────────────────────────────────────────────────────────
TIP
