#!/usr/bin/env bash
# Build, generate graphs, and run the MST benchmarks.
#
# Usage:
#   ./hpc_tools.sh compile
#   ./hpc_tools.sh generate-graphs
#   ./hpc_tools.sh benchmark
#   ./hpc_tools.sh benchmark-scaling [graph_dir] [output_csv]
#   ./hpc_tools.sh compare
#   ./hpc_tools.sh plot

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"

compile_all() {
    make -C "$ROOT"
}

generate_graphs() {
    mkdir -p "$ROOT/graphs"
    local vertices=(1000 1500 2000 5000 10000 20000 40000 80000)
    for v in "${vertices[@]}"; do
        local sparse_edges=$((v * 2))
        local medium_edges
        medium_edges=$(awk -v n="$v" 'BEGIN { printf "%d", n * log(n) / log(2) }')
        local dense_edges=$((v * v / 4))
        echo "Generating ${v}-vertex graphs..."
        "$BUILD/graph_generator" "$v" "$sparse_edges" "$ROOT/graphs/graph_${v}_sparse.txt"
        "$BUILD/graph_generator" "$v" "$medium_edges" "$ROOT/graphs/graph_${v}_medium.txt"
        "$BUILD/graph_generator" "$v" "$dense_edges" "$ROOT/graphs/graph_${v}_dense.txt"
    done
    echo "Graphs written to $ROOT/graphs"
}

benchmark() {
    shopt -s nullglob
    local graphs=("$ROOT"/graphs/graph_*_*.txt)
    if [ ${#graphs[@]} -eq 0 ]; then
        echo "No graph files found in $ROOT/graphs; run generate-graphs first." >&2
        exit 1
    fi
    for graph in "${graphs[@]}"; do
        local n
        n=$(head -n 1 "$graph" | awk '{print $1}')
        echo "== $graph =="
        "$BUILD/serial" "$n" "$graph"
        mpirun -np 2 --bind-to none -x OMP_NUM_THREADS=2 \
            "$BUILD/parallel" "$n" "$graph"
    done
}

benchmark_scaling() {
    local graph_dir="${1:-$ROOT/graphs}"
    local output="${2:-$ROOT/results/scaling_new.csv}"
    local repeats="${REPEATS:-3}"
    local ranks_list=(2 4 8 16 32)
    local threads_per_rank=2

    shopt -s nullglob
    local graphs=("$graph_dir"/graph_*_dense.txt)
    if [ ${#graphs[@]} -eq 0 ]; then
        echo "No dense graph files found in $graph_dir." >&2
        exit 1
    fi

    mkdir -p "$(dirname "$output")"
    echo "run,nodes,mpi_ranks,threads_per_rank,total_threads,parallel_s,serial_s" > "$output"
    for graph in "${graphs[@]}"; do
        local n
        n=$(head -n 1 "$graph" | awk '{print $1}')
        for run in $(seq 1 "$repeats"); do
            local serial_out serial_s
            serial_out=$("$BUILD/serial" "$n" "$graph")
            serial_s=$(awk '/Computation Time/ {print $3; exit}' <<< "$serial_out")
            if [ -z "$serial_s" ]; then
                echo "Could not parse serial time for $graph" >&2
                exit 1
            fi
            for ranks in "${ranks_list[@]}"; do
                local parallel_out parallel_s
                parallel_out=$(mpirun -np "$ranks" --bind-to none \
                    -x OMP_NUM_THREADS="$threads_per_rank" \
                    "$BUILD/parallel" "$n" "$graph")
                parallel_s=$(awk '/Computation Time/ {print $3; exit}' <<< "$parallel_out")
                if [ -z "$parallel_s" ]; then
                    echo "Could not parse parallel time for $graph at $ranks ranks" >&2
                    exit 1
                fi
                echo "$run,$n,$ranks,$threads_per_rank,$((ranks * threads_per_rank)),$parallel_s,$serial_s" >> "$output"
                echo "n=$n run=$run ranks=$ranks serial=${serial_s}s parallel=${parallel_s}s"
            done
        done
    done
    echo "Wrote $output"
}

compare() {
    shopt -s nullglob
    local graphs=("$ROOT"/graphs/graph_*_*.txt)
    if [ ${#graphs[@]} -eq 0 ]; then
        echo "No graph files found in $ROOT/graphs; run generate-graphs first." >&2
        exit 1
    fi
    for graph in "${graphs[@]}"; do
        local n serial_out parallel_out serial_weight serial_time parallel_weight parallel_time
        n=$(head -n 1 "$graph" | awk '{print $1}')
        echo "== $graph =="
        serial_out=$("$BUILD/serial" "$n" "$graph")
        serial_weight=$(awk -F: '/Total MST Weight/ {gsub(/ /, "", $2); print $2}' <<< "$serial_out")
        serial_time=$(awk -F: '/Computation Time/ {gsub(/ /, "", $2); print $2}' <<< "$serial_out")
        parallel_out=$(mpirun -np 4 "$BUILD/parallel" "$n" "$graph")
        parallel_weight=$(awk -F: '/Total MST Weight/ {gsub(/ /, "", $2); print $2}' <<< "$parallel_out")
        parallel_time=$(awk -F: '/Computation Time/ {gsub(/ /, "", $2); print $2}' <<< "$parallel_out")
        echo "serial:   weight=$serial_weight time=${serial_time}s"
        echo "parallel: weight=$parallel_weight time=${parallel_time}s"
    done
}

plot() {
    python3 "$ROOT/scripts/plot_results.py"
}

case "${1:-}" in
    compile) compile_all ;;
    generate-graphs) generate_graphs ;;
    benchmark) benchmark ;;
    benchmark-scaling) shift; benchmark_scaling "$@" ;;
    compare) compare ;;
    plot) plot ;;
    *)
        echo "Usage: $0 <compile|generate-graphs|benchmark|benchmark-scaling|compare|plot>" >&2
        exit 1
        ;;
esac
