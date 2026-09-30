<!-- markdownlint-disable MD024 -->
# Praat Scripts

A collection of [Praat](https://www.fon.hum.uva.nl/praat/) scripts for acoustic analysis and speech manipulation, developed primarily for research on infant-directed speech (IDS).

**Author:**
Juan David Leongómez [![ORCID](https://img.shields.io/badge/ORCID-0000--0002--0092--6298-brightgreen?logo=orcid)](https://orcid.org/0000-0002-0092-6298)

---

## Scripts

| Script | Description |
| --- | --- |
| [`syllable-nuclei-with-review.praat`](#syllable-nuclei-with-reviewpraat) | Detect syllable nuclei; compute speech and articulation rates with a manual review step |
| [`extract_f0_formants.praat`](#extract_f0_formantspraat) | General-purpose batch extraction of duration, $f_0$, formants, and formant dispersion from a folder of `.wav` files |
| [`extract_formants_IDS.praat`](#extract_formants_idspraat) | Extract $f_0$ and formant summary statistics from a folder of IDS `.wav` files |
| [`IDS_manipulation.praat`](#ids_manipulationpraat) | Generate 8 factorial acoustic manipulations ($f_0$ mean × $f_0$ SD × formants) from a single recording |

---

## `syllable-nuclei-with-review.praat`

Detects syllable nuclei in a WAV file and calculates two speech rate metrics:

- **Speech rate**: syllables / total duration
- **Articulation rate**: syllables / phonation time (pauses excluded)

After automatic detection, the script opens the Praat editor so the user can manually review and correct both the syllable tier and the utterance/silence segmentation before results are written to a CSV file.

### Features

- **Sonority envelope**: intensity is computed on a bandpass-filtered copy   of the audio (default 100–6000 Hz, adjustable in the form), reducing   false positives from low-frequency noise and fricative energy.
- **Pitch-based utterance validation (VAD)**: each interval classified as   `utterance` is validated against the Pitch object; intervals without   sufficient vocal-fold vibration are reclassified as `silent`.
- Interactive WAV file selection via the system file chooser.
- Results are appended to a cumulative CSV in the same folder as the audio,   so all recordings in a folder accumulate in a single output file.
- Compatible with Linux, Mac, and Windows.

### Adapted from

- De Jong, N. & Wempe, T. (2009). Praat script to detect syllable nuclei and measure speech rate automatically. *Behavior Research Methods*, 41(2), 385–390. <https://doi.org/10.3758/BRM.41.2.385>
- Quené, H., Persoon, I. & De Jong, N. (2010). Modified version of the original script [version 2010.09.17]. <https://github.com/FieldDB/Praat-Scripts/blob/main/praat-script-syllable-nuclei-v2dir.praat>

---

## `extract_f0_formants.praat`

General-purpose version of the batch extraction, not tied to any particular corpus. For every `.wav` file in a folder, it writes one row to a CSV with the following columns:

| Column | Description |
| --- | --- |
| `filename` | File name without the `.wav` extension |
| `duration_s` | Total duration (s) |
| `f0_mean_hz` / `f0_sd_hz` | $f_0$ mean and SD (Hz) |
| `f1_mean_hz` – `f4_mean_hz` | Mean frequency of F1–F4 (Hz) |
| `formant_mean_hz` | Arithmetic mean of F1–F4 (Hz) |
| `df_hz` | Formant dispersion, $D_f = (F_4 - F_1) / 3$ (Fitch, 1997) (Hz) |

### Parameters

| Parameter | Description | Default |
| --- | --- | --- |
| `directory` | Folder containing the `.wav` files (trailing `/` optional) | — |
| `output_file` | Full path of the output CSV | — |
| `pitch_floor` / `pitch_ceiling` | $f_0$ analysis range | 75 / 500 Hz |
| `maximum_formant` | Formant analysis ceiling | 5500 Hz |

### Notes

- Recommended ranges: $f_0$ 75–300 Hz and `maximum_formant = 5000` for male speakers; $f_0$ 100–600 Hz and `maximum_formant = 5500` for female speakers and children.
- Undefined values (e.g., unvoiced or silent files) are written as `NA`, so the CSV can be read directly into R. `formant_mean_hz` is `NA` unless all four formants are defined, and `df_hz` is `NA` unless F1 and F4 are defined.
- Formant analysis uses the Burg method (5 formants, 25 ms window, pre-emphasis from 50 Hz), matching the settings of Hilton et al. (2022).

### Sources

- Formant analysis settings: Hilton, C. B., Moser, C. J., et al. (2022). Acoustic regularities in infant-directed speech and song across cultures. *Science*, 378(6617). <https://doi.org/10.1126/science.abm1720>
- Formant dispersion: Fitch, W. T. (1997). Vocal tract length and formant frequency dispersion correlate with body size in rhesus macaques. *The Journal of the Acoustical Society of America*, 102(2), 1213–1222. <https://doi.org/10.1121/1.421048>

---

## `extract_formants_IDS.praat`

Extracts $f_0$ (mean and SD) and formant frequencies (F1–F4) summary statistics from a folder of IDS speech `.wav` files, and writes one row per file to a CSV.

### Parameters

| Parameter | Description | Default |
| --- | --- | --- |
| `directory` | Folder containing the `.wav` files | — |
| `resultsfile` | Full path of the output CSV | — |
| `minimum_pitch` / `maximum_pitch` | $f_0$ analysis range | 100 / 600 Hz (female) |
| `maximum_formant` | Formant analysis ceiling | 5500 Hz (female/children) |

### Notes

- Default settings are tuned for female speakers. For male speakers, use `minimum_pitch = 75`, `maximum_pitch = 300`, and `maximum_formant = 5000`.
- Undefined values (unvoiced or silent segments) are replaced with `0`.
- Formant analysis uses the Burg method (5 formants, 25 ms window, pre-emphasis from 50 Hz), matching the settings of Hilton et al. (2022).

### Adapted from

- Adapted from [`analysis/acoustics_processing/3_masterscript.praat`](https://github.com/themusiclab/infant-speech-song/blob/main/analysis/acoustics_processing/3_masterscript.praat) in  Hilton, C. B., Moser, C. J., et al. (2022). Acoustic regularities in   infant-directed speech and song across cultures. *Science*, 378(6617).   <https://doi.org/10.1126/science.abm1720>
- Original script repository: <https://github.com/themusiclab/infant-speech-song>

---

## `IDS_manipulation.praat`

Generates all 8 combinations of a 2 ($f_0$ mean: High/Low) × 2 ($f_0$ SD: High/Low) × 2 (formant frequencies: High/Low) factorial design from a single IDS recording. Each manipulated file is saved as a `.wav`, and a verification report with pre- and post-manipulation acoustic values is saved as a `.txt` file.

Manipulation magnitudes are set to 1 × the between-speaker SD of IDS acoustics in female speakers reported by Hilton et al. (2022, *Nature Human Behaviour*; *n* = 21 societies):

| Parameter | Offset | Default |
| --- | --- | --- |
| $f_0$ mean | ± *n* Hz | ±51 Hz (50.8 Hz) |
| $f_0$ SD | ± *n* Hz | ±28 Hz (28.4 Hz) |
| Formants (F1–F4) | ± proportion | ±4.6% (CV = 0.046) |

### Manipulation procedure

1. **Formant shift (Step 1):** LPC-based resynthesis applied to the original audio. All formant frequencies are scaled proportionally by a ratio that is adjusted iteratively until the geometric mean of F1–F4 in the output matches the target within `ffreq_tolerance_hz`. No PSOLA is used in this step; pitch is left untouched.

2. **$f_0$ manipulation (Step 2):** Iterative affine correction via PSOLA. A linear transform (slope and intercept) is computed to shift $f_0$ mean and SD to their targets. After each resynthesis, the output SD is measured; if it deviates from the target by more than `sd_tolerance_hz`, the slope is corrected by `target_sd / measured_sd` and the process repeats. Typically converges in 2–3 iterations (maximum `max_iter`).

### Parameters

| Parameter | Description | Default |
| --- | --- | --- |
| `Input_file` | Full path to the input `.wav` file | — |
| `Output_dir` | Output folder (trailing `/` required) | — |
| `sd_f0mean_hz` | $f_0$ mean offset in Hz | 51 |
| `sd_f0sd_hz` | $f_0$ SD offset in Hz | 28 |
| `factor_formant` | Formant scaling factor | 0.046 |
| `pitch_floor_hz` / `pitch_ceiling_hz` | $f_0$ analysis range | 100 / 500 Hz |
| `sd_tolerance_hz` | Convergence tolerance for $f_0$ SD | 0.5 Hz |
| `max_iter` | Maximum iterations for $f_0$ | 5 |
| `ffreq_tolerance_hz` | Convergence tolerance for formants | 10 Hz |
| `max_ffreq_iter` | Maximum iterations for formants | 12 |
| `max_formant_synth_hz` | Formant ceiling for synthesis and measurement | 5500 Hz |

### Output files

- 8 `.wav` files named
  `{name}_f0mean-{High/Low}_f0SD-{High/Low}_Ffreq-{High/Low}.wav`
- 1 `.txt` report named
  `{name}_mean±{n}Hz_sd±{n}Hz_formant±{n}pct.txt`

### Sources

- Manipulation magnitudes: Hilton, C. B., et al. (2022). Acoustic regularities in infant-directed speech and song across cultures. *Nature Human Behaviour*, 6, 1545–1556. <https://doi.org/10.1038/s41562-022-01410-x>
- Formant manipulation adapted from `changeformants.praat`, [Praat Vocal Toolkit](http://www.praatvocaltoolkit.com/)

---

## Licenses

Each script carries its own license header because they derive from different upstream sources:

| Script | License | Upstream |
| --- | --- | --- |
| `syllable-nuclei-with-review.praat` | [GPL-3.0-or-later](https://www.gnu.org/licenses/gpl-3.0.html) | de Jong & Wempe (2008); Quené et al. (2010) via [FieldDB/Praat-Scripts](https://github.com/FieldDB/Praat-Scripts) |
| `extract_f0_formants.praat` | [GPL-3.0-or-later](https://www.gnu.org/licenses/gpl-3.0.html) | Original code; analysis settings follow Hilton, Moser et al. (2022) |
| `extract_formants_IDS.praat` | [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) | Hilton, Moser et al. (2022) via [themusiclab/infant-speech-song](https://github.com/themusiclab/infant-speech-song) |
| `IDS_manipulation.praat` | [GPL-2.0-or-later](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html) | Original code; formant shift procedure adapted from [Praat Vocal Toolkit](http://www.praatvocaltoolkit.com/) `changeformants.praat` (verify license) |

> **Note:** `extract_formants_IDS.praat` is released under CC BY-NC-SA 4.0, which restricts **commercial use**. The other scripts are GPL and permit commercial use. These licenses are not mutually compatible, so a single repo-wide license is not applied.
