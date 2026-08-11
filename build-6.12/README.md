# build-6.12 — provare i driver sul kernel che gira

I due driver sono scritti contro **mainline 7.2**. Su questa macchina gira il
kernel **Debian 6.12.86+deb13-amd64**, l'unico che porta `pinctrl-alderlake` e
quindi l'unico su cui i sensori si accendono. Questa directory tiene insieme le
due cose senza toccare i sorgenti.

**Regola che vale piu' di tutto il resto: i `.c` qui dentro sono copie
bit-identiche di `/home/nicfio/linux`.** Le differenze di API stanno tutte in
`compat-6.12.h`, incluso con `-include`. Cosi' cio' che gira e' esattamente il
codice che verra' inviato upstream, e non una sua variante addomesticata.

Oggi `compat-6.12.h` contiene **una sola** riga di sostanza:
`devm_v4l2_sensor_clk_get()` non esiste nella 6.12, e diventa
`devm_clk_get_optional()`. Su questa piattaforma il clock lo registra `int3472`
con `con_id` nullo, che matcha qualunque `con_id` richiesto.

## Cosa c'e'

| File | Origine |
|---|---|
| `gc5035.c`, `gc8034.c` | copie da `/home/nicfio/linux/drivers/media/i2c/` |
| `ipu-bridge.c` | `v6.12.86` da git.kernel.org, **piu' la sola Serie 3** |
| `compat-6.12.h`, `Makefile`, `carica.sh` | solo per la prova locale, non da inviare |

`ipu-bridge` va ricompilato perche' la tabella `ipu_supported_sensors[]` e'
statica: senza le due voci `GCTI*` non nasce il grafo fwnode CSI-2, e i driver
restano in probe rimandata con `waiting for endpoint node`.

## Prerequisiti

Header della versione **esatta** del kernel in esecuzione. Il kernel Debian qui
non e' installato come pacchetto, quindi `apt install linux-headers-...`
tirerebbe dentro anche `linux-image`: gli header sono stati estratti a mano,
senza far toccare a dpkg ne' `/boot` ne' la ESP.

```bash
apt-get download linux-headers-$(uname -r) \
                 linux-headers-6.12.86+deb13-common \
                 linux-kbuild-6.12.86+deb13
for d in *.deb; do sudo dpkg-deb -x "$d" /; done
sudo ln -sfn /usr/src/linux-headers-$(uname -r) /lib/modules/$(uname -r)/build
sudo apt-get install dwarves v4l-utils i2c-tools
```

`dwarves` serve per `pahole`: senza, la build muore sul passo BTF.

## Uso

```bash
make                    # gc5035.ko, gc8034.ko, ipu-bridge.ko
sudo ./carica.sh        # scarica ipu6, mette il bridge patchato, carica i driver
sudo ./carica.sh -d     # torna allo stato di Debian
```

Poi:

```bash
media-ctl -p                                  # gc5035 e gc8034 devono comparire
../scripts/cattura.sh gc5035 5                # 5 fotogrammi
../scripts/raw-to-png.py gc5035.raw 2592 1944 grbg
```

`cattura.sh` ricava da solo entita', CSI2 e nodo `/dev/videoN`: **non vanno
scritti a mano**, cambiano da un boot all'altro.

## Cosa non fa

Non installa niente e **non sopravvive a un riavvio**. E' voluto: il traguardo
del progetto e' il tree di Linus, non una macchina che funziona in locale. Se
un giorno servisse la persistenza, la strada e' DKMS — ma sarebbe tempo tolto
all'invio upstream.

Nota: i moduli non sono firmati, quindi il kernel si marca `tainted`. Non e' un
problema qui e non lascia tracce dopo il riavvio.

Risultati della prima prova: `docs/08-prova-hardware.md`.
