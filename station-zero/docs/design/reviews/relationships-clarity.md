# Review of relationships.md rev 1: designer-clarity (Korppoo lens)

Verdict: sound and restrained; the risk is the player-facing channel. Fix three things before sign-off. (Reviewer read the spec text only, not the sim or log panel code.)

**Good:** trust as a derived reading, no HUD number; one fixed number-free text per event; news-only filter; hysteresis; uncapped grief; hash-neutral at shipped values.

**Must-fix**
1. Friends-only talk will read as a bug (today any two nearby beings talk). Pick one: (a) a distinct awkward/apart idle for non-friends, or (b, preferred) a brief rarer talk for non-friends so friends simply talk more and longer: a gradient, not a binary. Do not ship the binary version.
2. Kinless newborns are silent and unexplained for ~9 sols (recorded parent may be a child or dead). Either allow the lonely-child case to talk (1b) or add a one-time line ("{a} has no one yet."). The spec must state the player-facing story; the lonely_share target 0.05 to 0.5 accepts up to half the colony silent.
3. The 3-a-sol cap drops events without retry and still adds ids to `found_friend`, so a first friendship can be lost for good. Do not set `found_friend` unless the line is logged, or queue to the next sol. State which. Say what the log shows when the cap hits (one summary line is cheaper than silence).

**Should-fix**
4. At 160 beings, names mean nothing; state that clicking a log line with ids focuses the camera on the first named being, or record it as an O3 cost.
5. Nothing tells the player why: add the shared place in plain words ("...have become friends at the Green Room." / "on the ice field"); needs a last-shared-place per pair, not in hashed state.
6. Drift lines fire only for was_close pairs, so the founders' crew dissolves silently and web_by_sol falls with no visible reason (a hidden counter acting as a gate for Task 5, against HANDOFF 1 in spirit); mark as a consequence in O2.
7. Add one rare colony-voice line when the web changes in kind, not level ("The colony has split into two camps." / rejoins).
8. Scale the per-sol cap with population, e.g. max(3, pop/20); one data key.
9. Log eviction at 500 entries may drop these low-volume lines first; check, or use a separate small ring buffer.

**Ideas:** talk gradient friends/close pairs; grieving mourner has a muted pose or slower walk; first Mars-born friendship line.

**On the owner questions:** agrees with O1(a), O2(a), O3(a), O4(a) conditional on the fixes above; if friend_pull ships on, islands form invisibly without item 7.
