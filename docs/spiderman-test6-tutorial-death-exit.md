# Test6 tutorial death exit

The user still encounters the forced free-revive screen after Test5: "This revive is on us. Just keep going!" with Continue as its only button. Setting the UI property `isTutorialContinues` to false in Test4 did not establish a usable quit route on the device.

The native revive decision at ARM64 offset 0x44b884 reads the tutorial state at RunState +0x158. A positive value bypasses the ordinary revive cap (+0x178 versus count +0x15c) and returns an available revival. The caller at 0x50955c branches to native mission termination when this decision returns zero; the caller at 0x5047fc also has an existing zero-result path.

Test6 changes the comparison dispatch at 0x44b90c. A 16-byte stub at unused header padding 0x2010 sends positive tutorial states to the existing return-zero block at 0x44ba20. Nonpositive states go to the original cap check at 0x44ba08. The original stack restoration, callers, ordinary revive eligibility, and tutorial progress data are unchanged. The Test5 portal guard occupies 0x2000–0x200f and is preserved.

This deliberately removes forced tutorial revives: dying in a tutorial should end that run instead of opening the mandatory Continue prompt. Tutorial completion still requires its normal goal; this is an exit workaround, not a progression-completion patch. Start a fresh run after updating the IPA to test the changed death decision. Existing in-memory prompts cannot be retroactively changed by an IPA update.

Verification includes seven ARM64 execution cases (zero, positive, large positive, and signed-negative tutorial states), instruction allowlisting, preserved prior patch bytes, input SHA256, ZIP CRC, and equality checks for every other IPA member. The workflow supplies a separate verification artifact. iPhone gameplay behaviour still requires device testing.
