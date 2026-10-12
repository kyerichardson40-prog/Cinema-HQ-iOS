# Spider-Man Unlimited Test1 startup diagnostics

Input: existing artifact 11737460031, Spider-Man_Unlimited_v5.0.0_Portal_Test1.ipa.
Completed analysis: https://github.com/kyerichardson40-prog/Cinema-HQ-iOS/actions/runs/38259511024
Report: https://github.com/kyerichardson40-prog/Cinema-HQ-iOS/actions/runs/38259511024/artifacts/11751103721

This is read-only static analysis. The workflow neither executes the game nor contacts game servers. It verifies the input IPA SHA256 remains unchanged. Uploaded device saves were not submitted to the public repository.

## Confirmed evidence

- IPA SHA256: f7b18da956e9ce0059f115fa7129daaa7567cbb7618bfaa3c6b32738902cab83.
- Executable SHA256: 7da6f8b352e2f2803b615e6999c846a640f8f0784cee4ac454703818431e18d2.
- ARM64 UUID matches the original crash report: 135e4f28-1cb4-3ef3-b91d-535bf291409f.
- Instruction at image-relative 0x5648bc is NOP. This is the earlier vector-reserve bypass; it does not provide portal definitions.
- Constructor writes selected tab 4 at 0x55fc94/0x55fc98. Portal refresh and tab update use four tables indexed 0 through 3.
- Selection function 0x56465c uses the provided index at 0x5646f0 to calculate the table address, without a bounds check in the inspected path. The caller at 0x568e74 loads the stored selection.
- Tab update code loads table size at 0x56c5b8. When the table has no first node and size zero, 0x56c77c through 0x56c788 produces state 4. This is consistent with the locked, empty recruitment screen reported by the user; the state-to-padlock interpretation is an inference.
- Bundled StaticData.json has GameStaticSection/LockedSections/Recruit set to false. Therefore a blanket Recruit lock in this bundled JSON is not the explanation.
- Bundled InitialCRMFeed.dat exists (828920 bytes), and code at 0x628a50 and 0x6295a8 references it. The first path reads the file and calls a transformation routine at 0x1182438 before parsing.
- The configuration parser at 0x628e7c explicitly handles offline_store. Additional configuration code at 0xbd4f60 and 0xbd62c8 also handles it.
- InitialCRMFeed.dat and events.json do not parse as plain JSON; their byte entropy is close to 8 bits/byte. This establishes opaque encoding, not a particular cipher or corruption.
- The executable references /PortalData/GetStaticData.php and /PortalData/GetEvents.php. References do not establish whether these endpoints were called, reachable, or required for this tutorial.

## Interpretation and limits

The strongest working explanation is that recruitment is entered before usable portal data and a valid selected tab are available. Skipping reserve prevents the reported abort but does not repair those prerequisites. Static data and the offline_store code show a bundled configuration path exists, so a dead-server explanation remains unproven.

The tab sentinel is a concrete boundary hazard. Changing it alone would not populate an empty catalogue. Similarly, forcing tab states enabled would expose missing data rather than establish correct offline recruitment.

The report cannot decode the user's tutorial state, establish live network failure, or show whether the bundled feed was successfully loaded on the phone. The next investigation should trace the bundled-feed transformation at 0x1182438, validate its decoded portal definitions, and establish which readiness condition prevents their use before deciding on a functional offline patch.

## Workflow correction

Run 38259274888 initially stopped its instruction scan at embedded data and returned no string references. Run 38259511024 corrected this by allowing embedded data during disassembly. Both runs were sequential. Use the latter report.
