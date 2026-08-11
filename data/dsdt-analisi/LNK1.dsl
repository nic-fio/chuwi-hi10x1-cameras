        Device (LNK1)
        {
            Name (PNIO, Package (0x01)
            {
                "\\_SB.PC00.SPI1.SPFD.CVFD"
            })
            Name (PUSB, Package (0x02)
            {
                "\\_SB.PC00.SPI1.SPFD.CVFD", 
                "\\_SB.PC00.XHCI.RHUB.HS07.VIC0"
            })
            Name (MUSB, Package (0x02)
            {
                "\\_SB.PC00.SPI1.SPFD.CVFD", 
                "\\_SB.PC00.XHCI.RHUB.HS06.VIC0"
            })
            Name (AUSB, Package (0x02)
            {
                "\\_SB.PC00.SPI1.SPFD.CVFD", 
                "\\_SB.PC00.XHCI.RHUB.HS08.VIC0"
            })
            Name (MASB, Package (0x02)
            {
                "\\_SB.PC00.SPI1.SPFD.CVFD", 
                "\\_SB.PC00.XHCI.RHUB.HS03.VIC0"
            })
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (L1EN)
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_DEP, 0, NotSerialized)  // _DEP: Dependencies
            {
                If (L1EN)
                {
                    If ((CVFS == 0x02))
                    {
                        If ((CUPN == 0x06))
                        {
                            Return (MUSB) /* \_SB_.PC00.LNK1.MUSB */
                        }
                        ElseIf ((CUPN == 0x07))
                        {
                            Return (PUSB) /* \_SB_.PC00.LNK1.PUSB */
                        }
                        ElseIf ((CUPN == 0x08))
                        {
                            Return (AUSB) /* \_SB_.PC00.LNK1.AUSB */
                        }
                        ElseIf ((CUPN == 0x03))
                        {
                            Return (MASB) /* \_SB_.PC00.LNK1.MASB */
                        }

                        Return (Package (0x00){})
                    }

                    If ((CVFS == One))
                    {
                        Return (PNIO) /* \_SB_.PC00.LNK1.PNIO */
                    }
                    Else
                    {
                        Return (CDEP (L1CL, L1BS))
                    }
                }
                Else
                {
                    Return (Package (0x01)
                    {
                        PC00
                    })
                }
            }

            Name (_UID, One)  // _UID: Unique ID
            Method (_HID, 0, NotSerialized)  // _HID: Hardware ID
            {
                Return (HCID (One))
            }

            Method (_DDN, 0, NotSerialized)  // _DDN: DOS Device Name
            {
                Name (BUF, Buffer (0x10){})
                BUF [Zero] = L1M0 /* \L1M0 */
                BUF [One] = L1M1 /* \L1M1 */
                BUF [0x02] = L1M2 /* \L1M2 */
                BUF [0x03] = L1M3 /* \L1M3 */
                BUF [0x04] = L1M4 /* \L1M4 */
                BUF [0x05] = L1M5 /* \L1M5 */
                BUF [0x06] = L1M6 /* \L1M6 */
                BUF [0x07] = L1M7 /* \L1M7 */
                BUF [0x08] = L1M8 /* \L1M8 */
                BUF [0x09] = L1M9 /* \L1M9 */
                BUF [0x0A] = L1MA /* \L1MA */
                BUF [0x0B] = L1MB /* \L1MB */
                BUF [0x0C] = L1MC /* \L1MC */
                BUF [0x0D] = L1MD /* \L1MD */
                BUF [0x0E] = L1ME /* \L1ME */
                BUF [0x0F] = L1MF /* \L1MF */
                Return (ToString (BUF, Ones))
            }

            Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
            {
                Name (PLDB, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                        /* 0008 */  0x69, 0x0E, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00,  // i.......
                        /* 0010 */  0xFF, 0xFF, 0xFF, 0xFF                           // ....
                    }
                })
                CreateByteField (DerefOf (PLDB [Zero]), 0x08, BPOS)
                CreateField (DerefOf (PLDB [Zero]), 0x73, 0x04, RPOS)
                BPOS = L1PL /* \L1PL */
                RPOS = L1DG /* \L1DG */
                Return (PLDB) /* \_SB_.PC00.LNK1._PLD.PLDB */
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                If ((CVFS == 0x02))
                {
                    Return (VIIC (L1A0, Zero))
                }

                If ((L1DI == Zero))
                {
                    Return (Buffer (Zero){})
                }
                Else
                {
                    If ((L1DI > Zero))
                    {
                        Local0 = IICB (L1A0, L1BS)
                    }

                    If ((L1DI > One))
                    {
                        Local1 = IICB (L1A1, L1BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L1DI > 0x02))
                    {
                        Local1 = IICB (L1A2, L1BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L1DI > 0x03))
                    {
                        Local1 = IICB (L1A3, L1BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L1DI > 0x04))
                    {
                        Local1 = IICB (L1A4, L1BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L1DI > 0x05))
                    {
                        Local1 = IICB (L1A5, L1BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L1DI > 0x06))
                    {
                        Local1 = IICB (L1A6, L1BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L1DI > 0x07))
                    {
                        Local1 = IICB (L1A7, L1BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L1DI > 0x08))
                    {
                        Local1 = IICB (L1A8, L1BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L1DI > 0x09))
                    {
                        Local1 = IICB (L1A9, L1BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L1DI > 0x0A))
                    {
                        Local1 = IICB (L1AA, L1BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L1DI > 0x0B))
                    {
                        Local1 = IICB (L1AB, L1BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    Return (Local0)
                }
            }

            Method (SSDB, 0, NotSerialized)
            {
                Name (PAR, Buffer (0x6C)
                {
                    /* 0000 */  0x00, 0x00, 0x69, 0x56, 0x39, 0x8A, 0xF7, 0x11,  // ..iV9...
                    /* 0008 */  0xA9, 0x4E, 0x9C, 0x7D, 0x20, 0xEE, 0x0A, 0xB5,  // .N.} ...
                    /* 0010 */  0xCA, 0x40, 0xA3, 0x00, 0x00, 0x00, 0x00, 0x00,  // .@......
                    /* 0018 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0020 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0028 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0030 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0038 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0040 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0048 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0050 */  0x0F, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,  // ........
                    /* 0058 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0060 */  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0068 */  0x00, 0x00, 0x00, 0x00                           // ....
                })
                PAR [Zero] = L1DV /* \L1DV */
                PAR [One] = L1CV /* \L1CV */
                PAR [0x18] = L1LC /* \L1LC */
                PAR [0x1C] = L1LU /* \L1LU */
                PAR [0x1D] = L1NL /* \L1NL */
                PAR [0x4E] = L1EE /* \L1EE */
                PAR [0x4F] = L1VC /* \L1VC */
                PAR [0x52] = L1FS /* \L1FS */
                PAR [0x53] = L1LE /* \L1LE */
                PAR [0x54] = CDEG (L1DG)
                CreateDWordField (PAR, 0x56, DAT)
                DAT = L1CK /* \L1CK */
                PAR [0x5A] = L1CL /* \L1CL */
                PAR [0x5F] = L1PP /* \L1PP */
                PAR [0x60] = L1VR /* \L1VR */
                PAR [0x63] = L1FI /* \L1FI */
                Return (PAR) /* \_SB_.PC00.LNK1.SSDB.PAR_ */
            }
