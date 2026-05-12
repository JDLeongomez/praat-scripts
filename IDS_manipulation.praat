# =============================================================================
# IDS Acoustic Manipulation Script
# =============================================================================
# Measures baseline f0 mean, f0 SD, and formant frequencies from a
# recording, creates and saves the 8 High/Low combinations (2×2×2 design),
# re-measures each output, and saves a full report as a text file.
#
# Manipulation magnitudes are expressed as fixed Hz offsets (f0 parameters)
# or a proportional scaling factor (formant frequencies), derived from
# between-speaker SDs of IDS speech in female speakers (Hilton et al. 2022,
# Nature Human Behaviour; n = 21 societies):
#   f0 mean : ±sd_f0mean_hz  (default 51 Hz = 1 × 50.8 Hz; Hilton et al. 2022)
#   f0 SD   : ±sd_f0sd_hz    (default 28 Hz = 1 × 28.4 Hz; Hilton et al. 2022)
#   Formant : ±factor_formant (default ±4.6% = 1 × CV 0.046; Hilton et al. 2022)
#
# Manipulation order:
#
#   Step 1 — Formant frequencies: Iterative LPC-based resynthesis on the ORIGINAL sound.
#                 factor_formant is the DESIRED OUTPUT proportional shift (e.g. 0.046 = ±4.6%).
#                 The script internally adjusts the synthesis ratio until the measured
#                 geometric mean of F1-F4 matches the target within ffreq_tolerance_hz.
#                 This mirrors the iterative f0 SD correction (procedure synthesizeF0).
#                 No PSOLA → pitch is genuinely untouched.
#                 Adapted from Praat Vocal Toolkit changeformants.praat.
#
#   Step 2 — f0 : Iterative affine correction (procedure synthesizeF0).
#                 Targets are absolute Hz values:
#                   target_mean = base_f0mean ± sd_f0mean_hz
#                   target_sd   = base_f0sd   ± sd_f0sd_hz
#                 Initial transform:
#                   slope     = target_sd / src_f0sd
#                   intercept = target_mean − src_f0mean × slope
#                   new_f0(t) = intercept + old_f0(t) × slope
#                 After each PSOLA resynthesis, the output SD is measured.
#                 If it differs from target_sd by more than sd_tolerance_hz,
#                 slope is multiplied by (target_sd / measured_sd) and the
#                 process repeats — up to max_iter times.
#                 Typically converges in 2–3 iterations.
#
# A single max_formant_hz setting is used for both LPC synthesis and post-
# manipulation measurement. Using the same ceiling for both ensures the Burg
# tracker finds formants at consistent positions before and after manipulation.
#
# Report filename: {sound_name}_mean+-{n}Hz_sd+-{n}Hz_formant+-{n}pct.txt
#
# Author: Juan David Leongómez — Universidad El Bosque
#
# License: GNU General Public License v2.0 or later (GPL-2.0-or-later)
#   Formant shift procedure adapted from Praat Vocal Toolkit changeformants.praat
#   (verify license at http://www.praatvocaltoolkit.com/). All other code is
#   original and released under GPL-2.0-or-later.
#   <https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>
# =============================================================================

form IDS Acoustic Manipulation
    comment Input sound file (full path):
    sentence Input_file /path/to/recording.wav
    comment Output directory (full path, with trailing slash):
    sentence Output_dir /path/to/output/
    comment f0 mean offset in Hz (default: 51 = 1 x 50.8 Hz; Hilton et al. 2022):
    positive sd_f0mean_hz 51
    comment f0 SD offset in Hz (default: 28 = 1 x 28.4 Hz; Hilton et al. 2022):
    positive sd_f0sd_hz 28
    comment Formant scaling factor (0.046 = +-4.6% = 1 x CV 0.046; Hilton et al. 2022):
    positive factor_formant 0.046
    comment --- f0 analysis settings ---
    positive pitch_floor_hz 100
    positive pitch_ceiling_hz 500
    comment --- f0 SD iterative correction ---
    positive sd_tolerance_hz 0.5
    integer max_iter 5
    comment --- Formant iterative correction ---
    positive ffreq_tolerance_hz 10
    integer max_ffreq_iter 12
    comment --- Formant analysis settings (used for both synthesis and measurement) ---
    comment Set to ~5500 Hz for females/children, ~5000 Hz for males
    positive max_formant_synth_hz 5500
    positive number_of_formants 5
endform

clearinfo

