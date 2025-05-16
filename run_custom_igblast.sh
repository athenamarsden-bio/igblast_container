#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Default values ---
OUTPUT_FILE="/data/igblast_results.tsv"
THREADS=1
INPUT_FASTA=""
ENABLE_EXTEND_5_PRIME=false
ENABLE_EXTEND_3_PRIME=false
OUTPUT_FORMAT="7"

# --- Read necessary environment variables set in Singularity %environment ---
# RAW_SPECIES (e.g. "Homo sapiens")
# BUILT_SPECIES (e.g., Homo_sapiens) is used for constructing DB paths.
# OGRDB_COMBINED_DIR, IGDATA, IGBLAST_VERSION.
# The script uses these directly from the environment.

# --- Helper function for usage ---
usage() {
  echo "Usage: $(basename "$0") --input <fasta_file> [--output <output_tsv>] [--threads <num>] \\"
  echo "          [--extend_5_prime] [--extend_3_prime] [--outfmt <format_string>]"
  echo ""
  echo "Arguments:"
  echo "  --input           : Path to the input FASTA file (required)."
  echo "  --output          : Path for the output file (default: /data/igblast_results.tsv)."
  echo "  --threads         : Number of threads for IgBlast (default: 1)."
  echo "  --extend_5_prime  : Enable 5' V-gene alignment extension (IgBlast -extend_align5end)."
  echo "  --extend_3_prime  : Enable 3' V-gene alignment extension (IgBlast -extend_align3end)."
  echo "  --outfmt          : IgBlast output format string (default: \"7\" for AIRR TSV)."
  echo "                      Examples: \"7\" (AIRR), \"19\" (Extended AIRR with all fields),"
  echo "                      \"6 qseqid sseqid pident ...\" (custom tabular)."
  echo "  --species_config  : (Info) This script uses IgBlast configured for raw species name: '${RAW_SPECIES}'."
  echo "                      The germline DB paths are constructed using sanitized name: '${BUILT_SPECIES}'."
  exit 1
}

# --- Parse command-line arguments ---
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --input) INPUT_FASTA="$2"; shift ;;
    --output) OUTPUT_FILE="$2"; shift ;;
    --threads) THREADS="$2"; shift ;;
    --extend_5_prime) ENABLE_EXTEND_5_PRIME=true ;;
    --extend_3_prime) ENABLE_EXTEND_3_PRIME=true ;;
    --outfmt) OUTPUT_FORMAT="$2"; shift ;;
    --help) usage ;;
    *) echo "Unknown parameter passed: $1"; usage ;;
  esac
  shift
done

# --- Validate input ---
if [ -z "$INPUT_FASTA" ]; then
  echo "Error: Input FASTA file (--input) is required."
  usage
fi

if [ ! -f "$INPUT_FASTA" ]; then
  echo "Error: Input FASTA file not found at $INPUT_FASTA"
  exit 1
fi

# Determine IgBlast organism name for -organism flag and for locating auxiliary data file.
IGBLAST_ORGANISM_NAME_FOR_AUX=$(printf '%s' "${RAW_SPECIES}" | tr '[:upper:]' '[:lower:]' | sed 's/ /_/g') 
IGBLAST_ORGANISM_NAME_FOR_IGBLAST=${IGBLAST_ORGANISM_NAME_FOR_AUX} 

AUX_FILE_SUFFIX="_gl.aux"
AUX_DIR_PATH="${IGDATA}/optional_file" 
AUX_FILE_PATH="${AUX_DIR_PATH}/${IGBLAST_ORGANISM_NAME_FOR_AUX}${AUX_FILE_SUFFIX}"

if [ ! -d "${IGDATA}" ]; then
    echo "Error: IGDATA directory not found at ${IGDATA}. This should be set by the Singularity container environment."
    exit 1
fi
if [ ! -d "${AUX_DIR_PATH}" ]; then
    ALT_AUX_DIR_PATH="${IGDATA}/internal_data/optional_file"
    if [ -d "${ALT_AUX_DIR_PATH}" ]; then
        AUX_DIR_PATH="${ALT_AUX_DIR_PATH}"
        AUX_FILE_PATH="${AUX_DIR_PATH}/${IGBLAST_ORGANISM_NAME_FOR_AUX}${AUX_FILE_SUFFIX}" 
    else
        echo "Error: Neither ${IGDATA}/optional_file nor ${IGDATA}/internal_data/optional_file exist. Cannot find auxiliary data directory."
        exit 1
    fi
fi

