# XMM-Newton ESAS Pipeline

This repository contains a practical workflow for reducing XMM-Newton observations with SAS/ESAS, handling backgrounds with a double-subtraction method. It takes you from ODFs to cleaned events, regions/masks, images and spectra, and finally XSPEC fits.

---

## Quick Start

0. Initial preparation:
    * You must have SAS (22.1.0)/ Heasoft (6.35.1) installed.
    * CCF should be loaded and appropriate path set.
    * You must have outer directores/ files: scripts, blank_all, observation\_data, and blank\_sky\_files.
    * Adjust `resolve_paths.sh` with your directories if using nonstandard directories.
    * Activate whatever `sas_env` you use.
    * It is probably good to export at least OBS\_DIR, BASE\_DIR, SCRIPTS\_DIR.
    * Also a good idea to run `set_SAS_variables.sh` from your base shell.

1. Directory creation, file download, flare filtering:
    * For existing data-reductions, a lot of this may be done.
    * Can be completed manually or with `xmm_pipeline_1.sh`.
    * Neglect `--obs-id` and `--base-dr` if set elsewhere.

```bash
./xmm_pipeline_1.sh --obs-id 0922150101 --base-dir /abs/path/to/BASE_DIR --use-startsas yes --build-ccf yes
```

This retrieves data (via startsas), processes calibration, runs odfingest, generates light curves, and prompts you to choose soft-proton flare rates. Chosen rates are saved to `analysis/config/rates.env`.

2. Create cheese masks:
    * You will likely have to run a couple times for fine tuning, use `--with-cheese false` after initial run.
    * You can set ***many*** cheese parameters individually.

```bash
./xmm_pipeline_2.sh --create-files yes --with-cheese yes
```

3. Detector data-reduction:
    * You must first create background and source wcs.reg files.
    * Filters flares and extracts spectra from all detectors.
    * Performs double-subtraction.

```bash
./xmm_pipeline_3.sh --run-all yes --build-regions yes --subtraction2 yes --vig-mode obs
```


4. Image creation and spectral fitting:
    * Image processing takes a long time, for a quick look at spectra only use `--run-images no`
    * Xspec will prompt to open an interactive terminal and save logs to `analysis/QA`

```bash
./xmm_pipeline_4.sh --run-images yes --run-xspec yes
```

---

## Overview

What this suite does:

- `xmm_pipeline_1.sh`
    * Initializes SAS and required paths for a given OBS\_ID.
    * Retrieves ODF files automatically via startsas.
    * Process and CCF and creates event files from ODFs.
    * Prompts for and persists flare cut rates for reproducibility.

- `xmm_pipeline_2.sh`
    * Create and process source files for use with `cheese`.
    * Initial run of `cheese` to create `emllist`.
    * Fills missing values in `emllist` and makes cheese masks.
    * Displays mask and observation in ds9, use blink/fade to compare.

- `xmm_pipeline_3.sh`
    * Identifies bad MOS CCDs via emanom and persists exclusions.
    * Converts DS9 WCS regions to detector coordinates and exports them as env vars.
    * Produces detector-specific images, masks, and spectra suitable for double subtraction.
    * Runs double-subtracted XSPEC fits with grouping.

- `xmm_pipeline_4.sh`
    * Creates binned/ smoothed final images:
        - pn/mosspectra -> pn/mosback -> combimage -> binadapt
    * Creates and fits XSpec model, saving output and plots to `analysis/QA`.
    * Will prompt for nH and z.
    * Opens interactive XSpec terminal.


---

## Prerequisites

### Directory layout (expected)

Keep this structure to avoid early exits and missing-path errors.

Paths and files that must exist before reduction:

```
BASE_DIR/
  scripts/                          # All scripts from this pipeline
  blank_all/                        # Template directory
  blank_sky_files/                  # Holds raw blank sky files
    vignette/                       # Holds vignette corrected files
  observation_data/
```
Complete path structure:
```
BASE_DIR/
  scripts/ 
  blank_all/
  blank_sky_files/
    vignette/
  observation_data/   
    <OBS_ID>/
      odf/                          # raw ODF files
      analysis/
        m1/                         # ALL MOSS001 specific files from xmm_pipeline_3
        m2/                         # M2 specific files
        pn/                         # PN specific files
        mask/                       # Cheese files
        reg/
          src/wcs.reg               # DS9 WCS region for source
          bkg/wcs.reg               # DS9 WCS region for background
        subtracted/                 # Grouped spectra
            run_xspec_wrapper.sh    # XSpec terminal script
            savexspec.xcm           # Initial xspec model
        images/                     # All image processing files (a LOT)
        old_files/                  # Intermediate data files
        config/                     # *.env (rates, ccds, regions, spectra)
        QA/                         # Logs and quick diagnostics
            logs/                   # All xmm_pipelin_x log files
```


### External software