# =============================================================================
# Procedure: LPC-based proportional formant shift
#   Multiplies ALL formant frequencies by .ratio → shifts all formants proportionally.
#   No PSOLA — pitch is not altered.
#   Adapted from Praat Vocal Toolkit changeformants.praat.
#   Input:  .snd (Sound ID), .ratio (scale factor)
#   Output: lpc_ffreq_result (global Sound ID — caller must remove)
# =============================================================================
procedure shiftFormants: .snd, .ratio
    selectObject: .snd
    .sf_orig = Get sampling frequency
    .sf_low  = max_formant_synth_hz * 2

    selectObject: .snd
    .hf = Filter (stop Hann band): 0, max_formant_synth_hz, 100

    selectObject: .snd
    .rs = Resample: .sf_low, 10

    .formant_orig = noprogress nowarn To Formant (robust): 0.005, number_of_formants,
                   ... max_formant_synth_hz, 0.025, 50, 1.5, 5, 0.000001
    .lpc_orig = noprogress To LPC: .sf_low
    plusObject: .rs
    .source = Filter (inverse)

    selectObject: .formant_orig
    .formant_mod = Copy: "formant_mod"
    Formula (frequencies): "self * .ratio"

    .lpc_mod = noprogress To LPC: .sf_low
    plusObject: .source
    .tmp = Filter: "no"

    .rs_back = Resample: .sf_orig, 10
    Formula: "self + object[.hf]"
    Scale peak: 0.99
    lpc_ffreq_result = selected("Sound")

    removeObject: .hf, .rs, .formant_orig, .lpc_orig, .source,
                 ... .formant_mod, .lpc_mod, .tmp
    # .rs_back IS lpc_ffreq_result — caller removes it
endproc

# =============================================================================
# Procedure: synthesizeF0 — iterative affine f0 correction
#   Applies an affine transform to the pitch of .snd to hit target_mean and
#   target_sd, iterating until the measured output SD is within
#   sd_tolerance_hz of target_sd (or max_iter is reached).
#
#   Inputs (all global):
#     .snd         — source Sound ID (the formant-shifted sound)
#     .src_mean    — measured f0 mean of .snd
#     .src_sd      — measured f0 SD of .snd
#     .tgt_mean    — desired output f0 mean
#     .tgt_sd      — desired output f0 SD
#   Output: synth_result (global Sound ID — caller must remove)
#   Also sets synth_iter (number of iterations used) and synth_sd (final SD)
# =============================================================================
procedure synthesizeF0: .snd, .src_mean, .src_sd, .tgt_mean, .tgt_sd
    .slope     = .tgt_sd / .src_sd
    .intercept = .tgt_mean - .src_mean * .slope
    .iter      = 0
    .done      = 0

    while .done = 0
        .iter = .iter + 1

        # Build modified Pitch from .snd
        selectObject: .snd
        To Pitch (ac): 0.0, pitch_floor_hz, 15, "no", 0.03, 0.45,
                      ... 0.01, 0.35, 0.14, pitch_ceiling_hz
        .pitch = selected("Pitch")
        Formula: "if self = undefined then undefined else .intercept + self * .slope fi"
        Down to PitchTier
        .pt = selected("PitchTier")
        selectObject: .pitch
        Remove

        # PSOLA resynthesis
        selectObject: .snd
        To Manipulation: 0.01, pitch_floor_hz, pitch_ceiling_hz
        .manip = selected("Manipulation")
        plusObject: .pt
        Replace pitch tier
        selectObject: .pt
        Remove
        selectObject: .manip
        Get resynthesis (overlap-add)
        .result = selected("Sound")
        selectObject: .manip
        Remove

        # Measure output SD
        selectObject: .result
        To Pitch (ac): 0.0, pitch_floor_hz, 15, "no", 0.03, 0.45,
                      ... 0.01, 0.35, 0.14, pitch_ceiling_hz
        .meas_pitch = selected("Pitch")
        .meas_sd   = Get standard deviation: 0, 0, "Hertz"
        .meas_mean = Get mean: 0, 0, "Hertz"
        selectObject: .meas_pitch
        Remove

        # Check convergence
        .sd_err = abs(.meas_sd - .tgt_sd)
        if .sd_err <= sd_tolerance_hz or .iter >= max_iter
            .done = 1
        else
            # Multiplicative slope correction:
            # The PSOLA bias is approximately proportional, so scaling the
            # slope by (target / measured) corrects it on the next iteration.
            .slope     = .slope * (.tgt_sd / .meas_sd)
            # Recompute intercept using the fixed SOURCE mean (ffreq_sound
            # is always the input — its mean never changes between iterations).
            .intercept = .tgt_mean - .src_mean * .slope
            selectObject: .result
            Remove
        endif
    endwhile

    synth_result = .result
    synth_iter   = .iter
    synth_sd     = .meas_sd
    synth_mean   = .meas_mean
