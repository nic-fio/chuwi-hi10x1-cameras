#!/usr/bin/env bash
#
# Spedisce la recensione della patch 09/21 della serie IPU6 di Sakari Ailus
# ("IPU6 multi-stream and metadata support preparation", v3 del 22/09/2026; solo il reperto 2, quello del collegamento spento).
#
#   ./invia-recensione-09-21-v3.sh --prova    mostra il messaggio, NON spedisce
#   ./invia-recensione-09-21-v3.sh            chiede conferma e spedisce
#
# Il corpo del messaggio sta in recensione-09-21-v3.txt, a fianco di questo
# script: e' il testo approvato, lo script non lo modifica, ci mette solo le
# intestazioni.
#
# La password per le app di Google (16 caratteri) NON e' salvata da nessuna
# parte: viene chiesta a ogni invio, digitata in chiaro non si vede, e non
# passa mai dalla riga di comando (sarebbe visibile con `ps`).

set -euo pipefail

CARTELLA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORPO="$CARTELLA/recensione-09-21-v3.txt"

PROVA=0
if [[ "${1:-}" == "--prova" || "${1:-}" == "--dry-run" ]]; then
	PROVA=1
fi

if [[ ! -f "$CORPO" ]]; then
	echo "ERRORE: non trovo il corpo del messaggio: $CORPO" >&2
	exit 1
fi

# --- Destinatari -------------------------------------------------------
# Risposta a tutti sulla lista esatta della patch 09/21, piu' se stessi in
# copia per avere la conferma di recapito. I due indirizzi Intel che nel
# 2026 rimbalzavano (bingbu.cao, tian.shu.qiu) qui non ci sono.
export MAIL_A="Sakari Ailus <sakari.ailus@linux.intel.com>"
export MAIL_CC="linux-media@vger.kernel.org, dongcheng.yan@intel.com, mehdi.djait@linux.intel.com, ong.hock.yu@intel.com, khai.wen.ng@intel.com, antti.laakso@linux.intel.com, manik.bajpai@intel.com, divyamani.tripathi@intel.com, nicfio@gmail.com"

# --- Aggancio al thread ------------------------------------------------
# In-Reply-To: la patch 09/21 stessa, cosi' il commento finisce sotto la
# patch giusta e non sotto la cover.
# References: prima la cover 00/21, poi la 09/21.
export MAIL_IN_REPLY_TO="<20260922120538.896684-10-sakari.ailus@linux.intel.com>"
export MAIL_REFERENCES="<20260922120538.896684-1-sakari.ailus@linux.intel.com> <20260922120538.896684-10-sakari.ailus@linux.intel.com>"
export MAIL_OGGETTO="Re: [PATCH v3 09/21] media: ipu6: Start streaming once all streams have started, stop when not"

# --- Impostazioni SMTP: lette dal git, le stesse che hanno spedito la v2 ---
export MAIL_DA="$(git config --get sendemail.from || echo 'Nicola Fiorillo <nicfio@gmail.com>')"
export MAIL_SERVER="$(git config --get sendemail.smtpserver || echo smtp.gmail.com)"
export MAIL_PORTA="$(git config --get sendemail.smtpserverport || echo 587)"
export MAIL_UTENTE="$(git config --get sendemail.smtpuser || echo nicfio@gmail.com)"
export MAIL_CORPO="$CORPO"
export MAIL_PROVA="$PROVA"

# --- Costruzione e anteprima -------------------------------------------
COSTRUISCI=$(cat <<'PY'
import email.utils, os, smtplib, sys
from email.message import EmailMessage

corpo = open(os.environ["MAIL_CORPO"], encoding="utf-8").read()

m = EmailMessage()
m["From"] = os.environ["MAIL_DA"]
m["To"] = os.environ["MAIL_A"]
m["Cc"] = os.environ["MAIL_CC"]
m["Subject"] = os.environ["MAIL_OGGETTO"]
m["Date"] = email.utils.formatdate(localtime=True)
m["Message-ID"] = email.utils.make_msgid(domain="gmail.com")
m["In-Reply-To"] = os.environ["MAIL_IN_REPLY_TO"]
m["References"] = os.environ["MAIL_REFERENCES"]
m["MIME-Version"] = "1.0"
try:
    corpo.encode("ascii")
    m.set_content(corpo, cte="7bit")
except UnicodeEncodeError:
    m.set_content(corpo, charset="utf-8", cte="8bit")

if os.environ["MAIL_PROVA"] == "1":
    sys.stdout.write(m.as_string())
    sys.exit(0)

pw = os.environ.get("MAIL_PASSWORD", "")
if not pw:
    print("ERRORE: password vuota, non spedisco.", file=sys.stderr)
    sys.exit(1)

destinatari = [a for _, a in email.utils.getaddresses(
    [m["To"], m["Cc"]]) if a]

s = smtplib.SMTP(os.environ["MAIL_SERVER"], int(os.environ["MAIL_PORTA"]),
                 timeout=60)
try:
    s.ehlo()
    s.starttls()
    s.ehlo()
    s.login(os.environ["MAIL_UTENTE"], pw)
    rifiutati = s.send_message(m, to_addrs=destinatari)
finally:
    try:
        s.quit()
    except Exception:
        pass

if rifiutati:
    print("ATTENZIONE, indirizzi rifiutati dal server:", file=sys.stderr)
    for indirizzo, errore in rifiutati.items():
        print("  %s -> %s" % (indirizzo, errore), file=sys.stderr)
    sys.exit(1)

print("SPEDITO.")
print("Message-ID: %s" % m["Message-ID"])
print("Destinatari (%d): %s" % (len(destinatari), ", ".join(destinatari)))
PY
)

echo "================= MESSAGGIO CHE STO PER SPEDIRE ================="
MAIL_PROVA=1 python3 -c "$COSTRUISCI"
echo "================================================================"
echo

if [[ "$PROVA" == "1" ]]; then
	echo "(prova: non ho spedito niente)"
	exit 0
fi

read -r -p "Spedisco questo messaggio? Scrivi SI per confermare: " RISPOSTA
if [[ "$RISPOSTA" != "SI" ]]; then
	echo "Annullato, non ho spedito niente."
	exit 1
fi

echo
echo "Password per le app di Google (16 caratteri, NON quella normale)."
echo "Si prende da myaccount.google.com/apppasswords - digitando non si vede."
read -r -s -p "Password: " MAIL_PASSWORD
export MAIL_PASSWORD
echo
echo

python3 -c "$COSTRUISCI"
unset MAIL_PASSWORD
