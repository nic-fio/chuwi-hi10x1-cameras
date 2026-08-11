#!/usr/bin/env python3
"""
read-camera-nvs.py — legge i parametri camera dalla ACPI NVS.

Progetto INTEL-CAMERA — CHUWI Hi10 X1

PERCHE' ESISTE
--------------
Nella DSDT di questa macchina i parametri dei sensori NON ci sono: _HID, _CRS,
SSDB, CLDB e i _DSM sono tutti parametrizzati da variabili che il BIOS scrive
in ACPI NVS al boot. Nella DSDT quei campi sono solo dichiarati.

La OperationRegion GNVS ha pero' un indirizzo fisico letterale, quindi i valori
si possono leggere dalla memoria della macchina in esecuzione — SENZA riavviare
e senza installare nulla.

    OperationRegion (GNVS, SystemMemory, 0x75886000, 0x0CE1)

Serve root perche' legge /dev/mem. E' una lettura pura: non scrive niente.

USO
---
    sudo ./scripts/read-camera-nvs.py

ATTENZIONE
----------
L'indirizzo GNVS e la tabella degli offset valgono per QUESTA macchina con
QUESTO BIOS (SA10C.N1195.24071902.014). Dopo un aggiornamento del BIOS vanno
ricalcolati ridecompilando la DSDT.
"""

import errno
import os
import struct
import sys

GNVS_ADDR = 0x75886000
GNVS_LEN = 0x0CE1

HERE = os.path.dirname(os.path.abspath(__file__))
OFFSETS_FILE = os.path.join(HERE, "..", "data", "dsdt-analisi", "gnvs-offsets.txt")

# Tipi di funzione GPIO riconosciuti da intel_skl_int3472_discrete.
# Fonte: include/linux/platform_data/x86/int3472.h
GPIO_TYPES = {
    0x00: "RESET",
    0x01: "POWERDOWN",
    0x02: "STROBE",
    0x0B: "POWER_ENABLE",
    0x0C: "CLK_ENABLE",
    0x0D: "PRIVACY_LED",
    0x10: "DOVDD",
    0x12: "HANDSHAKE",
    0x13: "HOTPLUG_DETECT",
}


def load_offsets():
    """nome -> (offset_byte, larghezza_bit), dal Field GNVS della DSDT."""
    table = {}
    with open(OFFSETS_FILE) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) == 4:
                table[parts[0]] = (int(parts[1]), int(parts[3]))
    return table


def read_via_devmem():
    """Strada 1: /dev/mem. Puo' essere bloccata da CONFIG_IO_STRICT_DEVMEM."""
    fh = open("/dev/mem", "rb")
    try:
        fh.seek(GNVS_ADDR)
        data = fh.read(GNVS_LEN)
    finally:
        fh.close()
    if len(data) < GNVS_LEN:
        raise OSError("lettura corta: %d byte su %d" % (len(data), GNVS_LEN))
    return data


def read_via_kcore():
    """
    Strada 2: /proc/kcore.

    kcore espone la memoria del kernel come ELF. Il segmento PT_LOAD che mappa
    la memoria fisica diretta porta p_paddr, quindi si puo' risalire
    dall'indirizzo fisico all'offset nel file. Non passa da devmem_is_allowed(),
    quindi CONFIG_IO_STRICT_DEVMEM non lo blocca.
    """
    with open("/proc/kcore", "rb") as fh:
        hdr = fh.read(64)
        if hdr[:4] != b"\x7fELF" or hdr[4] != 2:
            raise OSError("/proc/kcore non e' un ELF64")
        e_phoff = struct.unpack_from("<Q", hdr, 32)[0]
        e_phentsize = struct.unpack_from("<H", hdr, 54)[0]
        e_phnum = struct.unpack_from("<H", hdr, 56)[0]

        fh.seek(e_phoff)
        phdrs = []
        for _ in range(e_phnum):
            ph = fh.read(e_phentsize)
            p_type = struct.unpack_from("<I", ph, 0)[0]
            p_offset = struct.unpack_from("<Q", ph, 8)[0]
            p_vaddr = struct.unpack_from("<Q", ph, 16)[0]
            p_paddr = struct.unpack_from("<Q", ph, 24)[0]
            p_filesz = struct.unpack_from("<Q", ph, 32)[0]
            if p_type == 1:  # PT_LOAD
                phdrs.append((p_offset, p_vaddr, p_paddr, p_filesz))

        for p_offset, p_vaddr, p_paddr, p_filesz in phdrs:
            if p_paddr and p_paddr <= GNVS_ADDR < p_paddr + p_filesz:
                fh.seek(p_offset + (GNVS_ADDR - p_paddr))
                data = fh.read(GNVS_LEN)
                if len(data) == GNVS_LEN:
                    return data

        # Nessun match: stampa la tabella, serve per adattare lo script.
        sys.stderr.write("\n/proc/kcore: nessun PT_LOAD copre 0x%08X.\n"
                         "Segmenti trovati (offset, vaddr, paddr, size):\n"
                         % GNVS_ADDR)
        for p_offset, p_vaddr, p_paddr, p_filesz in phdrs[:24]:
            sys.stderr.write("  off=0x%012x vaddr=0x%016x paddr=0x%012x size=0x%x\n"
                             % (p_offset, p_vaddr, p_paddr, p_filesz))
        raise OSError("nessun segmento kcore utilizzabile")


