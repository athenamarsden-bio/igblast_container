# AIRU Custom IgBlast Container

This container functions to annotate airr-seq sequences as part of various B-cell analytic pipelines. It automatically pulls data from OGRDB (https://ogrdb.airr-community.org/) during container building. The container can also take custom fasta inputs to generate temporary V, D and J databases for annotation. 

The build process also loads in a run script for ease of use, the usage for the run script is detailed below.

## Example and Usage

### Example

```bash
singularity run path/to/igblast_custom.sif/ \
  --input your_input \
  --output your_output \
  --outfmt "19" \ #full airr table
  --extend_5_prime \
  --extend_3_prime
```

### Usage

```
Usage: run_igblast_custom.sh --input <fasta_file> [--output <output_tsv>] [--threads <num>] \
          [--extend_5_prime] [--extend_3_prime] [--outfmt <format_string>] \
          [--custom_v_fasta <v_fasta>] [--custom_d_fasta <d_fasta>] [--custom_j_fasta <j_fasta>]

Arguments:
  --input           : Path to the input FASTA file (required).
  --output          : Path for the output file (default: /data/igblast_results.tsv).
  --threads         : Number of threads for IgBlast (default: 1).
  --extend_5_prime  : Enable 5' V-gene alignment extension (IgBlast -extend_align5end).
  --extend_3_prime  : Enable 3' V-gene alignment extension (IgBlast -extend_align3end).
  --outfmt          : IgBlast output format string (default: "7" for AIRR TSV).
                      Examples: "7" (AIRR), "19" (Extended AIRR with all fields),
                      "6 qseqid sseqid pident ..." (custom tabular).
  --custom_v_fasta  : Path to a custom FASTA file for the V-gene database.
                      This will override the default OGRDB database.
  --custom_d_fasta  : Path to a custom FASTA file for the D-gene database.
  --custom_j_fasta  : Path to a custom FASTA file for the J-gene database.
  --species_config  : (Info) This script uses IgBlast configured for raw species name: 'Homo sapiens'.
                      The germline DB paths are constructed using sanitized name: 'Homo_sapiens'.
```
