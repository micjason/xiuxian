# Shared battle cast — presentation only

`CombatAnimationSlots.setup()` attaches `scripts/combat_cast.gd` to the existing
TimelineBattlePage arena. `play_slot(side, slot, event)` is unchanged. Stage and
fog use the same cast, including READY idle. No combat rules, sessions, journal,
start/finish/ack, retreat, rewards, map return, or page chrome are changed.

## Composition

The new oral direction supersedes the **character composition only** in the
11/04 confirmation image. The HUD, back button, start/speed buttons and report
remain unchanged. At 1080×2340, feet are approximately **(261,1280)** and
**(819,1280)**. Heroes face right, these supplied monsters face left; the group
is horizontally centered. Hero standing height is 280, enemy 300. Both shrink
proportionally in shorter/narrower arenas. Roots/feet never lunge or bob.
Invisible legacy art rects carry the new bounds to existing FX, status and HP
anchors. Legacy single-image rigs remain hidden; existing sword/slash FX and
intro/result timing stay in place.

## Hero: genuine supplied sheet frames

The provided RGBA slices are copied unchanged (already transparent; no green
screen removal). Shared 640×320 canvas, feet anchor **(240,280)**, standing
reference height 130; one fixed scale across all poses.

- idle: 移动/**02,03,04,03**, 2.42 fps. No breathing scaling or rigid wobble.
- attack: 普通攻击/**00–04**, 11 fps.
- skill / ult: 技能施放/**00–04** then 技能攻击/**00–03**, 11 fps.
- hit: 受击/**00–03**; win: 胜利/**00–02**; lose: 倒地/**00–04**.
- Attacks/skills/hits return to idle. Results hold their last pose. A hit does
  not erase the player's outgoing strike halfway through. Speed follows the
  existing 1/2/3× playback setting, without changing combat timestamps.

`frames/manifest.json` records the source crop cells and included subset. Only
29 required PNG slices are included, through the repository's existing LFS
rules. The full sheet, demo scene/movie and unrelated frames are not bundled.

## Enemy: articulated mesh, not monster frame sheets

There are **no monster action frame sheets** in the existing battle_idle /
battle_boss art. Their old single-sprite breathing/lunge is not reused.
`scripts/enemy_pose.gd` makes a UV triangle mesh from the actual monster art
(`mon_*` counterpart when available), with independent neck/head, forelimb and
tail/wing pivots and local skinning weights. Quadruped, biped, winged and serpent
profiles select the joints. Idle scans/flexes/curls; attack lifts and sweeps the
forelimb and lowers the head (serpents strike with neck articulation); hit
recoils the neck. Rear planted feet and the whole root transform remain fixed.
This is procedural joint animation of existing art, **not newly drawn monster
frames** and not using the hero sheet for enemies. Bespoke per-monster artwork
is still a future art-quality improvement, not a missing task dependency.

The local cast deliberately does not change the global ArtLib facing table or
MonsterRig used on other pages. This version uses the supplied raw monster art
rather than deforming the old baked oversized outline/glow together with the
body; identity and the top HUD portrait are unchanged.

## Verification

```
Godot --headless --path game --editor --import
XIUXIAN_UI_MOCK=1 XIUXIAN_UPDATE_CHECK=0 Godot --headless --path game \
  -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_combat_cast.gd,res://tests/unit/test_battle_timeline.gd,res://tests/unit/test_boss_fight.gd -gexit
```

Real main-scene captures use XIUXIAN_UI_MOCK=0 and local HTTP, not the unit
fixture. The capture harness and screenshots stay outside the repository.
Original source art's ownership/commercial licensing was not independently
verified; slices are the supplied resources, not newly licensed artwork.
