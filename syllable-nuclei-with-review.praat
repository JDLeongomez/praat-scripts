###########################################################################
#                                                                         #
#  Praat Script Syllable Nuclei -- modified for manual review             #
#                                                                         #
#  Original:  Copyright (C) 2008  Nivja de Jong & Ton Wempe               #
#  Modified:  2010.09.17  Hugo Quené, Ingrid Persoon, & Nivja de Jong     #
#  Modified:  2026        Juan David Leongómez                            #
#             - interactive file chooser; CSV output (appended per run)   #
#             - manual review step: editor opens before calculating rates #
#             - sonority envelope: intensity on bandpass-filtered audio   #
#             - pitch-based utterance validation (VAD)                    #
#                                                                         #
#  NB: speech rate       = syllables / total duration                     #
#      articulation rate = syllables / phonation time (pauses excluded)   #
#                                                                         #
###########################################################################
#
#  License: GNU General Public License v3.0 or later (GPL-3.0-or-later)
#  This script is a derivative of GPL-3.0-licensed code originally by
#  de Jong & Wempe (2008) and modified by Quené, Persoon & de Jong (2010).
#  <https://www.gnu.org/licenses/gpl-3.0.html>
#
# WORKFLOW:
#   1. Fill in the parameters and select a WAV file.
#   2. The script detects syllable nuclei and utterance boundaries,
#      then opens the Sound + TextGrid in the editor for manual review.
#   3. Correct the "syllables" tier (tier 1) as needed; edit the
#      utterance/silent tier (tier 2) if any pauses were missed or
#      incorrectly detected.
#   4. Click Continue -- the script re-counts from the corrected tiers
#      and appends one row of results to the CSV.
#
# IMPROVEMENTS OVER PREVIOUS VERSIONS:
#   Syllables: intensity is computed on a bandpass-filtered copy of the
#     audio (default 100-6000 Hz, adjustable in the form). This suppresses
#     low-frequency room noise and microphone rumble without cutting into
#     vowel formant energy, producing a cleaner sonority envelope for
#     nucleus detection. Raising the low cutoff reduces over-detection;
#     lowering it reduces under-detection.
#
#   Silences: after intensity-based segmentation, each "utterance" interval
#     is validated against the Pitch object. Intervals where fewer than
#     min_voiced_fraction of sampled time points have a defined f0 are
#     reclassified as "silent", removing noise bursts or breaths that pass
#     the intensity threshold but contain no vocal-fold vibration.
#
# USAGE NOTES:
#   - Tier 1 = "syllables" (points). Add or remove points here.
#   - Tier 2 = utterance/silent intervals. Edit if the automatic
#     segmentation missed or incorrectly detected pauses. To add a
#     silent interval: place boundaries at each edge of the silence
#     (Boundary > Add on selected tier), then label the new interval
#     "silent" (exactly; not "silence" or "pause"). Flanking speech
#     intervals must be labelled "utterance".
#   - Results are APPENDED to the CSV on each run, so all recordings
#     in a folder accumulate in a single output file.
###########################################################################


form Counting Syllables in Sound Utterances
   real    Silence_threshold_(dB)             -25
   real    Minimum_dip_between_peaks_(dB)       2
   real    Minimum_pause_duration_(s)          0.3
   real    Minimum_sounding_duration_(s)       0.1
   real    Minimum_voiced_fraction             0.2
   real    Filter_low_cutoff_(Hz)            100
   real    Filter_high_cutoff_(Hz)           6000
   boolean Keep_Soundfiles_and_Textgrids       yes
   sentence Output_CSV_filename  syllable-nuclei-output.csv
endform

# --- shorten variables ---
silencedb       = silence_threshold
mindip          = minimum_dip_between_peaks
showtext        = keep_Soundfiles_and_Textgrids
minpause        = minimum_pause_duration
minsounding     = minimum_sounding_duration
minvoiced       = minimum_voiced_fraction
filtLow         = filter_low_cutoff
filtHigh        = filter_high_cutoff


