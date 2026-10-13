# Test8 pause menu FOV slider

The user requested a gameplay FOV slider incorporated into the pause menu. Test8 adds a UIKit panel to MainGLView, visible only when the game's existing pause panel is visible. It offers integer vertical FOV values from 45 to 100 degrees and a Reset button. The last selected value is stored under the separate preference key SMUFieldOfViewDegrees. Reset removes that key and restores the camera's captured native value; game save data is not rewritten.

Native evidence:

- Gameplay camera creation at ARM64 0x22cbf0 constructs the concrete camera node, gives it the name camera-object, and sets its FOV to the constant at 0x1481788: 1.04719758 radians (60 degrees).
- The concrete camera vtable begins at 0x18d6ce0. FOV is at object +0x188, aspect at +0x18c, near/far at +0x190/+0x194. The original FOV setter at 0xfe31c0 changes +0x188 and sets projection dirty bit 1 at +0x3a0.
- The projection builder at 0xfe31fc uses cotangent(FOV/2), with the horizontal coefficient divided by aspect. The value is vertical FOV.
- setActiveCamera at 0x1001bb8 stores the camera at scene manager +0x208. The gameplay constructor calls it on the singleton referenced at 0x1bbf1a0.
- UI lookup at 0x148d18 is called by existing game code with the native short string menu_HUD. Its byte layout is inline content at 0 and length at 23, directly reproduced by the adapter rather than using a different compiler's string object.
- HUD root visibility is queried through its native movie-clip handle at +0x20 using 0xd07c80. Pause visibility at 0x3a0cb0 resolves mvc_Pause and reads its visibility.
- MainGLView's inherited prepare method is void(id, SEL), native IMP 0xe56790. The adapter chains this method and the prior layout method, retaining Test7's safe-area hook.

The adapter finds the guest image by its UUID, validates key native instruction signatures, and enables itself only if the prepare IMP is the expected game method. Each native access runs on the main thread. It writes FOV only to the active concrete camera with the exact camera-object name while the gameplay HUD is visible. Other camera classes/names are skipped; HUD-hidden sequences restore the last authored value on the active gameplay camera. It retains numeric history without dereferencing inactive camera objects. If a pause panel is visible but the eligible camera cannot be found, the slider is disabled and displays FOV CAMERA UNAVAILABLE instead of pretending to modify a camera.

The new panel is placed at the bottom of the rendering view, away from the main pause button stack. UIKit controls receive slider/reset touches; the rest of the game view keeps its original input handling. The panel hides on resume or when the view leaves its window. The setting remains active after resuming.

Validation includes compiled shared policy tests (clamping, no cumulative zoom, authored changes, reset, leaving gameplay), ARM64 execution of the actual native setter at five selected angles, iOS ARM64 compilation with warnings as errors, dylib initialization/dependency checks, and full IPA resource equality/CRC checks. The only original executable changes are an additional load command and its header counts; all Test7 instructions and resources remain intact. The new file is Frameworks/SMUFOV.dylib.

Device validation is still required: panel placement, pause visibility detection, native camera lookup, visible widening, reset, persistence after restart, touch behaviour and performance. Particular authored cinematics that retain the normal gameplay HUD/camera need checking; static evidence alone does not prove every such sequence is excluded.
