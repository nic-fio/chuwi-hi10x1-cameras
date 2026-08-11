        Device (LNK0)
        {
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (L0EN)
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
                If (L0EN)
                {
                    Return (CDEP (L0CL, L0BS))
                }
                Else
                {
                    Return (Package (0x01)
                    {
                        PC00
                    })
                }
            }

            Name (_UID, Zero)  // _UID: Unique ID
            Method (_HID, 0, NotSerialized)  // _HID: Hardware ID
            {
                Return (HCID (Zero))
            }

            Method (_DDN, 0, NotSerialized)  // _DDN: DOS Device Name
            {
                Name (BUF, Buffer (0x10){})
                BUF [Zero] = L0M0 /* \L0M0 */
                BUF [One] = L0M1 /* \L0M1 */
                BUF [0x02] = L0M2 /* \L0M2 */
                BUF [0x03] = L0M3 /* \L0M3 */
                BUF [0x04] = L0M4 /* \L0M4 */
                BUF [0x05] = L0M5 /* \L0M5 */
                BUF [0x06] = L0M6 /* \L0M6 */
                BUF [0x07] = L0M7 /* \L0M7 */
                BUF [0x08] = L0M8 /* \L0M8 */
                BUF [0x09] = L0M9 /* \L0M9 */
                BUF [0x0A] = L0MA /* \L0MA */
                BUF [0x0B] = L0MB /* \L0MB */
                BUF [0x0C] = L0MC /* \L0MC */
                BUF [0x0D] = L0MD /* \L0MD */
                BUF [0x0E] = L0ME /* \L0ME */
                BUF [0x0F] = L0MF /* \L0MF */
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
                BPOS = L0PL /* \L0PL */
                RPOS = L0DG /* \L0DG */
                Return (PLDB) /* \_SB_.PC00.LNK0._PLD.PLDB */
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                If ((L0DI == Zero))
                {
                    Return (Buffer (Zero){})
                }
                Else
                {
                    If ((L0DI > Zero))
                    {
                        Local0 = IICB (L0A0, L0BS)
                    }

                    If ((L0DI > One))
                    {
                        Local1 = IICB (L0A1, L0BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L0DI > 0x02))
                    {
                        Local1 = IICB (L0A2, L0BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L0DI > 0x03))
                    {
                        Local1 = IICB (L0A3, L0BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L0DI > 0x04))
                    {
                        Local1 = IICB (L0A4, L0BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L0DI > 0x05))
                    {
                        Local1 = IICB (L0A5, L0BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L0DI > 0x06))
                    {
                        Local1 = IICB (L0A6, L0BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L0DI > 0x07))
                    {
                        Local1 = IICB (L0A7, L0BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L0DI > 0x08))
                    {
                        Local1 = IICB (L0A8, L0BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L0DI > 0x09))
                    {
                        Local1 = IICB (L0A9, L0BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L0DI > 0x0A))
                    {
                        Local1 = IICB (L0AA, L0BS)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((L0DI > 0x0B))
                    {
                        Local1 = IICB (L0AB, L0BS)
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
                    /* 0060 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0068 */  0x00, 0x00, 0x00, 0x00                           // ....
                })
                PAR [Zero] = L0DV /* \L0DV */
                PAR [One] = L0CV /* \L0CV */
                PAR [0x18] = L0LC /* \L0LC */
                PAR [0x1C] = L0LU /* \L0LU */
                PAR [0x1D] = L0NL /* \L0NL */
                PAR [0x4E] = L0EE /* \L0EE */
                PAR [0x4F] = L0VC /* \L0VC */
                PAR [0x52] = L0FS /* \L0FS */
                PAR [0x53] = L0LE /* \L0LE */
                PAR [0x54] = CDEG (L0DG)
                CreateDWordField (PAR, 0x56, DAT)
                DAT = L0CK /* \L0CK */
                PAR [0x5A] = L0CL /* \L0CL */
                PAR [0x5F] = L0PP /* \L0PP */
                PAR [0x60] = L0VR /* \L0VR */
                PAR [0x63] = L0FI /* \L0FI */
                Return (PAR) /* \_SB_.PC00.LNK0.SSDB.PAR_ */
            }
