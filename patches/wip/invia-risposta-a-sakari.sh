#!/usr/bin/env bash
#
# Spedisce la risposta a Sakari Ailus sul thread della v2 dell'invio 1.
#
#   ./invia-risposta-a-sakari.sh --prova    mostra il messaggio, NON spedisce
#   ./invia-risposta-a-sakari.sh            chiede conferma e spedisce
#
# Il corpo del messaggio sta in risposta-a-sakari-v2.txt, a fianco di questo
# script: e' il testo approvato, lo script non lo modifica, ci mette solo le
# intestazioni.
#
# La password per le app di Google (16 caratteri) NON e' salvata da nessuna
# parte: viene chiesta a ogni invio, digitata in chiaro non si vede, e non
# passa mai dalla riga di comando (sarebbe visibile con `ps`).

set -euo pipefail

CARTELLA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORPO="$CARTELLA/risposta-a-sakari-v2.txt"

PROVA=0
if [[ "${1:-}" == "--prova" || "${1:-}" == "--dry-run" ]]; then
	PROVA=1
fi

if [[ ! -f "$CORPO" ]]; then
	echo "ERRORE: non trovo il corpo del messaggio: $CORPO" >&2
	exit 1
fi

# --- Destinatari -------------------------------------------------------
# Risposta a tutti, esattamente la lista del messaggio di Sakari (verificata
# funzionante: la v2 e' passata con questi indirizzi, tutti Result: 250).
export MAIL_A="Sakari Ailus <sakari.ailus@linux.intel.com>"
export MAIL_CC="linux-media@vger.kernel.org, mchehab@kernel.org, hverkuil@kernel.org, antti.laakso@linux.intel.com, linux-kernel@vger.kernel.org, nicfio@gmail.com"

# --- Aggancio al thread ------------------------------------------------
# In-Reply-To: il messaggio di Sakari del 12/09.
# References: la catena completa, cioe' la cover letter della v2 e poi lui.
# Senza questi due il messaggio aprirebbe un thread nuovo e su lore
# sembrerebbe scollegato dalla discussione.
export MAIL_IN_REPLY_TO="<aqUoLr0JFGEBiJIf@kekkonen.localdomain>"
export MAIL_REFERENCES="<20260911194854.78894-1-nicfio@gmail.com> <aqUoLr0JFGEBiJIf@kekkonen.localdomain>"
export MAIL_OGGETTO="Re: [PATCH v2 0/3] media: Two oopses and a hang when unbinding a streaming sensor"

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
