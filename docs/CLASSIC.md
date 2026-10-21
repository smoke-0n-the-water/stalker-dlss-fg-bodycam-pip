# Classic bodycam

Classic mode adds camera and weapon handling on top of GAMMA's own first-person
animations. It does not replace an authored animation; it moves the camera, adds
offsets to the HUD, and solves the arms around the weapon.

Each feature has its own enable setting and works with every other feature
off. The four simulation features each have a settings struct with an enable
flag, a state struct and an update function in `bodycam_simulation.*`. The
camera features (Camera Decoupling, Footstep Camera) keep their settings and
state in the camera rig, `bodycam_camera_rig.*`; the other features keep their
settings in `bodycam_settings.h`. There are three departures from one struct
per feature:

- Camera Decoupling also owns the head roll and shake settings, which have no
  enable flag of their own, and the choice of lag model
  (`camera_continuous_follow_enable`: Deadzone or Reference follow) with the
  Reference follow lag tuning. The Camera Decoupling tab shows the settings
  of the selected lag model only; under Reference follow these are the follow
  lag, the position shift and its follow speed, and the maximum offsets, which
  still limit the position shift there.
- Mouse-driven arm settling and Movement-linked handling share one struct with
  two flags.
- Sprint Transition is one toggle over the sprint start, its gun step bob
  (`sprint_transition_gun_bob`, in `RuntimeConfig::sprint_start`) and the
  sprint camera sway.

## Features

| Feature (UI tab) | Enable setting | What it does | Code |
| --- | --- | --- | --- |
| Camera Decoupling | `camera_decoupling_enable` | The camera trails the aim, inside a deadzone and soft zone (Deadzone) or continuously with the Reference camera lag (Reference follow); its position shifts with the lag and with movement. Includes Reference head roll and shake. | `bodycam_camera_rig.*`, `bodycam_actor_camera.cpp`; follow lag in `bodycam_reference/classic_follow.h` |
| Footstep Camera | `footstep_camera_enable` | Recorded Reference head motion on the native footstep schedule. Replaces native head bob. | `bodycam_camera_rig.*`, `bodycam_reference/classic_footstep_camera.h` |
| Sprint Transition | `sprint_transition_enable` | Holds the hand-off to the sprint presentation until full sprint speed, and adds the sprint camera sway. Once the start is underway (the entry decision, about 0.1 s after the press) and until the hand-off, a weapon without its own run-to-sprint clip takes a gun step bob on the native footstep schedule, sized by the Reference step cycle at the current speed: translation, a depth push, and pitch, yaw and roll about the grip (fixed ratios in `classic_sprint_bob.h`). It fades in over half a step and out over one step, and resets on a mode or camera change. A start that completes inside the first 0.1 s gets no bob. A weapon switched in during the start gets its own entry decision. | `bodycam_sprint_start.h`, `bodycam_actor_movement.cpp`; sway in `bodycam_simulation.*`; gun bob in `bodycam_reference/classic_sprint_bob.h`, `bodycam_camera.cpp` |
| Movement Inertia | `movement_inertia_enable` | Acceleration and deceleration time, with braking strides. | `bodycam_movement_response.*`, `bodycam_actor_movement.cpp` |
| Viewmodel Lowering | `vm_lowering_enable` | Lowers the weapon while walking. | `bodycam_simulation.*` |
| Fire Impulse (Recoil) | `fire_impulse_enable` | A sprung kick of the weapon per shot; the kick shape per unit of power is set by the `fire_impulse_kick_*` settings. | `bodycam_simulation.*` |
| STALKER 2 Style Arm IK | `stalker2_style_arm_ik_enable` | Weapon and hands turn as one controller with the mouse; adds authored walk motion where the weapon's animation has little. | `bodycam_simulation.*`, `bodycam_hud_arms.*` |
| Reference regrip (Regrip) | `classic_regrip_enable` | Reference regrip clips on the Classic rig. | `bodycam_hud_arms.*` |
| Reference recoil (Recoil) | `classic_recoil_enable` | Reference gun recoil on the Classic rig. | `bodycam_hud_arms.*` |
| Mouse-driven arm settling (Weapon Handling) | `directional_weapon_inertia_enable` | The elbows settle after look movement. | `bodycam_hud_arms.*` |
| Movement-linked handling (Weapon Handling) | `movement_linked_handling_enable` | The weapon reacts to steps and velocity changes. | `classic_handling.h`, `bodycam_hud_arms.*` |

## Where features meet

- A shot notifies both lowering (recovery timers) and the fire impulse.
- The camera position spring carries the sprint sway, so the sway uses the camera follow speed.
- The Footstep Camera replaces native head bob and silences the sprint camera sway.
- Reference recoil takes a share of the Fire Impulse (`classic_recoil_fire_impulse_share`).
  The two share the Recoil tab and the shot event, nothing else.
- Regrip, recoil and look settling share one Reference source rig (calibration data only).
- The arm layers pause during weapon actions and script animations. A
  running Reference recoil and the handling offset settle out through a
  weapon action instead of stopping, and a regrip clip that is playing blends
  out at its own rate (0.2 s) while no new one starts. The recoil is added on top of the
  action's animated gun and carries both hands with it, so a hand holding a
  magazine during a reload moves with the recoil too. A script animation
  resets the handling offset and suppresses the recoil while it plays; the
  recoil keeps settling meanwhile, and what is left of it shows again
  afterwards.
