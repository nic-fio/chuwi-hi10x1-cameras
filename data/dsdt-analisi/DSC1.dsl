        Device (DSC1)
        {
            Name (_HID, "INT3472")  // _HID: Hardware ID
            Name (_DDN, "PMIC-CRDG")  // _DDN: DOS Device Name
            Name (_UID, One)  // _UID: Unique ID
            If ((C1GP != Zero))
            {
                Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
                {
                    If ((C1GP > Zero))
                    {
                        Local0 = PINR (C1P0, C1G0)
                    }

                    If ((C1GP > One))
                    {
                        Local1 = PINR (C1P1, C1G1)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((C1GP > 0x02))
                    {
                        Local1 = PINR (C1P2, C1G2)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((C1GP > 0x03))
                    {
                        Local1 = PINR (C1P3, C1G3)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((C1GP > 0x04))
                    {
                        Local1 = PINR (C1P4, C1G4)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((C1GP > 0x05))
                    {
                        Local1 = PINR (C1P5, C1G5)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    Return (Local0)
                }
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (CL01)
                {
                    If ((C1TP == One))
                    {
                        Return (0x0F)
                    }
                }

                Return (Zero)
            }

            Method (CLDB, 0, NotSerialized)
            {
                Name (PAR, Buffer (0x20)
                {
                    /* 0000 */  0x00, 0x00, 0x01, 0x00, 0x00, 0x0C, 0x00, 0x00,  // ........
                    /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0010 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0018 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
                })
                PAR [Zero] = C1VE /* \C1VE */
                PAR [One] = C1TP /* \C1TP */
                PAR [0x03] = C1CV /* \C1CV */
                PAR [0x04] = C1IC /* \C1IC */
                PAR [0x06] = C1SP /* \C1SP */
                PAR [0x08] = C1W0 /* \C1W0 */
                PAR [0x09] = C1W1 /* \C1W1 */
                PAR [0x0A] = C1W2 /* \C1W2 */
                PAR [0x0B] = C1W3 /* \C1W3 */
                PAR [0x0C] = C1W4 /* \C1W4 */
                PAR [0x0D] = C1W5 /* \C1W5 */
                PAR [0x0E] = C1CS /* \C1CS */
                Return (PAR) /* \_SB_.PC00.DSC1.CLDB.PAR_ */
            }

            Method (_DSM, 4, NotSerialized)  // _DSM: Device-Specific Method
            {
                If ((Arg0 == ToUUID ("79234640-9e10-4fea-a5c1-b5aa8b19756f") /* Unknown UUID */))
                {
                    If ((Arg2 == Zero))
                    {
                        Return (Buffer (One)
                        {
                             0x3F                                             // ?
                        })
                    }

                    If ((Arg2 == One))
                    {
                        Return (C1GP) /* \C1GP */
                    }

                    If ((Arg2 == 0x02))
                    {
                        Return (GPPI (C1F0, ((0x20 * C1G0) + C1P0), C1I0, C1A0))
                    }

                    If ((Arg2 == 0x03))
                    {
                        Return (GPPI (C1F1, ((0x20 * C1G1) + C1P1), C1I1, C1A1))
                    }

                    If ((Arg2 == 0x04))
                    {
                        Return (GPPI (C1F2, ((0x20 * C1G2) + C1P2), C1I2, C1A2))
                    }

                    If ((Arg2 == 0x05))
                    {
                        Return (GPPI (C1F3, ((0x20 * C1G3) + C1P3), C1I3, C1A3))
                    }

                    If ((Arg2 == 0x06))
                    {
                        Return (GPPI (C1F4, ((0x20 * C1G4) + C1P4), C1I4, C1A4))
                    }

                    If ((Arg2 == 0x06))
                    {
                        Return (GPPI (C1F5, ((0x20 * C1G5) + C1P5), C1I5, C1A5))
                    }
                }

                If (((PCHS == PCHP) || (PCHS == PCHN)))
                {
                    If ((Arg0 == ToUUID ("82c0d13a-78c5-4244-9bb1-eb8b539a8d11") /* Unknown UUID */))
                    {
                        If ((Arg2 == Zero))
                        {
                            If ((Arg1 == Zero))
                            {
                                Return (Buffer (One)
                                {
                                     0x03                                             // .
                                })
                            }
                            Else
                            {
                                Return (Zero)
                            }
                        }

                        If ((Arg2 == One))
                        {
                            ^^^ICLK.CLKC (ToInteger (DerefOf (Arg3 [Zero])), ToInteger (DerefOf (Arg3 [
                                One])))
                            ^^^ICLK.CLKF (ToInteger (DerefOf (Arg3 [Zero])), ToInteger (DerefOf (Arg3 [
                                0x02])))
                        }
                        Else
                        {
                            Return (Zero)
                        }
                    }
                }

                Return (Buffer (One)
                {
                     0x00                                             // .
                })
            }
        }