if [ ! -f "$AUX_FILE_PATH" ]; then
    IGBLAST_ORGANISM_NAME_FIRST_WORD=$(printf '%s' "${RAW_SPECIES}" | tr '[:upper:]' '[:lower:]' | cut -d' ' -f1)
    AUX_FILE_PATH_FIRST_WORD="${AUX_DIR_PATH}/${IGBLAST_ORGANISM_NAME_FIRST_WORD}${AUX_FILE_SUFFIX}"
    if [ -f "$AUX_FILE_PATH_FIRST_WORD" ]; then
        AUX_FILE_PATH="$AUX_FILE_PATH_FIRST_WORD"
        IGBLAST_ORGANISM_NAME_FOR_IGBLAST=${IGBLAST_ORGANISM_NAME_FIRST_WORD} 
    else
        if [ "$BUILT_SPECIES" == "Homo_sapiens" ] && [ -f "${AUX_DIR_PATH}/human_gl.aux" ]; then
            AUX_FILE_PATH="${AUX_DIR_PATH}/human_gl.aux"
            IGBLAST_ORGANISM_NAME_FOR_IGBLAST="human"
        elif [ "$BUILT_SPECIES" == "Mus_musculus" ] && [ -f "${AUX_DIR_PATH}/mouse_gl.aux" ]; then
             AUX_FILE_PATH="${AUX_DIR_PATH}/mouse_gl.aux"
             IGBLAST_ORGANISM_NAME_FOR_IGBLAST="mouse"
        else
            echo "Error: Cannot find auxiliary file. Tried:"
            echo "  ${AUX_FILE_PATH} (derived from ${IGBLAST_ORGANISM_NAME_FOR_AUX})"
            echo "  ${AUX_FILE_PATH_FIRST_WORD} (derived from ${IGBLAST_ORGANISM_NAME_FIRST_WORD})"
            echo "Exiting."
            exit 1
        fi
    fi
fi

echo "--- Running IgBlast ---"
echo "Species (configured for filenames): ${BUILT_SPECIES}" 
echo "IgBlast Organism Name (for -organism and aux data): ${IGBLAST_ORGANISM_NAME_FOR_IGBLAST}"
echo "Input FASTA: ${INPUT_FASTA}"
echo "Output File: ${OUTPUT_FILE}"
echo "Output Format: ${OUTPUT_FORMAT}"
echo "Threads: ${THREADS}"
echo "5' V-gene extension enabled: ${ENABLE_EXTEND_5_PRIME}"
echo "3' V-gene extension enabled: ${ENABLE_EXTEND_3_PRIME}"
echo "Auxiliary data file: ${AUX_FILE_PATH}"
echo "OGRDB Combined Directory: ${OGRDB_COMBINED_DIR}" 
echo "IGDATA Path: ${IGDATA}" 
echo "IgBlast Version (runtime): ${IGBLAST_VERSION}" 

# --- Define paths to FASTA files (for validation) and BLAST DB base names (for igblastn) ---
# OGRDB_COMBINED_DIR and BUILT_SPECIES (e.g. Homo_sapiens) are from Singularity %environment

# FASTA file paths (for checking existence/content)
DB_V_FASTA_PATH="${OGRDB_COMBINED_DIR}/${BUILT_SPECIES}_OGRDB_V.fasta"
DB_J_FASTA_PATH="${OGRDB_COMBINED_DIR}/${BUILT_SPECIES}_OGRDB_J.fasta"
DB_D_FASTA_PATH="${OGRDB_COMBINED_DIR}/${BUILT_SPECIES}_OGRDB_D.fasta"

# BLAST Database base paths (for igblastn -germline_db_* arguments)
# These should be the full path to the base name used by makeblastdb's -out
DB_V_BLAST_BASE="${OGRDB_COMBINED_DIR}/${BUILT_SPECIES}_OGRDB_V" # No .fasta
DB_J_BLAST_BASE="${OGRDB_COMBINED_DIR}/${BUILT_SPECIES}_OGRDB_J" # No .fasta
DB_D_BLAST_BASE="${OGRDB_COMBINED_DIR}/${BUILT_SPECIES}_OGRDB_D" # No .fasta


# --- Validate FASTA database files (source files for BLAST DBs) ---
if [ ! -s "$DB_V_FASTA_PATH" ]; then echo "Error: Source V-gene FASTA DB is empty or not found: $DB_V_FASTA_PATH"; exit 1; fi
if [ ! -s "$DB_J_FASTA_PATH" ]; then echo "Error: Source J-gene FASTA DB is empty or not found: $DB_J_FASTA_PATH"; exit 1; fi
if [ ! -s "$DB_D_FASTA_PATH" ]; then 
    echo "Warning: Source D-gene FASTA DB is empty or not found: $DB_D_FASTA_PATH. This is okay if not analyzing IGH or if D genes are not used."
fi

IGBLAST_ARGS=() 
# Only add -germline_db_D if the D gene FASTA file exists and is not empty (implies DB was made)
if [ -s "$DB_D_FASTA_PATH" ]; then
    IGBLAST_ARGS+=("-germline_db_D" "$DB_D_BLAST_BASE")
fi
if [ ! -f "$AUX_FILE_PATH" ]; then echo "Error: Auxiliary data file not found: $AUX_FILE_PATH"; exit 1; fi

if [ "$ENABLE_EXTEND_5_PRIME" = true ]; then
  IGBLAST_ARGS+=("-extend_align5end")
fi
if [ "$ENABLE_EXTEND_3_PRIME" = true ]; then
  IGBLAST_ARGS+=("-extend_align3end")
fi

echo "Running IgBlast command..."
igblastn -ig_seqtype Ig \
  -germline_db_V "$DB_V_BLAST_BASE" \
  "${IGBLAST_ARGS[@]}" \
  -germline_db_J "$DB_J_BLAST_BASE" \
  -auxiliary_data "$AUX_FILE_PATH" \
  -organism "${IGBLAST_ORGANISM_NAME_FOR_IGBLAST}" \
  -query "$INPUT_FASTA" \
  -out "$OUTPUT_FILE" \
  -outfmt "${OUTPUT_FORMAT}" \
  -num_threads "${THREADS}"

echo "--- IgBlast processing complete. Output at: ${OUTPUT_FILE} ---"