# -----------------------------------------------------------------------
# 1. SELECT WAV FILE AND DERIVE PATHS
# -----------------------------------------------------------------------
filePath$ = chooseReadFile$("Select a WAV file")
if filePath$ = ""
    exit No file selected. Script cancelled.
endif

directory$ = left$(filePath$, rindex(filePath$, "/"))
directory$ = left$(directory$, length(directory$) - 1)
fileName$  = mid$(filePath$, rindex(filePath$, "/") + 1, length(filePath$))
outputCSV$ = directory$ + "/" + output_CSV_filename$


# -----------------------------------------------------------------------
# 2. LOAD SOUND
# -----------------------------------------------------------------------
Read from file... 'filePath$'
soundname$ = selected$("Sound")
soundid    = selected("Sound")
originaldur = Get total duration


# -----------------------------------------------------------------------
# 3. PITCH
#    Computed early so it can be used for both:
#      (a) utterance validation (VAD) in step 5, and
#      (b) voiced-peak filtering in step 7.
#
#    Parameters: time step 0.01 s, F0 range 75-600 Hz (covers male and
#    female adult voices), 15 candidates (robust to noise).
#    Adjust F0 range if working with children or atypical voices.
# -----------------------------------------------------------------------
select soundid
To Pitch (ac)... 0.01 75 15 no 0.03 0.45 0.01 0.35 0.14 600
pitchid = selected("Pitch")


# -----------------------------------------------------------------------
# 4. SONORITY ENVELOPE (bandpass-filtered intensity)
#    The audio is bandpass-filtered before computing intensity, producing
#    a sonority envelope that is more robust for syllable-nucleus detection.
#
#    Default: 100-6000 Hz.
#      - Low cutoff (100 Hz): removes microphone rumble and room noise
#        without cutting into vowel energy (F1 of /u/, /o/ can be ~300 Hz,
#        so a lower cutoff is safer than the naive 300 Hz).
#      - High cutoff (6000 Hz): retains all formant energy while reducing
#        high-frequency noise above the speech range.
#
#    If the script misses syllables: lower the low cutoff or raise the high.
#    If the script over-detects:    raise the low cutoff or lower the high.
#    Both values are adjustable in the form.
# -----------------------------------------------------------------------
select soundid
Filter (pass Hann band)... filtLow filtHigh 100
filteredid = selected("Sound")

To Intensity... 50 0 yes
intid   = selected("Intensity")
start   = Get time from frame number... 1
nframes = Get number of frames
end     = Get time from frame number... 'nframes'

minint   = Get minimum... 0 0 Parabolic
maxint   = Get maximum... 0 0 Parabolic
max99int = Get quantile... 0 0 0.99

threshold  = max99int + silencedb
threshold2 = maxint - max99int
threshold3 = silencedb - threshold2
if threshold < minint
    threshold = minint
endif


# -----------------------------------------------------------------------
# 5. UTTERANCE/SILENCE SEGMENTATION WITH PITCH VALIDATION
#
#    Step A - intensity-based segmentation (standard method):
#      Intervals below the silence threshold become "silent";
#      intervals above become "utterance".
#
#    Step B - pitch-based validation (VAD):
#      For each "utterance" interval, sample f0 at n_samples evenly-
#      spaced time points. If fewer than minvoiced of those points have
#      a defined f0, the interval is reclassified as "silent".
#      This removes noise bursts and breath sounds that pass the
#      intensity threshold but contain no vocal-fold vibration.
# -----------------------------------------------------------------------

# --- Step A: intensity-based ---
select intid
To TextGrid (silences)... threshold3 minpause minsounding silent utterance
textgridid = selected("TextGrid")