endproc

# =============================================================================
# Procedure: measure f0 mean, f0 SD, and formant geometric mean from a Sound object ID
# Formant ceiling matches synthesis ceiling (max_formant_synth_hz) to ensure
# the Burg tracker finds peaks at consistent positions before and after manipulation.
# Geometric mean of F1-F4 is used as the verification metric for the proportional
# formant scaling manipulation (consistent with Hilton et al. 2022 analysis).
# Results stored in globals: meas_f0mean, meas_f0sd, meas_ffreq
# =============================================================================
procedure measureAcoustics: .snd
    selectObject: .snd
    To Pitch (ac): 0.0, pitch_floor_hz, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitch_ceiling_hz
    .pitch = selected("Pitch")
    meas_f0mean = Get mean: 0, 0, "Hertz"
    meas_f0sd   = Get standard deviation: 0, 0, "Hertz"
    Remove

    selectObject: .snd
    To Formant (burg): 0.0, number_of_formants, max_formant_synth_hz, 0.025, 50
    .formant = selected("Formant")
    .f1 = Get mean: 1, 0, 0, "Hertz"
    .f2 = Get mean: 2, 0, 0, "Hertz"
    .f3 = Get mean: 3, 0, 0, "Hertz"
    .f4 = Get mean: 4, 0, 0, "Hertz"
    # Geometric mean of F1-F4: VTL proxy consistent with calibration source
    meas_ffreq = (.f1 * .f2 * .f3 * .f4) ^ 0.25
    Remove
endproc

# =============================================================================
# Procedure: pad/truncate string to exactly .n characters (left-aligned)
# =============================================================================
procedure pad: .s$, .n
    .s$ = .s$ + "                                                      "
    .s$ = left$(.s$, .n)
endproc

# =============================================================================
# Procedure: write line to Info window and report file
# =============================================================================
procedure logLine: .txt$
    appendInfoLine: .txt$
    appendFile: report_path$, .txt$ + newline$
endproc

# =============================================================================
# 1. Load sound
# =============================================================================
Read from file: input_file$
sound = selected("Sound")
sound_name$ = selected$("Sound")

report_path$ = output_dir$ + sound_name$ +
    ... "_mean+-" + string$(sd_f0mean_hz) + "Hz" +
    ... "_sd+-"   + string$(sd_f0sd_hz)   + "Hz" +
    ... "_formant+-" + fixed$(factor_formant * 100, 1) + "pct.txt"
writeFile: report_path$, ""

# =============================================================================
# 2. Measure baseline
# =============================================================================
@measureAcoustics: sound
base_f0mean  = meas_f0mean
base_f0sd    = meas_f0sd
base_ffreq   = meas_ffreq

if base_f0mean = undefined or base_f0mean <= 0
    exitScript: "ERROR: Could not measure f0. Check pitch floor/ceiling settings."
endif

