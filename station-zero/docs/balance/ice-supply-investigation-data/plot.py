"""Regenerate the standalone figure: python path/to/plot.py (requires matplotlib)."""
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

base = Path(__file__).resolve().parent
fig, axes = plt.subplots(2, 1, figsize=(10, 6.5), sharex=True, constrained_layout=True)
colors = ['#246a9b', '#bc4935', '#3b8a62', '#9665aa', '#b18223']
for seed, color in zip([42, 7, 99, 1234, 2026], colors):
    trace = json.loads((base / f'seed_{seed}_trace.json').read_text())
    std = json.loads((base.parent / 'lifecycle-standard-baseline-data' / f'std_seed_{seed}.json').read_text())
    axes[0].plot(range(721), trace['ice_samples'], color=color, linewidth=1.2, label=f'Seed {seed}')
    axes[1].step(range(721), std['adults'][:721], where='post', color=color, linewidth=1.5)
axes[0].set(title='Reachable ice remains available while stored water and founder labour collapse', ylabel='Stored ice (water units)')
axes[0].legend(ncol=5, loc='upper right', frameon=False)
axes[1].set(xlabel='Elapsed sol', ylabel='Living adults', yticks=range(8), ylim=(-0.2, 7.7), xlim=(0, 720))
axes[1].axhline(4, color='#555555', linestyle='--', linewidth=0.8)
axes[1].text(10, 4.2, 'L1 adult floor: 4', color='#555555', fontsize=9)
for ax in axes:
    ax.grid(alpha=0.18)
    ax.spines[['top', 'right']].set_visible(False)
fig.savefig(base / 'ice-and-founders.png', dpi=160)
fig.savefig(base / 'ice-and-founders.svg')
# Matplotlib emits trailing spaces inside SVG path attributes; newlines preserve their separators.
svg = base / 'ice-and-founders.svg'
svg.write_text('\n'.join(line.rstrip() for line in svg.read_text().splitlines()) + '\n')
