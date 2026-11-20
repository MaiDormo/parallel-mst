#!/usr/bin/env python3
"""Regenerate the scaling plots from results/scaling.csv.

The CSV keeps every timed run, including the cluster's I/O-contention
outliers.  The plots use the best of the three runs per configuration
(the least contended measurement); the README also reports the median.
"""

from __future__ import annotations

import csv
import statistics
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
DATA = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "results" / "scaling.csv"
OUT = ROOT / "docs" / "plots"

SIZES = (20000, 40000, 80000)
LABELS = {20000: "20k vertices", 40000: "40k vertices", 80000: "80k vertices"}
COLORS = {20000: "#2f6f4e", 40000: "#c26a3d", 80000: "#3b6ea5"}
RANKS = (2, 4, 8, 16, 32)


def load() -> dict[int, dict[int, list[dict[str, float]]]]:
    data: dict[int, dict[int, list[dict[str, float]]]] = {}
    with DATA.open(newline="") as handle:
        for row in csv.DictReader(handle):
            nodes = int(row["nodes"])
            ranks = int(row["mpi_ranks"])
            data.setdefault(nodes, {}).setdefault(ranks, []).append(
                {
                    "parallel_s": float(row["parallel_s"]),
                    "serial_s": float(row["serial_s"]),
                    "speedup": float(row["speedup"])
                    if row.get("speedup")
                    else float(row["serial_s"]) / float(row["parallel_s"]),
                    "total_threads": float(row["total_threads"]),
                }
            )
    return data


def aggregate(data):
    best: dict[int, list[float]] = {}
    median: dict[int, list[float]] = {}
    efficiency: dict[int, list[float]] = {}
    for nodes in SIZES:
        best[nodes] = []
        median[nodes] = []
        efficiency[nodes] = []
        for ranks in RANKS:
            runs = data[nodes][ranks]
            best_run = max(runs, key=lambda run: run["speedup"])
            best_speed = best_run["speedup"]
            best[nodes].append(best_speed)
            median[nodes].append(statistics.median(run["speedup"] for run in runs))
            efficiency[nodes].append(best_speed / best_run["total_threads"])
    return best, median, efficiency


def style(ax):
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.set_xscale("log", base=2)
    ax.set_xticks(RANKS)
    ax.set_xticklabels([str(rank) for rank in RANKS])
    ax.grid(axis="y", color="#dddddd", linewidth=0.8)
    ax.set_axisbelow(True)


def save(fig, name):
    fig.savefig(OUT / name, dpi=180, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def plot_speedup(best):
    fig, ax = plt.subplots(figsize=(8, 4.3))
    style(ax)
    for nodes in SIZES:
        ax.plot(
            RANKS,
            best[nodes],
            marker="o",
            markersize=6,
            linewidth=2,
            color=COLORS[nodes],
            label=LABELS[nodes],
        )
        ax.annotate(
            f"{best[nodes][-1]:.1f}x",
            (RANKS[-1], best[nodes][-1]),
            textcoords="offset points",
            xytext=(7, 0),
            va="center",
            fontsize=9,
            color=COLORS[nodes],
        )
    ax.set_xlabel("MPI ranks (2 OpenMP threads each)")
    ax.set_ylabel("Speedup vs serial")
    ax.set_ylim(0, 14.5)
    ax.set_yticks(range(0, 15, 3))
    ax.set_title(
        "Measured speedup on one 64-core node",
        loc="left",
        fontsize=12,
        fontweight="bold",
    )
    ax.legend(frameon=False, loc="upper left")
    fig.text(
        0.01,
        -0.02,
        "Best of three runs per configuration. Raw data: results/scaling.csv.",
        fontsize=8,
        color="#555555",
    )
    save(fig, "speedup.png")


def plot_efficiency(efficiency):
    fig, ax = plt.subplots(figsize=(8, 4.3))
    style(ax)
    for nodes in SIZES:
        ax.plot(
            RANKS,
            efficiency[nodes],
            marker="o",
            markersize=6,
            linewidth=2,
            color=COLORS[nodes],
            label=LABELS[nodes],
        )
    ax.set_xlabel("MPI ranks (2 OpenMP threads each)")
    ax.set_ylabel("Speedup / total threads")
    ax.set_ylim(0, 0.55)
    ax.set_yticks([0.0, 0.1, 0.2, 0.3, 0.4, 0.5])
    ax.set_title(
        "Parallel efficiency across all 64 threads",
        loc="left",
        fontsize=12,
        fontweight="bold",
    )
    ax.legend(frameon=False, loc="upper right")
    fig.text(
        0.01,
        -0.02,
        "Efficiency = speedup / (2 x MPI ranks). Best of three runs.",
        fontsize=8,
        color="#555555",
    )
    save(fig, "efficiency.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    data = load()
    best, _median, efficiency = aggregate(data)
    plot_speedup(best)
    plot_efficiency(efficiency)
    for nodes in SIZES:
        print(f"{nodes}: speedup={best[nodes]}")


if __name__ == "__main__":
    main()
