#!/usr/bin/env python3
# =============================================================================
# region_ds9.py
#
# Description:
#   Converts DS9 WCS region files (circle, ellipse, annulus) into detector
#   coordinates for XMM-Newton analysis, creating per-detector region files 
#   for use in ESAS/SAS pipelines.
#
# Features:
#   - Supports 'circle', 'ellipse', and 'annulus' regions in DS9 format
#   - Converts WCS regions to detector coordinates using pysas.ecoordconv
#   - Outputs formatted region files and CLI-compatible region strings
#
# Usage Example:
#   python region_ds9.py --analysis-root /path/to/analysis \
#                       --script-path /path/to/scripts \
#                       --obs-id 0881900301 \
#                       --region both
#
# Required:
#   - pysas (for ecoordconv)
#   - set_SAS_variables.sh in script path
#
# ============================================================================

import os
import json
import subprocess
import re
import io
import argparse
import sys

import numpy as np
from contextlib import redirect_stdout


PIXELS_PER_ARCSEC = 20.0   # 0.05"/pix


def sky_to_det(w, imageset: str, ra_deg: float, dec_deg: float) -> tuple[float, float]:
    """
    Convert an arbitrary sky position (RA,Dec in deg) to detector (DETX, DETY)
    using pysas.ecoordconv for the given imageset.

    Returns
    -------
    (detx, dety) : tuple[float, float]
    """
    inargs = [
        f'imageset={imageset}',
        'withcoords=yes',
        'coordtype=eqpos',
        f'x={ra_deg}',
        f'y={dec_deg}',
    ]
    f = io.StringIO()
    with redirect_stdout(f):
        w('ecoordconv', inargs).run()
    s = f.getvalue()
    det_xy = re.findall(r"([^\n]*?DETX[^\n]*)", s)[0].split()[-2:]
    return float(det_xy[0]), float(det_xy[1])


def load_sas_env_from_script(obs_id: str, script_path: str, build: bool = False):
    """
    Loads SAS and HEASoft environment variables for a given XMM observation by 
    sourcing the provided set_SAS_variables.sh script and updating the current 
    Python process environment.

    Parameters
    ----------
    obs_id : str
        XMM observation ID.
    script_path : str
        Directory containing set_SAS_variables.sh.
    build : bool, optional
        Whether to (re)build CCF files (default: False).
    """
    script = f"{script_path}/set_SAS_variables.sh"
    build_flag = "true" if build else "false"

    # IMPORTANT: redirect all output from the shell script to /dev/null
    cmd = f'''bash -lc 'source "{script}" --obs-id "{obs_id}" --build-ccf "{build_flag}" >/dev/null 2>&1; python3 - << "PY"
import os, json
keys = ["SAS_DIR","SAS_PATH","SAS_CCFPATH","SAS_ODF","SAS_CCF","HEADAS","PATH","LD_LIBRARY_PATH","DYLD_LIBRARY_PATH"]
print(json.dumps({{k: os.environ.get(k, "") for k in keys}}))
PY' '''
    env_json = subprocess.check_output(cmd, shell=True, text=True)
    os.environ.update(json.loads(env_json))


