        Device (DSC0)
        {
            Name (_HID, "INT3472")  // _HID: Hardware ID
            Name (_DDN, "PMIC-CRDG")  // _DDN: DOS Device Name
            Name (_UID, Zero)  // _UID: Unique ID
            If ((C0GP != Zero))
            {
                Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
                {
                    If ((C0GP > Zero))
                    {
                        Local0 = PINR (C0P0, C0G0)
                    }

                    If ((C0GP > One))
                    {
                        Local1 = PINR (C0P1, C0G1)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((C0GP > 0x02))
                    {
                        Local1 = PINR (C0P2, C0G2)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((C0GP > 0x03))
                    {
                        Local1 = PINR (C0P3, C0G3)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((C0GP > 0x04))
                    {
                        Local1 = PINR (C0P4, C0G4)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    If ((C0GP > 0x05))
                    {
                        Local1 = PINR (C0P5, C0G5)
                        ConcatenateResTemplate (Local0, Local1, Local2)
                        Local0 = Local2
                    }

                    Return (Local0)
                }
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (CL00)
                {
                    If ((C0TP == One))
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
                    /* 0000 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x00, 0x00,  // ........
                    /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0010 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                    /* 0018 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
                })
                PAR [Zero] = C0VE /* \C0VE */
                PAR [One] = C0TP /* \C0TP */
                PAR [0x03] = C0CV /* \C0CV */
                PAR [0x04] = C0IC /* \C0IC */
                PAR [0x06] = C0SP /* \C0SP */
                PAR [0x08] = C0W0 /* \C0W0 */
                PAR [0x09] = C0W1 /* \C0W1 */
                PAR [0x0A] = C0W2 /* \C0W2 */
                PAR [0x0B] = C0W3 /* \C0W3 */
                PAR [0x0C] = C0W4 /* \C0W4 */
                PAR [0x0D] = C0W5 /* \C0W5 */
                PAR [0x0E] = C0CS /* \C0CS */
                Return (PAR) /* \_SB_.PC00.DSC0.CLDB.PAR_ */
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
                        Return (C0GP) /* \C0GP */
                    }

                    If ((Arg2 == 0x02))
                    {
                        Return (GPPI (C0F0, ((0x20 * C0G0) + C0P0), C0I0, C0A0))
                    }

                    If ((Arg2 == 0x03))
                    {
                        Return (GPPI (C0F1, ((0x20 * C0G1) + C0P1), C0I1, C0A1))
                    }

                    If ((Arg2 == 0x04))
                    {
                        Return (GPPI (C0F2, ((0x20 * C0G2) + C0P2), C0I2, C0A2))
                    }

                    If ((Arg2 == 0x05))
                    {
                        Return (GPPI (C0F3, ((0x20 * C0G3) + C0P3), C0I3, C0A3))
                    }

                    If ((Arg2 == 0x06))
                    {
                        Return (GPPI (C0F4, ((0x20 * C0G4) + C0P4), C0I4, C0A4))
                    }

                    If ((Arg2 == 0x07))
                    {
                        Return (GPPI (C0F5, ((0x20 * C0G5) + C0P5), C0I5, C0A5))
                    }

                    Return (Buffer (One)
                    {
                         0x00                                             // .
                    })
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