- Braking strides belong to Movement Inertia.
- With only Movement Inertia on, the per-actor simulation does not run.

## Layout

All under `src/xrGame`.

- `bodycam_simulation.*`: sprint sway, lowering, fire impulse and STALKER 2
  arm IK. Plain data in and out, no engine types.
- `bodycam_camera_rig.*`: the Classic camera. The look lag (Camera
  Decoupling's deadzone and the Reference follow: both run every frame and the
  follow takes over the angles when selected), the camera shift, the Reference
  head roll and shake, the Footstep Camera, the HUD share (footstep offset and
  head roll), the view they compose over the effector camera, and the regrip
  turn of the applied view. Only xrCore math types, no engine state; the
  engine side gathers `CameraRigInput`, answers `CameraRigHost` (the footstep
  wall check) and applies the view, in `bodycam_actor_camera.cpp`.
- `bodycam_smoothing.h`: smoothing steps the simulation and the rig share.
- `bodycam_sprint_start.h`: sprint start, run-loop pacing, held lowering,
  braking stride. No engine types; the engine side is `SprintStartHost`,
  implemented in `bodycam_actor_movement.cpp`.
- `bodycam_settings.*`: the registry of settings (name, console name,
  storage, default, range). UI scripts refer to settings by name only.
- `bodycam_camera.*`: `CBodycam`, the per-actor host of the simulation and
  the camera rig. The actor reads the engine once per frame into an
  `ActorFrame`; `CBodycam::Update` derives the simulation input and the rig
  input from it.
- `bodycam_actor_camera.cpp`, `bodycam_actor_movement.cpp`,
  `bodycam_hud_playback.cpp`, `bodycam_steps.cpp`: members of engine classes,
  defined in bodycam-owned files.
- `bodycam_hud_arms.*`: the arm controller on the HUD rig.
- `bodycam_reference/`: the portable Reference library the Classic features
  borrow from (regrip, recoil, footstep camera, head motion, follow).

Porting to another X-Ray build: `docs/BODYCAM_PORTING.md`.

## Camera frame

In `CActor::cam_Finalize`, after the level camera manager has applied the raw
camera (`ActorCameras.cpp`), `cam_BodycamVisualUpdate` runs the rig and
applies its view, or the native camera when the rig does not compose; a held
PiP surround applies nothing. `FirstPerson::PublishCamera` publishes that
camera. The HUD update then solves the arms (regrip included). Last,
`cam_BodycamApplyRegrip` (`Actor.cpp`) applies the view a second time, turned
by the regrip camera, only when regrip is on and this frame's HUD solve gave
a regrip camera; it then publishes the camera and the weapon's scope snapshot
again. Readers inside the HUD update therefore see the first apply.

## Scope eye

With Bodycam scope effects, the lag model also chooses the scope eye
(`bodycam_reference_optics.cpp`, `SelectScopeEyeModel`). Under Deadzone the
eye follows a tracked pupil: the camera's offset from the gun's aimed eye is
eased back to the centre, as before. Under Reference follow the scope shows the
current eye, as Reference mode does, so the camera shift with movement, the
sprint sway and the regrip camera move the exit pupil. Camera Decoupling off
counts as Deadzone. Switching models while aimed hands over without a jump:
leaving Deadzone, the tracked eye returns to the current eye at the tracker's
speed; entering it, tracking starts from the current eye. Scopes drawn without
the scope effects (display sights, thermal overlays, MSAA or HDR10, effects
off) keep the stock eye tracking under both models.

## Validation

Validation fixtures are maintained separately. When changing a Classic feature, verify it alone
and in combination with recoil, regrip, native actions and mode changes. Portable calculations
can be checked offline; camera/HUD ordering and hand contact also require an engine build and
in-game checks.

## Diagnostics

`r__svp_cop_diag 2` writes these log lines for as long as it is set.

| Tag | Written |
| --- | --- |
| `[BODYCAM-CAMERA]`, `[BODYCAM-VIEWMODEL]`, `[BODYCAM-ARM]` | every frame the simulation runs |
| `[BODYCAM-FOOTSTEP]` | every frame the Footstep Camera runs |
| `[BODYCAM-SPRINT-START]` | while sprinting, and on the frame a held lowering commits |
| `[BODYCAM-SPRINT-BOB]` | every frame the Sprint Transition gun bob moves the gun |
| `[BODYCAM-BRAKE]` | during a braking stride |
| `[BODYCAM-REGRIP]`, `[BODYCAM-REGRIP-CLIP]` | every frame the arm controller solves; one clip line per playing regrip clip |
| `[BODYCAM-RECOIL]` | while firing or while the recoil pose is active |
| `[BODYCAM-SHOT]` | per shot |
| `[BODYCAM-CONTACT]` | every 60 arm solves: the largest hand-to-grip error since the last line |

These tags support in-game diagnosis.