def parse_wcs_region(region_text):
    """
    Parses a DS9 WCS region line and returns the region type and argument list.

    Parameters
    ----------
    region_text : str
        A single region string from a DS9 .reg file (e.g., 'circle(ra,dec,r)').

    Returns
    -------
    region_type : str
        Type of the region ('circle', 'ellipse', 'annulus').
    vals : list of float
        List of region parameters in the order expected by DS9/SAS.
    
    Raises
    ------
    ValueError
        If the region type is unsupported.
    """

    region_text = region_text.strip().lower()
    print(f"Parsing WCS region: {region_text}")
    if region_text.startswith("circle"):
        vals = list(map(float, re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", region_text)))
        return "circle", vals
    elif region_text.startswith("ellipse"):
        vals = list(map(float, re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", region_text)))
        return "ellipse", vals
    elif region_text.startswith("annulus"):
        vals = list(map(float, re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", region_text)))
        return "annulus", vals
    else:
        raise ValueError(f"Unsupported region type in: {region_text}")


def define_regfile_text(region_type, coord_det):
    """
    Builds DS9 region file content and a region string for use with SAS, given
    a region type and its detector-coordinate parameters.

    Parameters
    ----------
    region_type : str
        Type of region ('circle', 'ellipse', 'annulus').
    coord_det : list or tuple of float
        List of region parameters (detector coordinates/radii).

    Returns
    -------
    output : str
        Complete DS9 region file content (header + region line).
    reg_str : str
        Region string (e.g., 'circle(x,y,r)') for CLI/env usage.
    
    Raises
    ------
    ValueError
        If an unsupported region type is provided.
    """
    if region_type == "circle":
        reg_str = f"circle({coord_det[0]},{coord_det[1]},{coord_det[2]})"
    elif region_type == "ellipse":
        reg_str = f"ellipse({coord_det[0]},{coord_det[1]},{coord_det[2]},{coord_det[3]},{coord_det[4]})"
    elif region_type == "annulus":
        reg_str = f"annulus({coord_det[0]},{coord_det[1]},{coord_det[2]},{coord_det[3]})"
    else:
        raise ValueError(f"Unsupported region type: {region_type}")

    header = f"{reg_str}\n"
    output = (
        "# Region file format: DS9 version 4.1\n"
        "global color=green dashlist=8 3 width=1 font=\"helvetica 10 normal roman\" select=1 highlite=1 dash=0 fixed=0 edit=1 move=1 delete=1 include=1 source=1\n"
        "physical\n"
        f"{header}"
    )
    return output, reg_str


def get_wcs_coordinates(folder, src_or_bkg):
    """
    Loads and parses the last non-comment region line from a DS9 WCS region file.

    Parameters
    ----------
    folder : str
        Base analysis folder containing region files.
    src_or_bkg : str
        'src' for source or 'bkg' for background.

    Returns
    -------
    region_type : str
        Region type ('circle', 'ellipse', 'annulus').
    region_args : list of float
        Parsed region parameters (WCS coordinates/radii).
    """
    regfile = f'{folder}reg/{src_or_bkg}/wcs.reg'

    with open(regfile) as f:
        lines = [line.strip() for line in f if line.strip() and not line.startswith("#")]
        region_line = lines[-1]  # Last non-comment, non-empty line

    region_type, region_args = parse_wcs_region(region_line)

    print(f"Read WCS region from {regfile}: {region_line} -> type: {region_type}, args: {region_args}")
    return region_type, region_args


def get_region(folder, script_path, obs_id, region_flag='both', det_list=None, detector_list=None):
    """
    Converts WCS regions to detector coordinates for all requested detectors,
    generates DS9 region files, and returns region strings for use in the pipeline.

    Parameters
    ----------
    folder : str
        Path to analysis directory (must end with '/').
    script_path : str
        Directory containing SAS environment scripts.
    obs_id : str
        XMM observation ID.
    region_flag : str, optional
        'src', 'bkg', or 'both' (default: 'both').
    det_list : list of str, optional
        List of detector short names (default: ['m1', 'm2', 'pn']).
    detector_list : list of str, optional
        List of detector tags (default: ['mos1S001', 'mos2S002', 'pnS003']).

    Returns
    -------
    list or tuple of list
        List(s) of region strings for each detector and region type.
    """


    if det_list is None:
        det_list = ['m1', 'm2', 'pn']
    if detector_list is None:
        detector_list = ['mos1S001','mos2S002','pnS003']

    # call once before pysas/ecoordconv
    load_sas_env_from_script(obs_id, script_path=script_path, build=False)
    from pysas.wrapper import Wrapper as w # type: ignore

    src_regions, bkg_regions = [], []
    if region_flag == 'src':
        region = ['src']
    elif region_flag == 'bkg':
        region = ['bkg']
    else:
        region = ['src', 'bkg']

    for src_or_bkg in region:
        region_type, wcs_coord = get_wcs_coordinates(folder, src_or_bkg)
        print(f"WCS region for {src_or_bkg}: type={region_type}, coords={wcs_coord}")

        # Get center (WCS x, y)
        x_wcs, y_wcs = wcs_coord[0], wcs_coord[1]

        for det, detector in zip(det_list, detector_list):
            print(detector)
            print(src_or_bkg)

            # Convert WCS to detector coordinates
            imageset = f'{folder}/{det}/{detector}-allimc.fits'
            detx, dety = sky_to_det(w, imageset, x_wcs, y_wcs)

            # Now build the detector-region argument list:
            if region_type == "ellipse":
                # WCS params from DS9: [RA (deg), Dec (deg), major("), minor("), PA(deg)]
                ra_c, dec_c, major_arcsec, minor_arcsec, pa_deg = wcs_coord

                # --- Build a sky point at the tip of the MAJOR axis ---
                # DS9 WCS ellipse angle (PA) is CCW from North (i.e., from +Dec).
                # East component uses sin(PA); North uses cos(PA).
                th = np.deg2rad(pa_deg)
                major = major_arcsec if major_arcsec >= minor_arcsec else minor_arcsec
                east_arcsec  = np.sin(th) * major
                north_arcsec = np.cos(th) * major

                # Convert arcsec to degrees; RA needs cos(dec) scaling
                cosdec = np.cos(np.deg2rad(dec_c))
                dra_deg  = (east_arcsec  / (3600.0 * max(cosdec, 1e-12)))  # East-positive
                ddec_deg = (north_arcsec / 3600.0)

                ra_tip  = ra_c  + dra_deg
                dec_tip = dec_c + ddec_deg
                print(f"Tip of major axis at (RA,Dec) = ({ra_tip},{dec_tip})")

                # Convert to detector coordinates
                detx0, dety0 = sky_to_det(w,  imageset, ra_c,  dec_c)
                detx1, dety1 = sky_to_det(w,  imageset, ra_tip, dec_tip)
                print(f"Tip of major axis at (DETX,DETY) = ({detx1},{dety1})")

                # Detector-frame position angle: CCW from DETY axis
                dx, dy = (detx1 - detx0), (dety1 - dety0)
                print(f"dx, dy = {dx}, {dy}")
                det_pa = ((np.degrees(np.arctan2(dy, dx)) - 90) % 360.0)

                det_params = [
                    detx0, dety0,
                    major_arcsec * PIXELS_PER_ARCSEC,   # major in detector pixels
                    minor_arcsec * PIXELS_PER_ARCSEC,   # minor in detector pixels
                    det_pa
                ]

            elif region_type == "circle":
                det_params = [detx, dety, wcs_coord[2] * PIXELS_PER_ARCSEC]
 
            elif region_type == "annulus":
                det_params = [
                    detx, dety,
                    wcs_coord[2] * PIXELS_PER_ARCSEC,   # r_in
                    wcs_coord[3] * PIXELS_PER_ARCSEC,   # r_out
                ]
            else:
                raise ValueError(f"Unsupported region type: {region_type}")

            # Now create DS9 region file and string:
            output, region_string = define_regfile_text(region_type, det_params)
            reg_outfile = '{}reg/{}/{}.reg'.format(folder, src_or_bkg, det)
            with open(reg_outfile, 'w') as output_file:
                output_file.write(output)

            print(output)
            print(region_string)
            if src_or_bkg == 'src':
                src_regions.append(region_string)
            else:
                bkg_regions.append(region_string)


    if region_flag == 'src':
        return src_regions
    elif region_flag == 'bkg':
        return bkg_regions
    else:
        return src_regions, bkg_regions


# ---------------- CLI wrapper ----------------
def parse_cli():
    ap = argparse.ArgumentParser(description="Make per-detector DS9 physical regions from a WCS region.")
    ap.add_argument("--analysis-root", required=True, help="Path to .../observation_data/<obs_id>/analysis/ (folder)")
    ap.add_argument("--script-path", required=True, help="Folder containing set_SAS_variables.sh")
    ap.add_argument("--obs-id", required=True, help="Observation ID (e.g. 0922150101)")
    ap.add_argument("--region", choices=["src","bkg","both"], default="both", help="Which region set(s) to process")
    ap.add_argument("--detectors", nargs="*", choices=["m1","m2","pn"], help="Subset; default is all")
    ap.add_argument("--tags", nargs="*", help="Detector tags aligned with --detectors, e.g. mos1S001 mos2S002 pnS003")
    return ap.parse_args()

if __name__ == "__main__":
    args = parse_cli()

    # normalize params
    folder = args.analysis_root if args.analysis_root.endswith("/") else args.analysis_root + "/"
    det_list = args.detectors if args.detectors else ['m1','m2','pn']
    if args.tags:
        detector_list = args.tags
        if len(detector_list) != len(det_list):
            print("ERROR: --tags must have same length as --detectors", file=sys.stderr)
            sys.exit(2)
    else:
        default_map = {'m1':'mos1S001','m2':'mos2S002','pn':'pnS003'}
        detector_list = [default_map[d] for d in det_list]

    out = get_region(
        folder=folder,
        script_path=args.script_path,
        obs_id=args.obs_id,
        region_flag=args.region,
        det_list=det_list,
        detector_list=detector_list,
    )

    # summary output
    print("\n=== DS9 region summary ===")
    if isinstance(out, tuple):
        src, bkg = out
        for s in src:
            print("src:", s)
        for b in bkg:
            print("bkg:", b)
    else:
        for s in out:
            print(s)