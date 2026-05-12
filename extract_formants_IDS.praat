# population_norms/extract_formants_IDS.praat
#
# Extract f0 and formant (F1-F4) summary statistics from IDS speech files.
# Outputs one row per file to a CSV.
#
# Adapted from Hilton & Moser et al. (2022) masterscript.praat:
#   https://github.com/themusiclab/infant-speech-song
#   see 'analysis/acoustics_processing/3_masterscript.praat'
#
# Usage:
#   - Run from the Praat Objects window (Open > Run script...)
#   - Point 'directory' at the folder containing the IDS speech .wav files
#     (vocalization type B from the Hilton et al. corpus, e.g. ACO01B.wav)
#   - Settings below are for female speakers; adjust pitch/formant bounds
#     for male speakers if needed.
#
# Author: Juan David Leongómez — Universidad El Bosque
#
# License: Creative Commons Attribution-NonCommercial-ShareAlike 4.0 (CC BY-NC-SA 4.0)
#   Adapted from CC BY-NC-SA 4.0-licensed code by Hilton, Moser et al. (2022).
#   This derivative work is distributed under the same terms.
#   <https://creativecommons.org/licenses/by-nc-sa/4.0/>

form Extract formant summary stats
    comment Directory of sound files (include trailing slash):
    text directory /path/to/ids_speech_clips/
    sentence Sound_file_extension .wav
    comment Full path of output CSV (include filename and extension):
    text resultsfile /path/to/output/formant_summary.csv
    comment Pitch floor -- use 100 for females, 75 for males
    positive minimum_pitch_(Hz) 100
    comment Pitch ceiling -- use 600 for females, 300 for males
    positive maximum_pitch_(Hz) 600
    comment Maximum formant -- use 5500 for females/children, 5000 for males
    positive maximum_formant_(Hz) 5500
endform

# Build file list
Create Strings as file list... list 'directory$'*'sound_file_extension$'
numberOfFiles = Get number of strings

# Handle existing output file
if fileReadable (resultsfile$)
    pause The file 'resultsfile$' already exists! Overwrite?
    filedelete 'resultsfile$'
endif

# Write CSV header
header$ = "filename,f0_mean,f0_sd,f1_mean,f2_mean,f3_mean,f4_mean'newline$'"
fileappend "'resultsfile$'" 'header$'

# Process each file
for d from 1 to numberOfFiles
    select Strings list
    filename$ = Get string... d
    dotInd = rindex (filename$, ".")
    soundname$ = left$ (filename$, dotInd - 1)

    Read from file... 'directory$''filename$'
    soundID = selected ("Sound")

    # --- Pitch object (f0 mean and SD) ---
    select 'soundID'
    To Pitch... 0 'minimum_pitch' 'maximum_pitch'
    pitchID = selected ("Pitch")

    f0_mean = Get mean... 0 0 Hertz
    f0_sd   = Get standard deviation... 0 0 Hertz

    # Replace undefined (silent/unvoiced files) with 0
    if f0_mean = undefined
        f0_mean = 0
    endif
    if f0_sd = undefined
        f0_sd = 0
    endif

    # --- Formant object (Burg, 5 formants) ---
    # Settings match Hilton et al.: window 0.025 s, pre-emphasis from 50 Hz
    select 'soundID'
    To Formant (burg)... 0 5 'maximum_formant' 0.025 50
    formantID = selected ("Formant")

    select 'formantID'
    f1_mean = Get mean... 1 0 0 Hertz
    f2_mean = Get mean... 2 0 0 Hertz
    f3_mean = Get mean... 3 0 0 Hertz
    f4_mean = Get mean... 4 0 0 Hertz

    # Replace undefined with 0
    if f1_mean = undefined
        f1_mean = 0
    endif
    if f2_mean = undefined
        f2_mean = 0
    endif
    if f3_mean = undefined
        f3_mean = 0
    endif
    if f4_mean = undefined
        f4_mean = 0
    endif

    # Format to 3 decimal places
    f0_mean$ = fixed$ (f0_mean, 3)
    f0_sd$   = fixed$ (f0_sd,   3)
    f1_mean$ = fixed$ (f1_mean, 3)
    f2_mean$ = fixed$ (f2_mean, 3)
    f3_mean$ = fixed$ (f3_mean, 3)
    f4_mean$ = fixed$ (f4_mean, 3)

    resultline$ = "'soundname$','f0_mean$','f0_sd$',"
    ... "'f1_mean$','f2_mean$','f3_mean$',"
    ... "'f4_mean$''newline$'"

    # Clean up objects for this file before next iteration
    select all
    minus Strings list
    Remove
endfor

select all
Remove

printline Done. Results written to 'resultsfile$'
