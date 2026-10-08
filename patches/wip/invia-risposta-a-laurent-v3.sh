#!/usr/bin/env bash
#
# Spedisce la risposta a Laurent Pinchart sulla v3 1/2 (ritiro della serie v3).
#
#   ./invia-risposta-a-laurent-v3.sh --prova    mostra il messaggio, NON spedisce
#   ./invia-risposta-a-laurent-v3.sh            chiede conferma e spedisce
#
# Il corpo del messaggio sta in risposta-a-laurent-v3.txt, a fianco di questo
# script: e' il testo approvato, lo script non lo modifica, ci mette solo le
# intestazioni.
#
# La password per le app di Google (16 caratteri) NON e' salvata da nessuna
# parte: viene chiesta a ogni invio, digitata in chiaro non si vede, e non
# passa mai dalla riga di comando (sarebbe visibile con `ps`).

set -euo pipefail

CARTELLA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORPO="$CARTELLA/risposta-a-laurent-v3.txt"

PROVA=0
if [[ "${1:-}" == "--prova" || "${1:-}" == "--dry-run" ]]; then
	PROVA=1
fi

if [[ ! -f "$CORPO" ]]; then
	echo "ERRORE: non trovo il corpo del messaggio: $CORPO" >&2
	exit 1
fi

# --- Destinatari -------------------------------------------------------
# Risposta a tutti sul messaggio di Laurent: lui in To, in Cc gli stessi
# Cc della v3 (Sakari, Mauro, Hans, Nguyen, le due liste) piu' noi.
export MAIL_A="Laurent Pinchart <laurent.pinchart@ideasonboard.com>"
export MAIL_CC="Sakari Ailus <sakari.ailus@linux.intel.com>, mchehab@kernel.org, hverkuil@kernel.org, ngocthang2710.1999@gmail.com, linux-media@vger.kernel.org, linux-kernel@vger.kernel.org, nicfio@gmail.com"

# --- Aggancio al thread ------------------------------------------------
# In-Reply-To: la risposta di Laurent dell'08/10 05:48 UTC (letta via NNTP).
# References: lettera v3, patch 1/2, Laurent.
export MAIL_IN_REPLY_TO="<20261008054842.GB683793@killaraus.ideasonboard.com>"
export MAIL_REFERENCES="<20261008042600.275884-1-nicfio@gmail.com> <20261008042600.275884-2-nicfio@gmail.com> <20261008054842.GB683793@killaraus.ideasonboard.com>"
export MAIL_OGGETTO="Re: [PATCH v3 1/2] media: v4l2-subdev: Fix NULL pointer dereference in subdev_open()"

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