def read_gnvs():
    if os.geteuid() != 0:
        sys.exit("Serve root: sudo %s" % sys.argv[0])

    errors = []
    for name, fn in (("/dev/mem", read_via_devmem),
                     ("/proc/kcore", read_via_kcore)):
        try:
            data = fn()
            print("[letto via %s]" % name)
            return data
        except OSError as exc:
            code = getattr(exc, "errno", None)
            why = ""
            if code == errno.EPERM:
                why = "  (EPERM — il kernel blocca la regione: CONFIG_IO_STRICT_DEVMEM)"
            elif code == errno.ENOENT:
                why = "  (il file non esiste: opzione non compilata nel kernel)"
            errors.append("  %-12s -> %s%s" % (name, exc, why))

    sys.exit(
        "Non sono riuscito a leggere la ACPI NVS.\n"
        + "\n".join(errors)
        + "\n\nRestano solo strade che richiedono un kernel diverso da quello in\n"
          "esecuzione (iomem=relaxed, CONFIG_ACPI_DEBUGGER, modulo acpi_call).\n"
          "Vedi docs/05-parametri-sensori.md."
    )


def val(data, table, name):
    if name not in table:
        return None
    off, width = table[name]
    nbytes = width // 8
    chunk = data[off:off + nbytes]
    if len(chunk) < nbytes:
        return None
    return int.from_bytes(chunk, "little")


def describe_gpio(fn):
    if fn is None:
        return "?"
    known = GPIO_TYPES.get(fn)
    if known:
        return "0x%02x %s" % (fn, known)
    return "0x%02x <<< NON RICONOSCIUTO da int3472-discrete" % fn


def report_sensor(data, table, idx, name, hid):
    p = "L%d" % idx
    c = "C%d" % idx
    print("=" * 68)
    print("SENSORE %d — %s (%s)  ->  \\_SB.PC00.LNK%d" % (idx, name, hid, idx))
    print("=" * 68)

    ndev = val(data, table, p + "DI")
    bus = val(data, table, p + "BS")
    addr = val(data, table, p + "A0")
    lanes = val(data, table, p + "NL")
    mclk = val(data, table, p + "CK")
    clid = val(data, table, p + "CL")
    model = val(data, table, p + "SM")

    print("  modello (%sSM)        : 0x%02x" % (p, model or 0))
    print("  device I2C (%sDI)     : %s%s" % (
        p, ndev, "   <<< ZERO: nessuna risorsa I2C, nessun client" if ndev == 0 else ""))
    print("  bus I2C (%sBS)        : %s" % (p, bus))
    print("  indirizzo I2C (%sA0)  : 0x%02x" % (p, addr or 0))
    print("  LANE MIPI (%sNL)      : %s" % (p, lanes))
    print("  MCLK (%sCK)           : %s Hz%s" % (
        p, mclk, "  (= %.1f MHz)" % (mclk / 1e6) if mclk else ""))
    print("  control logic (%sCL)  : %s" % (p, clid))

    ngpio = val(data, table, c + "GP")
    clksrc = val(data, table, c + "CS")
    print()
    print("  INT3472 / DSC%d:" % idx)
    print("    numero GPIO (%sGP)  : %s" % (c, ngpio))
    print("    clock source (%sCS) : %s" % (c, clksrc))
    if ngpio:
        for i in range(ngpio):
            fn = val(data, table, "%sF%d" % (c, i))
            pin = val(data, table, "%sP%d" % (c, i))
            grp = val(data, table, "%sG%d" % (c, i))
            pin_abs = (0x20 * grp + pin) if (grp is not None and pin is not None) else None
            print("    GPIO %d: func=%-42s pin=%s" % (i, describe_gpio(fn), pin_abs))
    print()


def main():
    table = load_offsets()
    data = read_gnvs()

    print()
    print("ACPI NVS @ 0x%08X, %d byte letti" % (GNVS_ADDR, len(data)))
    print()

    report_sensor(data, table, 0, "GC8034 posteriore", "GCTI8034")
    report_sensor(data, table, 1, "GC5035 frontale", "GCTI5035")

    print("=" * 68)
    print("VERDETTI")
    print("=" * 68)

    c1gp = val(data, table, "C1GP")
    if c1gp is not None and c1gp >= 6:
        print("  [!] C1GP = %d  ->  il bug del firmware MORDE." % c1gp)
        print("      Nel _DSM di DSC1 il case Arg2==0x06 e' duplicato e il")
        print("      sesto GPIO e' irraggiungibile. Serve la Serie 4 come")
        print("      workaround. Vedi docs/05-parametri-sensori.md.")
    else:
        print("  [ok] C1GP = %s (<6): il bug del _DSM duplicato non ha effetto." % c1gp)

    unknown = []
    for c in (0, 1):
        n = val(data, table, "C%dGP" % c)
        for i in range(n or 0):
            fn = val(data, table, "C%dF%d" % (c, i))
            if fn is not None and fn not in GPIO_TYPES:
                unknown.append((c, i, fn))
    if unknown:
        print("  [!] tipi GPIO non riconosciuti da mainline:")
        for c, i, fn in unknown:
            print("      DSC%d GPIO %d: 0x%02x  -> serve la Serie 4" % (c, i, fn))
    else:
        print("  [ok] tutti i tipi GPIO sono gestiti da int3472-discrete:")
        print("       la Serie 4 (quirk int3472) NON serve.")

    for idx, nm in ((0, "GC8034"), (1, "GC5035")):
        ndev = val(data, table, "L%dDI" % idx)
        if ndev == 0:
            print("  [!] %s: L%dDI=0 -> _CRS vuoto, nessun client I2C creato." % (nm, idx))
            print("      Nessun driver potrebbe agganciarsi. Da risolvere prima")
            print("      di scrivere altro codice.")
    print()


if __name__ == "__main__":
    main()
