# Test4 bug audit

Input: Spider-Man_Unlimited_v5.0.0_Test4_Tutorial_Exit.ipa.
SHA256: a290559f906111e98b312e2c7f6d176262b1665edb44e076fd5c93bc2beaa523.
Run: https://github.com/kyerichardson40-prog/Cinema-HQ-iOS/actions/runs/38292661251
Audit artifact: https://github.com/kyerichardson40-prog/Cinema-HQ-iOS/actions/runs/38292661251/artifacts/11766208332

The audit was read-only. It checked 13 internal archives, indexed 7,720 asset names, hashed 272 suit files, checked active portal dates and price entries, and inspected four mission lists. The source IPA and device saves were not modified.

## Findings

1. Duplicated boss suits — confirmed file duplication; appearance consequences require runtime confirmation for Electro/Vulture.
   - Goblin Black, Default, Gold, Green, Grey, and Red Goblin Boss share the exact same bytes. The Goblin appearance problem is already reported by the user.
   - Electro, Blue, GreenYellow (spelled GeenYellow in the file), Purple, Red, and Suit_ironman share exact bytes.
   - Vulture, Blue, Green, GreenBlack, Pink, Red, RedYellow, Ruby, and Homecoming share exact bytes.
   - Restore clean original material/model assets rather than replacing names or inventing originals. Some aliases can be deliberate; identical bytes alone do not prove every named appearance is broken.

2. Remaining expired recruitment content — confirmed configuration state.
   - 36 baseline portals are active after Test2.
   - 459 definitions remain expired: Unlimited 3, MysteryBox 1, FixedPool 3, Regular 449, Loot 3.
   - Likely offline symptom: absent portal types or restricted recruitment choices. Historical offers may intentionally be expired.
   - Expand a curated permanent offline catalogue and validate prices/rewards. Do not enable every historical event at once.

3. Special/VIP pricing mismatch — potential offline integration issue.
   - Active special_gacha_01 and vip_gacha have no direct item entries in offline_store.prices.
   - Fixed pools and VIP may use other pricing logic, so this is a test target, not a confirmed transaction failure.
   - Test preview, purchase eligibility, completion, inventory update, and save/relaunch without charging unexpected currency.

4. Missing texture references — static candidates requiring model-level verification.
   - Suit_2099_New: _099_new_d.tga and _099_new_n.tga.
   - Suit_SpiderX and Suit_Lasher: jennix_s.tga.
   - Suit_IronSpiderNew: s.tga.
   - Five extracted string references were absent from the indexed archives. They may be internal aliases, externally supplied resources, or false positives from binary-string extraction. Do not patch blindly.
   - Possible symptoms if genuine: missing texture, fallback appearance, or a load failure when selecting those suits.

5. Network-backed functionality — unverified offline risk.
   - The executable retains 38 endpoint paths involving validation, inventory, alliances, rankings, and related functions.
   - Static strings do not show whether these requests execute or block play.
   - Validate event entry, ads revives, alliance functions, rewards, inventory operations, and ranking screens offline before claiming complete offline support.

6. Tutorial revive restriction — known defect under test.
   - Tutorial revive eligibility bypasses the normal cap; the baseline configuration also lists 45 zero-cost revives.
   - Test4 changes the prompt's isTutorialContinues flag to permit decline/quit.
   - Build verification passed. User confirmation of the quit option is still pending; the underlying tutorial is not marked completed by this patch.

## Checks that passed

- IPA ZIP integrity and unchanged source hash.
- All 272 inspected suit entries read with valid size/CRC.
- No duplicate mission IDs within SocialMap Story (119), SocialMap Special (30), Event Story (52), or Event Special (12).
- No nonpositive objective goals in those lists.
- No invalid portal date intervals or duplicate offline price item IDs.
- These static checks do not establish that gameplay, progression, or save persistence succeeds on-device.

## Priority

First confirm Test4 mission exit, then restore authentic boss variants, validate the four texture-risk suits, and test Special/VIP offline transactions. Broader portal availability should follow after transaction and save behaviour are verified.
