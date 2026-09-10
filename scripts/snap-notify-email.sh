#!/usr/bin/env bash
# Send snap workflow notifications to CONTACT_EMAIL (login node; never fails the caller).
#
# Usage:
#   snap-notify-email.sh --to EMAIL --subject SUBJECT --body TEXT

TO=""
SUBJECT=""
BODY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to) TO="$2"; shift 2 ;;
    --subject) SUBJECT="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,5p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 0 ;;
  esac
done

if [[ -z "${TO}" || -z "${SUBJECT}" ]]; then
  echo "snap-notify-email.sh: --to and --subject are required; skipped" >&2
  exit 0
fi

if command -v mailx >/dev/null 2>&1; then
  mailx -s "${SUBJECT}" "${TO}" <<< "${BODY}" && exit 0
fi
if command -v mail >/dev/null 2>&1; then
  mail -s "${SUBJECT}" "${TO}" <<< "${BODY}" && exit 0
fi

echo "snap-notify-email.sh: mailx/mail unavailable; skipped: ${SUBJECT}" >&2
exit 0