# --- Step B: pitch validation ---
n_samples = 9
select textgridid
nint_check = Get number of intervals... 1
for icheck from 1 to nint_check
    select textgridid
    label$ = Get label of interval... 1 icheck
    if label$ = "utterance"
        t1 = Get start time of interval... 1 icheck
        t2 = Get end time of interval... 1 icheck
        voiced_n = 0
        for k from 1 to n_samples
            t_q = t1 + (t2 - t1) * k / (n_samples + 1)
            select pitchid
            pv = Get value at time... t_q Hertz Linear
            if pv <> undefined
                voiced_n += 1
            endif
        endfor
        if voiced_n / n_samples < minvoiced
            select textgridid
            Set interval text... 1 icheck silent
        endif
    endif
endfor


# -----------------------------------------------------------------------
# 6. INITIAL SPEAKING TIME
#    (recalculated from the edited TextGrid in step 10)
# -----------------------------------------------------------------------
select textgridid
silencetierid  = Extract tier... 1
silencetableid = Down to TableOfReal... utterance
nutterance     = Get number of rows
npauses        = nutterance
speakingtot    = 0
for ipause from 1 to npauses
    beginsound  = Get value... 'ipause' 1
    endsound    = Get value... 'ipause' 2
    speakingdur = endsound - beginsound
    speakingtot = speakingdur + speakingtot
endfor


# -----------------------------------------------------------------------
# 7. PEAK DETECTION ON SONORITY ENVELOPE
# -----------------------------------------------------------------------
select intid
Down to Matrix
matid    = selected("Matrix")
To Sound (slice)... 1
sndintid = selected("Sound")

intdur = Get total duration
intmax = Get maximum... 0 0 Parabolic

To PointProcess (extrema)... Left yes no Sinc70
ppid     = selected("PointProcess")
numpeaks = Get number of points

for i from 1 to numpeaks
    t'i' = Get time from index... 'i'
endfor

select sndintid
peakcount = 0
for i from 1 to numpeaks
    value = Get value at time... t'i' Cubic
    if value > threshold
        peakcount += 1
        int'peakcount'       = value
        timepeaks'peakcount' = t'i'
    endif
endfor

select intid
validpeakcount = 0
currenttime = timepeaks1
currentint  = int1

for p to peakcount - 1
    following     = p + 1
    followingtime = timepeaks'following'
    dip           = Get minimum... 'currenttime' 'followingtime' None
    diffint       = abs(currentint - dip)
    if diffint > mindip
        validpeakcount += 1
        validtime'validpeakcount' = timepeaks'p'
    endif
    currenttime = timepeaks'following'
    currentint  = Get value at time... timepeaks'following' Cubic
endfor


# -----------------------------------------------------------------------
# 8. VOICED PEAKS ONLY
#    At this point tier 1 is still the utterance/silent tier.
#    A peak is kept only if:
#      (a) it falls inside an "utterance" interval, and
#      (b) the Pitch object has a defined f0 at that time.
# -----------------------------------------------------------------------
voicedcount = 0
for i from 1 to validpeakcount
    querytime = validtime'i'

    select textgridid
    whichinterval = Get interval at time... 1 'querytime'
    whichlabel$   = Get label of interval... 1 'whichinterval'

    select pitchid
    value = Get value at time... 'querytime' Hertz Linear

    if value <> undefined
        if whichlabel$ = "utterance"
            voicedcount += 1
            voicedpeak'voicedcount' = validtime'i'
        endif
    endif
endfor


# -----------------------------------------------------------------------
# 9. INSERT SYLLABLE POINTS INTO TEXTGRID AS TIER 1
#    After this step: tier 1 = syllables (points),
#                     tier 2 = utterance/silent (intervals).
# -----------------------------------------------------------------------
timecorrection = originaldur / intdur

select textgridid
Insert point tier... 1 syllables

for i from 1 to voicedcount
    position = voicedpeak'i' * timecorrection
    Insert point... 1 position ""
endfor

