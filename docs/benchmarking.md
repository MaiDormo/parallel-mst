# Benchmarking

## Hardware and software

| Item | Value |
|---|---|
| Node | 1 node of the University of Trento cluster |
| CPU | AMD EPYC 9334, 32 cores / 64 threads, 2.7 GHz base |
| RAM | 791.8 GB |
| MPI | MPICH 3.2 |
| Compiler | GCC with OpenMP |
| Scheduler | PBS |

Compiler flags for the parallel binary: `-O3 -fopenmp -march=native -mtune=native -ftree-vectorize -funroll-loops -flto`.

## Workload

Synthetic connected graphs with 20,000, 40,000, and 80,000 vertices. The generator creates a dense
graph with approximately `m = n^2 / 4` edges and random `uint16_t` weights. The graph is stored as a symmetric
adjacency matrix, so the 80k case needs about 12.8 GB per matrix and 25.6 GB for the graph plus
the MST matrix.

## Method

- Five MPI configurations: 2, 4, 8, 16, and 32 ranks.
- Two OpenMP threads per rank, matching a 1:2 rank-to-thread ratio.
- Three runs per configuration, except 80k with 8 ranks, which has two runs in the CSV.
- Within each run, the serial implementation is timed first, then the parallel implementation on
  the same node.
- Times are the `Computation Time` printed by the code. `src/main.c` starts that timer after the
  initial matrix broadcast and `MPI_Barrier`, so graph loading and the first broadcast are not in
  the measured region.
- Speedup is computed per run as `serial_s / parallel_s`, then aggregated across runs.
- Efficiency is `speedup / total_threads`, where `total_threads = MPI ranks * 2`.

The raw course spreadsheet is `results/scaling_raw.csv` with the original column names.
`results/scaling.csv` is the normalized file used by `scripts/plot_results.py`.

## Full results

| Graph | MPI ranks | Threads | Best speedup | Median speedup | Best efficiency (all threads) | Runs |
|---:|---:|---:|---:|---:|---:|---:|
| 20k | 2 | 4 | 1.70x | 1.65x | 0.426 | 3 |
| 20k | 4 | 8 | 3.75x | 3.63x | 0.469 | 3 |
| 20k | 8 | 16 | 6.54x | 2.83x | 0.409 | 3 |
| 20k | 16 | 32 | 10.87x | 10.23x | 0.340 | 3 |
| 20k | 32 | 64 | 10.56x | 8.09x | 0.165 | 3 |
| 40k | 2 | 4 | 1.77x | 1.11x | 0.443 | 3 |
| 40k | 4 | 8 | 3.27x | 3.22x | 0.408 | 3 |
| 40k | 8 | 16 | 6.80x | 5.81x | 0.425 | 3 |
| 40k | 16 | 32 | 10.64x | 9.70x | 0.333 | 3 |
| 40k | 32 | 64 | 12.87x | 11.80x | 0.201 | 3 |
| 80k | 2 | 4 | 1.57x | 0.92x | 0.392 | 3 |
| 80k | 4 | 8 | 3.12x | 3.00x | 0.390 | 3 |
| 80k | 8 | 16 | 6.45x | 5.57x | 0.403 | 2 |
| 80k | 16 | 32 | 8.38x | 7.89x | 0.262 | 3 |
| 80k | 32 | 64 | 11.61x | 9.41x | 0.181 | 3 |

## Noise and outliers

The cluster is shared and the 80k input is large, so run time varied between runs. The raw CSV
keeps every run. Two entries are worth calling out:

- 20k with 8 ranks: one run took 44.6s against 1.4s and 4.0s in the other two. The 44.6s run is
  a contention outlier; the best run is 6.54x and the median is pulled down to 2.83x.
- 40k with 2 ranks: one run reported 9.4s parallel and 10.45s serial, while the other two
  reported 31-52s parallel and 47-55s serial. Both phases were about 5x faster in that run,
  likely a different node or cache state, so it does not change the best speedup (1.77x) but it
  affects the median.

The plots in `docs/plots/` use the best run per configuration, which is the least contended
measurement. The tables above also report the median so the spread is visible.

## Regenerate

```bash
python3 scripts/plot_results.py
./hpc_tools.sh benchmark-scaling graphs results/scaling_new.csv
```

`benchmark-scaling` runs the full 2-32 rank matrix and writes a CSV with the same columns as
`results/scaling.csv` minus the derived speedup and efficiency columns; the plotting script
recomputes those from `serial_s` and `parallel_s`.
