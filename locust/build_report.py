#!/usr/bin/env python3
"""
build_report.py
Lê scenario_results/summary.csv e gera scenario_results/report.csv.
"""
 
import os, sys
import pandas as pd
 
CSV = "scenario_results/summary.csv"
OUT = "scenario_results/report.csv"
 
if not os.path.exists(CSV):
    sys.exit(f"Arquivo não encontrado: {CSV}\nRode run_scenarios.sh primeiro.")
 
df = pd.read_csv(CSV)
if df.empty:
    sys.exit("CSV vazio.")
 
df["linguagem"] = df["service"]
df["cache"]     = df["cache"].str.contains("com|with", case=False).astype(int)
 
# Colunas desejadas — inclui spawn_rate só se existir
base_cols = [
    "linguagem", "cache", "users",
    "total_requests", "failures", "failure_rate_pct",
    "avg_ms", "median_ms", "p75_ms", "p90_ms", "p95_ms", "p99_ms",
    "min_ms", "max_ms", "rps",
    "timestamp",
]
 
if "spawn_rate" in df.columns:
    base_cols.insert(3, "spawn_rate")
 
# Garante que só usa colunas que existem
cols = [c for c in base_cols if c in df.columns]
 
df[cols].to_csv(OUT, index=False)
print(f"Salvo: {OUT}")
print(df[cols].to_string(index=False))
 