# -----------------------------------------------------------------------
# 10. CLEAN UP INTERMEDIATE OBJECTS (before opening editor)
# -----------------------------------------------------------------------
select filteredid
plus intid
plus matid
plus sndintid
plus ppid
plus pitchid
plus silencetierid
plus silencetableid
Remove


# -----------------------------------------------------------------------
# 11. OPEN EDITOR FOR MANUAL REVIEW
#     Tier 1 = "syllables" (points).  Tier 2 = utterance/silent intervals.
#
#     Correcting syllables (tier 1):
#       - Remove a point: click it, then Tier > Remove point(s)
#       - Add a point:    click at the desired time, then Tier > Add point
#
#     Correcting silences (tier 2) - only if needed:
#       - Add a silent interval: place boundaries at each edge of the
#         silence (Tier > Add interval boundary), then label the new
#         interval "silent" (exactly; not "silence" or "pause").
#         The surrounding intervals of speech must be labelled "utterance".
# -----------------------------------------------------------------------
select soundid
plus textgridid
View & Edit

beginPause: "Review syllables"
    comment: "Check the 'syllables' tier (tier 1) in the editor window."
    comment: "Add or remove points to correct the automatic detection."
    comment: "When you are done, click Continue to calculate the rates."
endPause: "Continue", 1


# -----------------------------------------------------------------------
# 12. RE-COUNT FROM (POSSIBLY EDITED) TEXTGRID
#     Tier 1 syllable points and tier 2 silence intervals are both
#     re-read here so that any manual edits are reflected in the output.
# -----------------------------------------------------------------------
select textgridid
voicedcount = Get number of points... 1

nintervals  = Get number of intervals... 2
speakingtot = 0
npauses     = 0
for iint from 1 to nintervals
    label$ = Get label of interval... 2 iint
    if label$ = "utterance"
        t1 = Get start time of interval... 2 iint
        t2 = Get end time of interval... 2 iint
        speakingtot = speakingtot + (t2 - t1)
        npauses += 1
    endif
endfor


# -----------------------------------------------------------------------
# 13. SAVE TEXTGRID
# -----------------------------------------------------------------------
select textgridid
Save as text file... 'directory$'/'fileName$'.TextGrid


# -----------------------------------------------------------------------
# 14. OPTIONALLY REMOVE OBJECTS FROM OBJECT WINDOW
# -----------------------------------------------------------------------
if showtext < 1
    select soundid
    plus textgridid
    Remove
endif


# -----------------------------------------------------------------------
# 15. CALCULATE RATES
# -----------------------------------------------------------------------
npause           = npauses - 1
speakingrate     = voicedcount / originaldur
articulationrate = voicedcount / speakingtot
asd              = speakingtot / voicedcount


# -----------------------------------------------------------------------
# 16. WRITE RESULTS TO CSV (append; write header if file does not exist)
# -----------------------------------------------------------------------
outputCSVexists = fileReadable(outputCSV$)

if outputCSVexists = 0
    fileappend 'outputCSV$' fileName,syllableCount,pauseCount,totalDuration_s,phonationTime_s,speechRate_syll_s,articulationRate_syll_s,avgSyllDuration_s'newline$'
endif

fileappend 'outputCSV$' 'soundname$','voicedcount','npause','originaldur:3','speakingtot:3','speakingrate:3','articulationrate:3','asd:4''newline$'


# -----------------------------------------------------------------------
# 17. SUMMARY IN INFO WINDOW
# -----------------------------------------------------------------------
clearinfo
printline === Syllable Rate Results ===
printline File:              'soundname$'
printline Syllables:         'voicedcount'
printline Pauses:            'npause'
printline Total duration:    'originaldur:3' s
printline Phonation time:    'speakingtot:3' s
printline Speech rate:       'speakingrate:3' syll/s
printline Articulation rate: 'articulationrate:3' syll/s
printline Avg syll duration: 'asd:4' s
printline ===========================
printline Results appended to: 'outputCSV$'