# =============================================================================
# 3. Header
# =============================================================================
@logLine: "============================================="
@logLine: " IDS Acoustic Manipulation"
@logLine: "============================================="
@logLine: "File:   " + sound_name$
@logLine: "Factors:  f0 mean ±" + string$(sd_f0mean_hz) + " Hz   f0 SD ±" + string$(sd_f0sd_hz) + " Hz   formant ±" + fixed$(factor_formant * 100, 1) + "%"
@logLine: ""
@logLine: "--- Baseline measurements ---"
@logLine: "  f0 mean  : " + fixed$(base_f0mean, 2) + " Hz"
@logLine: "  f0 SD    : " + fixed$(base_f0sd,   2) + " Hz"
@logLine: "  Ffreq    : " + fixed$(base_ffreq,  2) + " Hz  (geom. mean F1-F4)"
@logLine: ""
@logLine: "--- Manipulation targets ---"
@logLine: "  f0 mean  Low : " + fixed$(base_f0mean - sd_f0mean_hz, 2) + " Hz"
@logLine: "  f0 mean  High: " + fixed$(base_f0mean + sd_f0mean_hz, 2) + " Hz"
@logLine: "  f0 SD    Low : " + fixed$(base_f0sd - sd_f0sd_hz, 2) + " Hz"
@logLine: "  f0 SD    High: " + fixed$(base_f0sd + sd_f0sd_hz, 2) + " Hz"
@logLine: "  Ffreq    Low : target " + fixed$(base_ffreq * (1 - factor_formant), 2) + " Hz  (ratio " + fixed$(1 - factor_formant, 4) + " initial; script iterates to converge)"
@logLine: "  Ffreq    High: target " + fixed$(base_ffreq * (1 + factor_formant), 2) + " Hz  (ratio " + fixed$(1 + factor_formant, 4) + " initial; script iterates to converge)"
@logLine: ""
@logLine: "--- Iterative correction settings ---"
@logLine: "  f0 SD tolerance  : " + fixed$(sd_tolerance_hz, 2) + " Hz  (max " + string$(max_iter) + " iter)"
@logLine: "  Ffreq tolerance  : " + fixed$(ffreq_tolerance_hz, 2) + " Hz  (max " + string$(max_ffreq_iter) + " iter)"
@logLine: ""
@logLine: "--- Creating 8 manipulations ---"

# =============================================================================
# 4. Create 8 combinations
#    Formant frequencies first (LPC on original, once per level) → f0 second (iterative)
# =============================================================================
n_files = 0

for i_ffreq from 1 to 2
    if i_ffreq = 1
        ffreq_label$ = "Low"
        formant_ratio = 1 - factor_formant
    else
        ffreq_label$ = "High"
        formant_ratio = 1 + factor_formant
    endif

    # Step 1: Iterative LPC formant shift — done once per formant level.
    # factor_formant is the target proportional shift in the OUTPUT geometric mean F1-F4.
    # The synthesis ratio is adjusted each iteration until the measured Ffreq matches.
    target_ffreq = base_ffreq * formant_ratio
    current_ratio = formant_ratio
    ffreq_iter = 0
    ffreq_done = 0

    while ffreq_done = 0
        ffreq_iter = ffreq_iter + 1
        @shiftFormants: sound, current_ratio
        tmp_snd = lpc_ffreq_result

        # Measure geometric mean F1-F4 of synthesis output
        selectObject: tmp_snd
        To Formant (burg): 0.0, number_of_formants, max_formant_synth_hz, 0.025, 50
        tmp_fmnt = selected("Formant")
        tmp_f1 = Get mean: 1, 0, 0, "Hertz"
        tmp_f2 = Get mean: 2, 0, 0, "Hertz"
        tmp_f3 = Get mean: 3, 0, 0, "Hertz"
        tmp_f4 = Get mean: 4, 0, 0, "Hertz"
        tmp_ffreq = (tmp_f1 * tmp_f2 * tmp_f3 * tmp_f4) ^ 0.25
        selectObject: tmp_fmnt
        Remove

        if abs(tmp_ffreq - target_ffreq) <= ffreq_tolerance_hz or ffreq_iter >= max_ffreq_iter
            ffreq_done = 1
            ffreq_sound = tmp_snd
        else
            selectObject: tmp_snd
            Remove
            # Adjust ratio: scale the DEVIATION from 1 by (target_deviation / measured_deviation).
            # Mirrors the slope correction in synthesizeF0: new_slope = old_slope * (tgt/meas).
            # Deviation from 1 is used because the neutral ratio (no shift) is 1, not 0.
            ffreq_meas_dev = tmp_ffreq - base_ffreq
            ffreq_tgt_dev  = target_ffreq - base_ffreq
            if abs(ffreq_meas_dev) < 1
                if ffreq_tgt_dev >= 0
                    ffreq_meas_dev = 1
                else
                    ffreq_meas_dev = -1
                endif
            endif
            current_ratio = 1 + (current_ratio - 1) * (ffreq_tgt_dev / ffreq_meas_dev)
            # Safety clamp
            if current_ratio < 0.70
                current_ratio = 0.70
            endif
            if current_ratio > 1.30
                current_ratio = 1.30
            endif
        endif
    endwhile

    achieved_ffreq_'ffreq_label$'$ = fixed$(tmp_ffreq, 2)
    used_ratio_'ffreq_label$'$ = fixed$(current_ratio, 4)

    @logLine: "  Ffreq-" + ffreq_label$ + ": target=" + fixed$(target_ffreq, 2) +
             ... " Hz  achieved=" + achieved_ffreq_'ffreq_label$'$ +
             ... " Hz  ratio=" + used_ratio_'ffreq_label$'$ +
             ... "  (" + string$(ffreq_iter) + " iter)"

    # Measure f0 statistics of the converged formant-shifted sound
    selectObject: ffreq_sound
    To Pitch (ac): 0.0, pitch_floor_hz, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitch_ceiling_hz
    .pitch_ffreq = selected("Pitch")
    ffreq_f0mean = Get mean: 0, 0, "Hertz"
    ffreq_f0sd   = Get standard deviation: 0, 0, "Hertz"
    selectObject: .pitch_ffreq
    Remove

    for i_sd from 1 to 2
        if i_sd = 1
            sd_label$ = "Low"
            target_sd = base_f0sd - sd_f0sd_hz
        else
            sd_label$ = "High"
            target_sd = base_f0sd + sd_f0sd_hz
        endif

        for i_mean from 1 to 2
            if i_mean = 1
                mean_label$ = "Low"
                target_mean = base_f0mean - sd_f0mean_hz
            else
                mean_label$ = "High"
                target_mean = base_f0mean + sd_f0mean_hz
            endif

            # Step 2: iterative f0 synthesis
            @synthesizeF0: ffreq_sound, ffreq_f0mean, ffreq_f0sd, target_mean, target_sd
            result_sound = synth_result

            # Log convergence info
            @logLine: "  [" + string$(i_sd) + string$(i_mean) + string$(i_ffreq) + "] " +
                     ... sound_name$ + "_f0mean-" + mean_label$ + "_f0SD-" + sd_label$ + "_Ffreq-" + ffreq_label$ +
                     ... "  (iters: " + string$(synth_iter) +
                     ... ", SD: " + fixed$(synth_sd, 2) + " Hz" +
                     ... ", mean: " + fixed$(synth_mean, 2) + " Hz)"

            # Name and save
            n_files = n_files + 1
            out_name$[n_files] = sound_name$ + "_f0mean-" + mean_label$ + "_f0SD-" + sd_label$ + "_Ffreq-" + ffreq_label$
            selectObject: result_sound
            Rename: out_name$[n_files]
            Save as WAV file: output_dir$ + out_name$[n_files] + ".wav"

            selectObject: result_sound
            Remove

        endfor
    endfor

    selectObject: ffreq_sound
    Remove

