#!/usr/bin/env bash
# Test senza root né systemd: cb-idle con finti systemctl/date/curl, gli helper
# di lib/common.sh, i template systemd, l'elenco degli step e cb-wake-proxy.
#
#   tests/run.sh

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
good() { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n' "$*"; }
fails() { ! "$@"; }
check() { local what=$1; shift; if "$@"; then good; else bad "$what"; fi; }
section() { printf -- '-- %s\n' "$*"; }

# ---------------------------------------------------------------- cb-idle

export FAKE_LOG=$TMP/calls FAKE_TABS=$TMP/tabs XDG_RUNTIME_DIR=$TMP/run
export CB_IDLE_CONF=$TMP/idle.conf
mkdir -p "$XDG_RUNTIME_DIR"

# idle CONF... : scrive la configurazione, azzera il registro e lancia cb-idle.
idle() {
  printf '%s\n' "$@" >"$CB_IDLE_CONF"
  : >"$FAKE_LOG"
  PATH="$ROOT/tests/stubs:$PATH" "$ROOT/bin/cb-idle" ${IDLE_ARGS:+"$IDLE_ARGS"} >"$TMP/out" 2>&1
}
called() { grep -qF -- "$1" "$FAKE_LOG"; }
not_called() { ! called "$1"; }
said() { grep -qF -- "$1" "$TMP/out"; }

section 'cb-idle --check'
IDLE_ARGS=--check
check 'configurazione vuota valida' idle ''
check 'idle stop in minuti' idle 'CB_CHROME_IDLE_STOP=30'
check 'finestre valide' idle 'CB_CHROME_KEEP_AWAKE="Mon..Fri 07:00-18:00; Sat,Sun 09:00-12:00; 22:00-23:59"'
check 'giorni a cavallo della settimana' idle 'CB_CHROME_KEEP_AWAKE="Fri..Mon 08:00-09:00"'
check 'URL http(s)' idle 'CB_CHROME_KEEP_AWAKE_URLS="https://claude.ai/ http://localhost:3000"'
check 'idle stop non numerico rifiutato' fails idle 'CB_CHROME_IDLE_STOP=soon'
check 'idle stop 0 rifiutato' fails idle 'CB_CHROME_IDLE_STOP=0'
check 'giorno sconosciuto rifiutato' fails idle 'CB_CHROME_KEEP_AWAKE="Mon..Fry 07:00-18:00"'
said "bad day" || bad 'messaggio per il giorno sbagliato'
check 'orario non valido rifiutato' fails idle 'CB_CHROME_KEEP_AWAKE="Mon 7:00-18:00"'
check 'ore 24 rifiutate' fails idle 'CB_CHROME_KEEP_AWAKE="Mon 08:00-24:00"'
check 'finestra oltre mezzanotte rifiutata' fails idle 'CB_CHROME_KEEP_AWAKE="Mon 22:00-02:00"'
said "split windows" || bad 'messaggio per la finestra oltre mezzanotte'
check 'testo in più rifiutato' fails idle 'CB_CHROME_KEEP_AWAKE="Mon 08:00-09:00 extra"'
check 'URL non http rifiutato' fails idle 'CB_CHROME_KEEP_AWAKE_URLS="ftp://example.com"'
check 'fuso orario sconosciuto rifiutato' fails idle 'CB_TIMEZONE=Mars/Olympus'
IDLE_ARGS=

section 'cb-idle: finestre keep-awake'
echo '[]' >"$FAKE_TABS"
export FAKE_ACTIVE=no
FAKE_NOW='2026-11-16 10:00' idle 'CB_CHROME_KEEP_AWAKE="Mon..Fri 07:00-18:00"'   # lunedì
check 'nella finestra avvia il browser' called 'start cb-chrome.service'
FAKE_NOW='2026-11-16 18:00' idle 'CB_CHROME_KEEP_AWAKE="Mon..Fri 07:00-18:00"'
check "l'ora di fine è esclusa" not_called 'start'
FAKE_NOW='2026-11-15 10:00' idle 'CB_CHROME_KEEP_AWAKE="Mon..Fri 07:00-18:00"'   # domenica
check 'domenica fuori da Mon..Fri' not_called 'start'
FAKE_NOW='2026-11-15 08:30' idle 'CB_CHROME_KEEP_AWAKE="Fri..Mon 08:00-09:00"'
check 'Fri..Mon include la domenica' called 'start cb-chrome.service'
FAKE_NOW='2026-11-18 08:30' idle 'CB_CHROME_KEEP_AWAKE="Fri..Mon 08:00-09:00"'   # mercoledì
check 'Fri..Mon esclude il mercoledì' not_called 'start'
FAKE_NOW='2026-11-15 23:30' idle 'CB_CHROME_KEEP_AWAKE="Mon..Fri 07:00-18:00; 23:00-23:59"'
check 'finestra senza giorni = tutti i giorni' called 'start cb-chrome.service'
FAKE_ACTIVE=yes FAKE_NOW='2026-11-16 10:00' idle 'CB_CHROME_KEEP_AWAKE="Mon 07:00-18:00"'
check 'browser già attivo: nessun riavvio' not_called 'start'

section 'cb-idle: schede da tenere aperte'
export FAKE_ACTIVE=yes
rm -f "$XDG_RUNTIME_DIR/cb-keep-awake-tabs"
echo '[{"id":"altra"}]' >"$FAKE_TABS"
conf=('CB_CHROME_KEEP_AWAKE="Mon 07:00-18:00"' 'CB_CHROME_KEEP_AWAKE_URLS="https://a.example/ https://b.example/"')
FAKE_NOW='2026-11-16 10:00' idle "${conf[@]}"
check 'apre le due pagine' test "$(grep -c 'json/new' "$FAKE_LOG")" = 2
FAKE_NOW='2026-11-16 10:01' idle "${conf[@]}"
check 'non le riapre se sono ancora aperte' not_called 'json/new'
jq 'map(select(.id != "tab2"))' "$FAKE_TABS" >"$TMP/t" && mv "$TMP/t" "$FAKE_TABS"
FAKE_NOW='2026-11-16 10:02' idle "${conf[@]}"
check 'riapre solo la pagina chiusa' test "$(grep -c 'json/new' "$FAKE_LOG")" = 1
called 'b.example' || called 'a.example' || bad 'URL della pagina riaperta'

section 'cb-idle: stop per inattività'
export FAKE_ACTIVE=yes FAKE_ACTIVE_SINCE='2026-11-16 08:00'
rm -f "$XDG_RUNTIME_DIR/cb-activity"
FAKE_NOW='2026-11-16 10:00' idle 'CB_CHROME_IDLE_STOP=30'
check 'inattivo da 2 ore: stop' called 'stop cb-chrome.service'
FAKE_NOW='2026-11-16 08:20' idle 'CB_CHROME_IDLE_STOP=30'
check 'avviato da 20 minuti: resta acceso' not_called 'stop'
touch -d '2026-11-16 09:45' "$XDG_RUNTIME_DIR/cb-activity"
FAKE_NOW='2026-11-16 10:00' idle 'CB_CHROME_IDLE_STOP=30'
check 'usato 15 minuti fa: resta acceso' not_called 'stop'
FAKE_NOW='2026-11-16 10:15' idle 'CB_CHROME_IDLE_STOP=30'
check 'usato 30 minuti fa: stop' called 'stop cb-chrome.service'
FAKE_NOW='2026-11-16 12:00' idle 'CB_CHROME_IDLE_STOP=off'
check 'idle stop off: nessuno stop' not_called 'stop'
FAKE_ACTIVE=no FAKE_NOW='2026-11-16 12:00' idle 'CB_CHROME_IDLE_STOP=30'
check 'browser già spento: niente da fare' not_called 'stop'
FAKE_NOW='2026-11-16 12:00' idle 'CB_CHROME_IDLE_STOP=30' 'CB_CHROME_KEEP_AWAKE="Mon 07:00-18:00"'
check 'nella finestra keep-awake non si spegne' not_called 'stop'

# ---------------------------------------------------------- lib/common.sh

section 'lib/common.sh'
(
  # shellcheck source=lib/common.sh
  . "$ROOT/lib/common.sh"
  owner="$(id -un):$(id -gn)"
  f=$TMP/conf/sub/file
  echo uno | ensure_file "$f" 600 "$owner" 2>/dev/null || exit 11
  echo uno | ensure_file "$f" 600 "$owner" 2>/dev/null && exit 12
  [[ $(stat -c %a "$f") == 600 ]] || exit 13
  echo due | ensure_file "$f" 644 "$owner" 2>/dev/null || exit 14
  [[ $(cat "$f") == due && $(stat -c %a "$f") == 644 ]] || exit 15
  ensure_line "$TMP/lines" 'export A=1' 2>/dev/null
  ensure_line "$TMP/lines" 'export A=1' 2>/dev/null
  ensure_line "$TMP/lines" '-x' 2>/dev/null
  [[ $(cat "$TMP/lines") == $'export A=1\n-x' ]] || exit 16
)
case $? in
  0) good ;;
  11) bad 'ensure_file: prima scrittura' ;;
  12) bad 'ensure_file: contenuto uguale deve restituire 1' ;;
  13) bad 'ensure_file: permessi' ;;
  14|15) bad 'ensure_file: aggiornamento' ;;
  16) bad 'ensure_line: idempotente' ;;
  *) bad 'lib/common.sh' ;;