* SAS/ESAS (22.1.0)installed and correctly sourced in your shell.
* HEASoft (6.35.1) with XSPEC
* DS9 for drawing WCS regions.

Note: SAS/ESAS/HEASoft are not conda-managed here.


### Environment Setup (Python)

The pipeline is primarily Bash. The Python piece is a small WCS helper. If you want a clean Python environment, you can use the optional environment.yml at the end of this README. Otherwise, your system Python is fine.


### Environment variables (recommended)

You can either export these once per shell, or pass them as CLI flags.

* OBS\_ID: the XMM observation ID (e.g., 0881900301)
* BASE\_DIR or env \XMM_BASE_DIR: absolute path to the project base

---

## Outputs

* Event files: standardized names under the working directory (e.g., mos1S001.fits, mos2S002.fits, pnS003.fits, pnS003-oot.fits).
* Flare thresholds: analysis/config/rates.env
* CCD exclusions: analysis/config/ccds.env
* Region exports: analysis/config/regions.env
* Spectral products: detector-specific subfolders in analysis/det, plus any double-subtracted products in analysis/subtracted
* Background-subtracted exposure corrected images in analysis/images
* QA logs: analysis/QA/logs
---

## Troubleshooting and Tips

SAS not found after init:

* If `sasversion` is not found, your SAS init did not export the environment. Source your SAS setup script manually, verify `sasversion`, then re-run.

Region build fails:

* Ensure DS9 region files exist and are WCS-based:

  * analysis/reg/src/wcs.reg
  * analysis/reg/bkg/wcs.reg
* Re-run `make_regions.sh` if you changed regions.

Non-standard exposure labels (S002, U001, segmented):

* Adjust `create_events.sh` glob rules or provide merged/renamed files so pipeline finds mos1S001, mos2S002, pnS003 consistently.
* If you have multiple segments within a single OBS\_ID, you'll probably have to run a lot manually
* If you need to combine multiple OBS\_IDs scientifically, run the pipeline on each and combine products with your preferred upstream method (e.g., mosaic or joint fitting), as appropriate for your science case.


Single source of truth for helpers:

* Ensure every script sources the same helpers.sh. Avoid duplicate or older versions of logging/tag functions in the tree.

Shell portability:

* Scripts use bash features (process substitution, arrays). Keep #!/usr/bin/env bash and set -euo pipefail. If you need broader POSIX sh compatibility, some constructs in run_verbose and tee pipelines would need adjustment.

Verbosity:

* Use `SAS_VERBOSE_LEVEL=2` or `--verbose 2` for detailed tee logging of stdout/stderr with timestamps.
* `--verbose 1` will log all stdout/stderr and display stderr.
* `--verbose 0` will log and display stderr only. 
* All custom messages are sent to stderr and always visible.

---

## Script Index (what to run when you need X)

* `xmm_pipeline_1.sh`: Build and process initial files, set flare rate.
* `xmm_pipeline_2.sh`: Build cheese masks
* `xmm_pipeline_3.sh`: Run per-detector data-reduction and double-subtraction.
* `xmm_pipeline_4.sh`: Create final spectral fit and cleaned images.

* `create_events.sh`: Run when you have ODFs and need standardized event files; can also run espfilt for flare filtering.
* `light_curves.sh`: Produce and inspect light curves to choose or validate flare thresholds.
* `filter_flares.sh`: Standalone flare filtering helper.

* `make_cheese.sh`: Point-source detection and mask production.
* `make_regions.sh`: Converts DS9 WCS regions to detector coordinates and writes analysis/config/regions.env.
* `region_ds9.py`: Python helper used by region-building.

* `run_det.sh`: Per-detector processing invoked by Stage 3; use directly if iterating on a single detector.
* `fparkey_bkg.sh`: Set blank-sky header date to match observation.
* `proton_blank.sh`: Apply flare rate to blank-sky files.
* `spectra_src.sh` and `spectra_bkg.sh`: Build source and background spectra per detector from your regions.


* `double_subtraction.sh`: Performs double-subtraction and prepares XSPEC-ready grouped spectra.
* `run_xspec.sh`: XSPEC driver for running fits in a controlled, logged manner.
* `make_images.sh`: Imaging products per detector (exposure-corrected images, etc.).

* `set_SAS_variables.sh`: SAS/ESAS environment initialization. Source this before running stages if not using the stage wrapper.
* `resolve_paths.sh`: Centralized path checks/exports; sourced by stage wrappers.
* `helpers.sh`: Shared logging, prompting, and utility functions.


---

## Optional: environment.yml (Python utilities only)

If you want a small, clean Python environment, create the env with `conda env create -f environment.yml`. Probably not much help.

```yaml
name: xmm-esas
channels:
  - conda-forge
  - defaults
dependencies:
  - python=3.12
```

Note: SAS/ESAS/HEASoft are installed separately and must be sourced in your shell before running pipeline stages. SAS may require a different env.
