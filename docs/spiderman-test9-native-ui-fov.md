# Spider-Man Unlimited Test9: persistent FOV and native UI

Gameplay previously overwrote the selected FOV in its per-frame camera update. Test9 intercepts that exact native virtual setter call, so the selected angle remains active while running. It replaces the UIKit slider with an ActionScript 3 control inside the existing pause menu. It also removes the whole-game safe-area inset: only the HUD and menu header artwork move, while the framebuffer and camera aspect stay full-screen.

## Behavior

- The pause menu has a native comic-style FIELD OF VIEW slider from 45 to 100 vertical degrees, using the game's Komika font. RESET selects the stock camera behavior.
- A value of 60 preserves the game's current authored camera angle, including speed-dependent changes. Other values override only the gameplay camera updater. Construction, menu and cutscene calls pass through.
- The preference uses the existing `SMUFieldOfViewDegrees` key. No player or tutorial save file is edited.
- Header and HUD offsets use the window's safe-area inset and the native movie's port dimensions. Menu header artwork extends its red background behind the Island. Gameplay retains the full rendering view.
- The working 120 FPS, portal, tutorial-exit and texture fallback patches remain from the verified Test6 baseline.

## Implementation

The runtime validates the guest UUID `135e4f28-1cb4-3ef3-b91d-535bf291409f`, native function bytes, and the writable camera vtable region. It replaces the FOV setter slot at RVA `0x18d6ce0 + 0x2c0`. The override qualifies the native caller return address `0x22d464` and the `camera-object` instance; the original setter continues to maintain the projection dirty bit.

The AS3 controls are independent classes added to the MainHUD and TopBarComplete sprites. Original game ABC scripts, fonts, artwork, animations and existing class mappings remain unchanged. Flash built-ins are external and must not be embedded a second time. The archive adds `SMURuntime.dylib` with a load command in unused header padding and retains all previous native instruction patches.

## Validation

The shared C/C++ policy covers 14,400 changing authored updates, stock reset and passthrough cameras. ARM64 emulation executes the compiled runtime hook and the game's actual setter over 1,203 cases, checking persistent FOV, latest authored reset, constructor passthrough, other camera passthrough and unchanged aspect/near/far/other fields. The game's native numeric decoder also verifies the obfuscated AS numeric format for FOV values and safe-area fractions.

The build verifies that each new AS3 module contains only its own control class; it preserves original UI assets and scripts, prior native fixes, all other archive resources, and ZIP checksums. Runtime behavior and final UI placement still require testing in LiveContainer on the device.