esac

section 'template systemd e cloud-init'
(
  . "$ROOT/lib/common.sh"
  cb_home() { echo /home/claude; }
  cb_uid() { echo 1000; }
  CB_USER=claude CB_DISPLAY=:99 CB_SCREEN=1280x800x24 CB_CDP_PORT=9222 CB_CDP_BACKEND_PORT=9223
  CB_CHROME_CDP_PORT=9223 CB_VNC_PORT=5900 CB_VNC_BACKEND_PORT=5901 CB_X11VNC_PORT=5901
  CB_NOVNC_PORT=6080 CB_MEMORY_MAX=3G CB_CPU_QUOTA=200% CB_MEMORY_SWAP_MAX=1G
  CB_CHROME_RESTART=04:30 CB_CHROME_MEMORY_HIGH=2G CB_RC_NAME=vps CB_RC_PERMISSION_MODE=default
  rc=0
  for t in "$ROOT"/systemd/user/* "$ROOT"/systemd/system/*; do
    out=$(render "$t")
    if grep -o '@[A-Z_]*@' <<<"$out" >/dev/null; then
      echo "  FAIL $(basename "$t"): segnaposto non sostituiti: $(grep -o '@[A-Z_]*@' <<<"$out" | sort -u | tr '\n' ' ')"
      rc=1
    fi
  done
  render "$ROOT/systemd/user/cb-chrome.service" | grep -q -- '1280,800' || { echo '  FAIL CB_WINDOW_SIZE'; rc=1; }
  exit $rc
) && good || fail=$((fail + 1))

section 'install.sh --list'
steps=$(bash "$ROOT/install.sh" --list 2>/dev/null)
files=$(cd "$ROOT/lib" && printf '%s\n' [0-9][0-9]-*.sh | sed -E 's/^[0-9]+-(.*)\.sh$/\1/')
check 'uno step per ogni lib/NN-*.sh, in ordine' test "$steps" = "$files"
for s in $steps; do
  grep -qE "^step_$s\(\)" "$ROOT"/lib/[0-9][0-9]-"$s".sh || bad "lib/*-$s.sh non definisce step_$s"
done
check 'opzione sconosciuta rifiutata' fails bash "$ROOT/install.sh" --boh 2>/dev/null

# ---------------------------------------------------------- cb-wake-proxy

section 'cb-wake-proxy'
if python3 "$ROOT/tests/test_wake_proxy.py" >"$TMP/py" 2>&1; then good; else bad 'cb-wake-proxy'; sed 's/^/    /' "$TMP/py"; fi

echo "$pass controlli ok, $fail falliti"
[[ $fail -eq 0 ]]
