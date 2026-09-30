# extract_f0_formants.praat
#
# Batch extraction of f0 and formant summary statistics from a folder of
# .wav files. General-purpose version (not tied to any particular corpus).
# Outputs one row per file to a CSV.
#
# Measures per file:
#   - duration (s)
#   - f0 mean and SD (Hz)
#   - F1-F4 means (Hz)
#   - formant mean: arithmetic mean of F1-F4 (Hz)
#   - formant dispersion, Df = (F4 - F1) / 3 (Fitch, 1997) (Hz)
#
# Formant settings follow Hilton, Moser et al. (2022): Burg method,
# 5 formants, window 0.025 s, pre-emphasis from 50 Hz.
#
# Usage:
#   - Run from the Praat Objects window (Open > Run script...)
#   - Point 'directory' at the folder containing the .wav files
#   - Adjust pitch/formant bounds to the speakers being analysed
#     (see the comments in the form).
#   - Undefined values (e.g. unvoiced or silent files) are written as NA,
#     so the CSV can be read directly into R.
#
# Author: Juan David Leongómez — Universidad El Bosque
#
# License: GNU General Public License v3.0 or later (GPL-3.0-or-later)
#   <https://www.gnu.org/licenses/gpl-3.0.html>

form Batch f0 and formant extraction
    comment Directory of .wav files:
    text directory /path/to/recordings/
    comment Full path of output CSV (include filename and extension):
    text output_file /path/to/output/acoustics_output.csv
    comment Pitch floor -- use 75 for males, 100 for females
    positive pitch_floor_(Hz) 75
    comment Pitch ceiling -- use 300 for males, 600 for females
    positive pitch_ceiling_(Hz) 500
    comment Maximum formant -- use 5000 for males, 5500 for females/children
    positive maximum_formant_(Hz) 5500
endform

# Accept the directory with or without a trailing slash
if right$ (directory$, 1) <> "/" and right$ (directory$, 1) <> "\"
    directory$ = directory$ + "/"
endif

# Handle existing output file
if fileReadable (output_file$)
    pauseScript: "The file " + output_file$ + " already exists! Overwrite?"
endif

writeFileLine: output_file$, "filename,duration_s,f0_mean_hz,f0_sd_hz,f1_mean_hz,f2_mean_hz,f3_mean_hz,f4_mean_hz,formant_mean_hz,df_hz"

fileList = Create Strings as file list: "fileList", directory$ + "*.wav"
n = Get number of strings

for i from 1 to n
    selectObject: fileList
    filename$ = Get string: i
    basename$ = filename$ - ".wav"

    sound = Read from file: directory$ + filename$
    duration = Get total duration

    # --- f0 ---
    pitch = To Pitch (ac): 0, pitch_floor, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitch_ceiling
    f0_mean = Get mean: 0, 0, "Hertz"
    f0_sd   = Get standard deviation: 0, 0, "Hertz"

    # --- Formants (F1-F4) ---
    selectObject: sound
    formant = To Formant (burg): 0, 5, maximum_formant, 0.025, 50
    for f from 1 to 4
        fmean[f] = Get mean: f, 0, 0, "hertz"
    endfor

    # Mean of F1-F4 (only if all four are defined)
    if fmean[1] <> undefined and fmean[2] <> undefined and fmean[3] <> undefined and fmean[4] <> undefined
        formant_mean = (fmean[1] + fmean[2] + fmean[3] + fmean[4]) / 4
    else
        formant_mean = undefined
    endif

    # Formant dispersion (Fitch, 1997): Df = (F4 - F1) / 3
    if fmean[1] <> undefined and fmean[4] <> undefined
        df = (fmean[4] - fmean[1]) / 3
    else
        df = undefined
    endif

    # Undefined values -> NA (read directly as NA in R)
    f0_mean$ = if f0_mean = undefined then "NA" else fixed$ (f0_mean, 3) fi
    f0_sd$   = if f0_sd   = undefined then "NA" else fixed$ (f0_sd, 3) fi
    for f from 1 to 4
        fmean$[f] = if fmean[f] = undefined then "NA" else fixed$ (fmean[f], 3) fi
    endfor
    formant_mean$ = if formant_mean = undefined then "NA" else fixed$ (formant_mean, 3) fi
    df$ = if df = undefined then "NA" else fixed$ (df, 3) fi

    appendFileLine: output_file$,
        ... basename$, ",",
        ... fixed$ (duration, 3), ",",
        ... f0_mean$, ",",
        ... f0_sd$, ",",
        ... fmean$[1], ",",
        ... fmean$[2], ",",
        ... fmean$[3], ",",
        ... fmean$[4], ",",
        ... formant_mean$, ",",
        ... df$

    # Clean up objects for this file before next iteration
    removeObject: pitch, formant, sound
endfor

removeObject: fileList

writeInfoLine: "Done. ", n, " files processed. Results written to ", output_file$