endfor

@logLine: ""
@logLine: "Done. 8 files saved to:"
@logLine: "  " + output_dir$
@logLine: "============================================="

# =============================================================================
# 5. Measure outputs and build comparison table
# =============================================================================
@logLine: ""
@logLine: "--- Measured acoustic values (post-manipulation) ---"
@logLine: ""

sep$ = "+------------------------------------------------------+------------+------------+------------+"
hdr$ = "| File                                                 | f0 mean Hz | f0 SD   Hz | Ffreq   Hz |"

@logLine: sep$
@logLine: hdr$
@logLine: sep$

@pad: sound_name$ + " [ORIGINAL]", 52
name_col$ = pad.s$
@pad: fixed$(base_f0mean, 2), 10
f0m_col$ = pad.s$
@pad: fixed$(base_f0sd, 2), 10
f0s_col$ = pad.s$
@pad: fixed$(base_ffreq, 2), 10
ffreq_col$ = pad.s$
@logLine: "| " + name_col$ + " | " + f0m_col$ + " | " + f0s_col$ + " | " + ffreq_col$ + " |"
@logLine: sep$

for k from 1 to n_files
    Read from file: output_dir$ + out_name$[k] + ".wav"
    manip_snd = selected("Sound")
    @measureAcoustics: manip_snd
    selectObject: manip_snd
    Remove

    @pad: out_name$[k], 52
    name_col$ = pad.s$
    @pad: fixed$(meas_f0mean, 2), 10
    f0m_col$ = pad.s$
    @pad: fixed$(meas_f0sd, 2), 10
    f0s_col$ = pad.s$
    @pad: fixed$(meas_ffreq, 2), 10
    ffreq_col$ = pad.s$
    @logLine: "| " + name_col$ + " | " + f0m_col$ + " | " + f0s_col$ + " | " + ffreq_col$ + " |"
endfor

@logLine: sep$
@logLine: ""
@logLine: "Report saved to:"
@logLine: "  " + report_path$
