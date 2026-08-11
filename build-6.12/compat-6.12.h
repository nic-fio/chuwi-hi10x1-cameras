/* SPDX-License-Identifier: GPL-2.0 */
/*
 * compat-6.12.h — colma le differenze fra mainline 7.2, contro cui i driver
 * sono scritti, e il kernel Debian 6.12.86 che gira su questa macchina.
 *
 * Serve SOLO alla build fuori albero per il test su hardware. Non fa parte
 * della serie da inviare upstream e i sorgenti dei driver non vanno toccati:
 * viene incluso con -include, cosi' gc5035.c e gc8034.c restano bit-identici
 * a quelli in /home/nicfio/linux.
 */
#ifndef INTELCAM_COMPAT_6_12_H
#define INTELCAM_COMPAT_6_12_H

#include <linux/version.h>

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 17, 0)
#include <linux/clk.h>

/*
 * devm_v4l2_sensor_clk_get() e' arrivato dopo la 6.12. Su questa piattaforma
 * il clock lo registra int3472 con clkdev_create(..., con_id = NULL, dev_id =
 * nome del sensore), e un lookup con con_id NULL matcha qualunque con_id
 * richiesto: devm_clk_get_optional() lo trova.
 */
#define devm_v4l2_sensor_clk_get(dev, id) devm_clk_get_optional((dev), (id))
#endif

#endif /* INTELCAM_COMPAT_6_12_H */
