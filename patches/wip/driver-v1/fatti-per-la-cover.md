# Fatti per la cover letter e i messaggi di commit

Per Nic. Non è un testo da copiare: sono i fatti, controllati l'8/10 sera
sulla serie finale. La cover e i messaggi li scrivi tu con parole tue.

Serie: `35478bd01..7b3ed03b4`, 3 patch, base media `next` `8e26d4c20`
(ancora la punta di `next` alle 19 dell'8/10).

1. gc5035, driver
2. gc8034, driver
3. ipu-bridge, le due voci ACPI

Niente binding DT: i driver sono solo ACPI.


## 1. Frasi della bozza (`cover.txt`) che oggi sono sbagliate

**«The register sequences are reproduced unmodified».** Non più vero.
Le tabelle sono state accorciate:
- gc5035: da 323 a 160 scritture. Una sola tabella: quella iniziale veniva
  quasi tutta riscritta da quella del modo.
- gc8034: da 233 a 182. Tolte le impostazioni del modo ridotto (binned)
  che il BSP scrive e poi sovrascrive subito.
- In tutte e due sono tolti i registri che i controlli scrivono già
  (esposizione, guadagno, VBLANK).
- Lo stato finale dei registri è stato confrontato pagina per pagina con
  quello delle tabelle originali: identico, salvo quei registri.

**«The vendor code is wrong» per il gc5035.** Non è esatto. Il valore
438 MHz era giusto per il clock di 24 MHz: 24 × 0x49 / 4 = 438. Intel è
passata a 19,2 MHz e ha cambiato la PLL (0xf8 = 0x58), ma ha lasciato la
costante vecchia. Con 0x58: 19,2 × 0x58 / 4 = 422,4 MHz. Ora il driver
calcola LINK_FREQ dalla PLL, non la copia.

**Per il gc8034 la frase va bene**, ma è più giusto dire che il valore del
BSP (336 MHz) vale per 24 MHz. A 19,2 MHz tutto va a 0,8 volte: 268,8 MHz,
24 fps invece di 30.

**«Tomasz Figa ... GC5035 power sequence ... the GC8034 one follows the
Rockchip driver».** Va bene, è ancora così.

**«The size of the full pixel arrays is not documented, so the readout
windows are reported as the native sizes».** Va bene, è ancora così:
NATIVE_SIZE = finestra letta (2608x1960 e 3284x2464), crop (8,8) e (9,8).

**Sezione Testing piena di [[DA PROVA]]:** i numeri sono qui sotto.

**Elenco delle patch in testa alla vecchia `cover-letter.txt` di agosto
(5 patch, binding, 45/46):** non usarla, è superata.


## 2. Numeri delle prove (8/10, 19:47, serie finale)

Kernel: `next` `8e26d4c20` + la serie finale (`7.3.0-rc1-intelcam-debug-g7b3ed03b4963`),
build di debug (KASAN, lockdep).
Tablet CHUWI Hi10 X1, Intel N100, IPU6. Uscita in
`data/prova-20261008-194731/`.

Frame rate (atteso dalle costanti del driver, misurato):
- gc5035: 28,82 contro 28,81 fps
- gc8034: 24,00 contro 24,01 fps
- con VBLANK 2000: gc5035 14,67 contro 14,67; gc8034 13,47 contro 13,47.
  Quindi anche l'offset di 36 righe del gc8034 torna: lo scarto è meno di
  una riga (-0,8).

Guadagno analogico, dal primo all'ultimo gradino:
- gc5035: 17 gradini, chiesto 15,6x, misurato 15,35x (1,6%)
- gc8034: 7 gradini, chiesto 7,66x, misurato 7,74x (1,0%)

Altre verifiche:
- esposizione e VBLANK scritti a 16 bit e riletti dal sensore: giusti
- finestra, crop e lunghezza di riga riletti dal sensore a stream acceso:
  uguali alle costanti del driver
- test pattern gc5035 («Test Chart»): due fotogrammi uguali al 100%
- 10 cicli di bind/unbind per sensore: tutti e due ancora funzionanti,
  nessun errore né avviso dai driver. Nel log ci sono solo «supply dvdd /
  dovdd not found, using dummy regulator», uno per ogni probe: lo scrive il
  core dei regolatori, ed è giusto, perché su questo tablet DVDD e DOVDD
  non esistono (vedi la cover: solo AVDD è un regolatore vero)

L'unico messaggio nel log del kernel è un WARNING dell'IPU6, non dei
sensori: `ipu6-isys-queue.c:203`, un `lockdep_assert_held` in
`ipu6_isys_buffer_list_get()`. Esce una volta per ogni avvio dello stream.
Non serve citarlo nella cover. Se lo vuoi citare, di' solo che esce anche
senza questi driver (è nel codice dell'IPU6).


## 3. v4l2-compliance

Versione da git, come chiede Hans: `v4l2-compliance 1.33.0-5515`,
SHA `1616bf9e3c81` del 06/10/2026.

Comando: `v4l2-compliance -z PCI:0000:00:05.0 -u /dev/v4l-subdevN`.
Il `-z` serve: senza, il programma non trova il dispositivo media e salta
i test sul pad (fa 46 test invece di 54).

Risultato, uguale per tutti e due:
`Total ...: 54, Succeeded: 54, Failed: 0, Warnings: 2`

I due avvisi (Try e Active) sono:
`VIDIOC_SUBDEV_G_SELECTION is supported for target 0 but not VIDIOC_SUBDEV_S_SELECTION`

Perché è normale: c'è un solo modo e il crop è fisso, quindi si può
leggere ma non cambiare. Fanno lo stesso imx219, imx258, ov5675, gc05a2,
gc08a3, imx283, hi846 in mainline. Conviene dirlo in una riga, prima che lo
chieda qualcuno.

L'output completo da mettere in fondo alla cover:
`data/prova-20261008-194731/04-compliance-gc5035.txt` e `...-gc8034.txt`.


## 4. Cose da dire che non sono coperte

- Un solo modo per sensore: 2592x1944 e 3264x2448. I modi ridotti del
  vendor non sono provati e non ci sono.
- Solo clock esterno a 19,2 MHz, l'unico provato.
- ANALOGUE_GAIN è l'indice del gradino analogico. Il guadagno digitale
  resta a 1x. I driver del vendor riempiono i buchi fra due gradini col
  digitale: qui lo lasciamo allo userspace.
- OTP non letto (sul gc5035 contiene impostazioni di fabbrica e pixel
  difettosi; la serie del 2020 lo usava).
- Il gc8034 ha un motore di messa a fuoco dw9714 (creato da ipu-bridge):
  la messa a fuoco non è provata.
- Un solo tablet, un esemplare per sensore.
- Niente datasheet. PLL e impostazioni CSI-2 non documentate.
- PIXEL_RATE del gc8034 più alto di quello che il link porta: è giusto,
  perché la lunghezza di riga (HTS) comprende il blanking.
- L'offset di 36 righe del gc8034 viene dal codice Rockchip; ora è anche
  confermato dalla misura a VBLANK 2000 (sopra).


## 5. Firme e tag

- Le patch **non hanno il Signed-off-by**. Va aggiunto da te, a tutte e 3.
- `Assisted-by:` ora dice `claude-opus-5-5 coccinelle sparse smatch` (1 e 2)
  e `claude-opus-5-5` (3), col nome del modello come ha chiesto Sakari.
  Va subito dopo il tuo Signed-off-by.
- La sezione «Use of an LLM» della cover ora ha il tuo testo. Laurent ha un
  bot contro i testi da LLM: anche il resto della cover e i messaggi di
  commit scrivili tu.


## 6. Controlli fatti stasera

- `next` non si è mosso: `8e26d4c20` è ancora la punta.
- Nessun altro ha mandato driver per questi sensori: su patchwork, per
  gc5035 c'è solo la v4 di Tomasz Figa del 2020, per gc8034 niente.
- I file in `patches/wip/driver-v1/gc5035.c` e `gc8034.c` sono identici a
  quelli della serie sul server.
- Rilettura da capo della serie finale: nessun difetto bloccante; 6 correzioni
  piccole prima di spedire (docs/13, «Rilettura da capo di bce5c5710»), applicate
  in `7b3ed03b4`. I numeri della sezione 2 vengono dalla prova completa rifatta
  su questa versione.
