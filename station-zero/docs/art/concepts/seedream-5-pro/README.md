# Seedream 5.0 Pro interior concepts (exploratory, not game assets)

Rendered 2026-10-09 through the Higgsfield connector, model `seedream_v5_pro`, 2K, 4:3 (2352 x 1760), one image per prompt.
Prompts: `docs/art/interior-concepts-seedream-5-pro.json` (from `main`), each sent verbatim plus one appended line:
"The attached reference image is the current in-game room of this building: match its line weight, palette and furniture
style only; do not copy its layout, its red-brown background or its straight top-down camera."

References (`references/`): the current interiors rendered from `main` (seed 42, noon, showcase layout, roof peeked,
zoom 4, HUD off) with `tools/shot.gd`, cropped to the room. One reference per building, shared by its A and B prompts.

| File | Job | Seed |
| --- | --- | --- |
| reactor_interior_concept_a.png | 88d437be-e1b5-44b5-bab6-2a51025cba9f | 695598 |
| reactor_interior_concept_b.png | 352986e7-be7c-4b91-9017-7b21cd384d7c | 735777 |
| habitat_interior_concept_a.png | 28541a4b-6c12-4087-9a44-e255b583972c | 955651 |
| habitat_interior_concept_b.png | 90573570-58f2-4029-901a-49c07779f8ee | 587812 |
| workshop_interior_concept_a.png | 589624b6-3098-4840-9219-6da341094e67 | 641069 |
| workshop_interior_concept_b.png | a3680881-19a7-4349-a5dd-561b3d03b1a0 | 35564 |
| greenroom_interior_concept_a.png | 75b288f0-d274-4b75-8391-8dec907a7a95 | 438317 |
| greenroom_interior_concept_b.png | 938bd39e-859d-44d5-a7ea-47299c3bf284 | 70892 |
| archive_interior_concept_a.png | bd21e5cb-0588-4eda-87cb-5de11be569cd | 357619 |
| archive_interior_concept_b.png | 46048e69-938c-40ce-a0fb-a20acd66b1e2 | 45431 |
| comms_interior_concept_a.png | d13bf354-0629-4b9c-beb4-151b8028cb30 | 727993 |
| comms_interior_concept_b.png | e7f67ab7-fa14-45e3-ab49-9979f590af17 | 502826 |

`contact_sheet.jpg`: current room, A, B per row. Unreviewed first renders: bed and seat counts, clearances and the
camera angle (the model drew a steeper isometric view than the requested 35-degree oblique) are not verified.
