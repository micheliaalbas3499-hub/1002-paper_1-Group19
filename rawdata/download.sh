#!/bin/bash -l
#SBATCH --job-name=NGS_download
#SBATCH --partition=msc_appbio
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=03:00:00
#SBATCH --output=download_%j.log

set -euo pipefail
module load sra-tools

# 1. Directories
BASE="/scratch/users/$USER/group_project_1002"
RAW="$BASE/rawdata"
META="$RAW/metadata.csv"
SRA="$BASE/sra_cache"
TMP="$BASE/fastq_work"

mkdir -p "$RAW/WGS" "$RAW/RNAseq" "$SRA" "$TMP"

# 2. Read metadata and download
tail -n +2 "$META" | cut -d',' -f1,2 | \
while IFS=',' read -r RUN TYPE; do

    # Identify sequencing type
    case "${TYPE,,}" in
        wgs) GROUP="WGS" ;;
        rna-seq|rnaseq) GROUP="RNAseq" ;;
        *) echo "Unknown assay: $TYPE"; exit 1 ;;
    esac

    [[ "$RUN" =~ ^SRR[0-9]+$ ]] || exit 1

    OUT="$RAW/$GROUP"
    WORK="$TMP/$RUN"

    R1="$OUT/${RUN}_1.fastq.gz"
    R2="$OUT/${RUN}_2.fastq.gz"

    echo "===== Processing $RUN ($GROUP) ====="

    # Skip completed FASTQ files
    if [[ -s "$R1" && -s "$R2" ]] &&
       gzip -t "$R1" "$R2"; then
        echo "$RUN already complete, skipping"
        continue
    fi

    # Prepare temporary directory
    rm -rf "$WORK"
    mkdir -p "$WORK/out" "$WORK/tmp"

    # Download SRA (resume supported)
    cd "$SRA"
    prefetch --max-size 50G "$RUN"

    # Convert SRA to paired FASTQ
    fasterq-dump "$RUN" \
        --split-files \
        -e 4 \
        -t "$WORK/tmp" \
        -O "$WORK/out"

    # Check FASTQ
    test -s "$WORK/out/${RUN}_1.fastq"
    test -s "$WORK/out/${RUN}_2.fastq"

    # Compress FASTQ
    if command -v pigz >/dev/null 2>&1; then
        pigz -p 4 "$WORK/out/"*.fastq
    else
        gzip "$WORK/out/"*.fastq
    fi

    # Verify and move files
    gzip -t "$WORK/out/"*.fastq.gz
    mv "$WORK/out/"*.fastq.gz "$OUT/"

    # Remove temporary files
    rm -rf "$WORK"

    echo "===== Complete: $RUN ====="

done

echo "All requested downloads finished!"
