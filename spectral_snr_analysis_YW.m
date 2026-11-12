%% Spectral SNR analysis for target-masker pairs
%
% Checks whether the target-masker SNR (in dB) is constant across frequency,
% or whether specific bands show a different target/masker energy balance
% across masker conditions (a potential spectral confound).
%
% Logic: broadband SNR is computed as
%   SNR_dB = 20*log10(rms(target) / rms(masker))
% Here this is repeated after narrowly bandpass-filtering BOTH target and
% masker at the same set of center frequencies. If the per-band SNR stays
% close to the broadband SNR at every band, and this pattern is the same
% across masker conditions, there is no spectral confound.
%
% DESIGN: each masker file is a single audio track per condition (5
% conditions total), independently crossed with every target story (5
% stories total) -- a fully-crossed 5x5 design, not a 1:1 pairing. The
% loop below computes SNR for every masker x target combination.

clear; clc; close all;

%% --- USER SETTINGS ---
% Define conditions and their masker files here (ONE masker file per
% condition -- it gets crossed with every target story below). These
% should be the RAW, PRE-ADJUSTMENT files (before the Audacity gain knob
% was applied), since the gain is now derived automatically per masker x
% target combination rather than hand-entered.
conditions = struct( ...
    'name', {'rhythm_jittered','pitch_scrambled','combined','reverse','music'}, ...
    'masker_files', { ...
        {'/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/background noise/onset_GoodBait.wav'}, ...
        {'/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/background noise/pitch_GoodBait.wav'}, ...
        {'/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/background noise/pitch_onset_GoodBait.wav'}, ...
        {''}, ...   % 'reverse' is derived below by time-reversing the 'music' file directly -- see note
        {'/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/background noise/unscram_goodbait.wav'} ...
    });

% Background masker starts playing at trial t=0; the story doesn't start
% until this many seconds later. 
onset_offset_sec = 1.5;

% Target speech (story) files -- every one of these gets crossed with
% every masker condition above.
target_files = { ...
    '/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/stories/dam.wav', ...
    '/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/stories/donkey.wav', ...
    '/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/stories/grandfather.wav', ...
    '/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/stories/raiden.wav', ...
    '/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/stories/raven.wav' ...
    '/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/stories/whitehorse.wav'
};
target_gain_db = zeros(1, numel(target_files));

[~, target_names] = cellfun(@fileparts, target_files, 'UniformOutput', false);

% The known/verified final broadband SNR for every pair, used to derive
% each masker's gain algebraically: since I tuned the masker gain per
% file specifically to hit this value in Audacity, solving backward from it is more
% reliable than re-entering (or re-finding) each knob value by hand?

target_snr_db = -10;

% My masker files (44100 Hz) and target files (48000 Hz) are at
% different native sample rates. My actual
% presented/mixed stimuli was 44100 Hz.
presentation_fs = 44100; 

n_bands      = 10;    % as suggested: ~10 log-spaced centers, 50-5000 Hz
f_low_edge   = 50;    % Hz
f_high_edge  = 5000;  % Hz
center_freqs = logspace(log10(f_low_edge), log10(f_high_edge), n_bands);

% Claude HELP: 
% Bandwidth: set each band's width equal to the spacing between adjacent
% center frequencies (in octaves), so the n_bands filters tile the
% 50-5000 Hz range with no gaps and minimal overlap. This ties the
% bandwidth directly to n_bands/f_low_edge/f_high_edge rather than
% picking an arbitrary fixed value (e.g. a conventional 1/3-octave),
% and means no part of the spectrum goes unexamined.
%
% Alternative: if you want filter widths that reflect the ear's own
% frequency resolution, you could instead set bandwidth from the ERB scale,
% e.g. ERB(fc) = 24.7*(4.37*fc/1000 + 1) Hz, converted to octaves. That's
% a more perceptually grounded choice but adds complexity; the tiling
% approach below is the simpler, still-defensible default.


% YW comments: (Karl says AI is right, 
% it's just means how perceptually you can differentiate two sounds within the same/different frequency bands, 
% but it's not a big deal)


band_spacing_oct = log2(f_high_edge / f_low_edge) / (n_bands - 1);
bandwidth_oct    = band_spacing_oct;

filter_order = 4;    % Butterworth order (zero-phase via filtfilt)
offset_samples = round(onset_offset_sec * presentation_fs);

%% --- COMPUTE ---
results = struct();

for c = 1:numel(conditions)
    cond      = conditions(c);
    n_targets = numel(target_files);

    snr_broadband = nan(n_targets,1);
    snr_by_band   = nan(n_targets, n_bands);

    if strcmpi(cond.name, 'reverse')
        % Derive directly from the 'music' (unscrambled) file rather than
        % the full-song reverse_goodbait.wav -- bc I just reversed the OG
        % music using Audacity's reverse function... BUT see below
        % IMPORTANT: reversal must happen AFTER trimming to the length
        % needed for each story, not before -- trim length varies per
        % story, and trim-then-reverse != reverse-then-trim when the trim
        % length changes. So only the raw (un-reversed, untrimmed) clip is
        % loaded here; the actual trim+reverse happens inside the t loop.
        music_idx = find(strcmpi({conditions.name}, 'music'), 1);
        assert(~isempty(music_idx), 'No condition named "music" found to derive "reverse" from.');
        [masker_raw, fs_m] = audioread(conditions(music_idx).masker_files{1});
        masker_raw = mean(masker_raw, 2);
    else
        [masker_raw, fs_m] = audioread(cond.masker_files{1});  % one masker file per condition
        masker_raw = mean(masker_raw, 2);  % force mono if stereo
    end

    if fs_m ~= presentation_fs
        masker_raw = resample(masker_raw, presentation_fs, fs_m);
        fs_m = presentation_fs;
    end

    for t = 1:n_targets
        [target, fs_t] = audioread(target_files{t});
        target = mean(target, 2);  % force mono if stereo

        if fs_t ~= presentation_fs
            target = resample(target, presentation_fs, fs_t);
            fs_t = presentation_fs;
        end

        assert(fs_t == fs_m, ...
            'Sample rate mismatch after resampling: target "%s" vs masker for condition %s', target_names{t}, cond.name);
        fs = fs_t;

        % The story starts onset_offset_sec after the masker does, so the
        % masker window that actually overlaps with this target starts
        % offset_samples into the masker, not at sample 1.
        n = min(length(target), length(masker_raw) - offset_samples);
        target = target(1:n);

        if strcmpi(cond.name, 'reverse')
            % Trim the ORIGINAL clip to the length needed for this
            % specific story first, THEN reverse that trimmed segment --
            % this reconstructs exactly what would have been played for
            % this story's trial.
            needed_length     = offset_samples + n;
            pre_trim_segment  = masker_raw(1:needed_length);
            reversed_segment  = flipud(pre_trim_segment);
            masker = reversed_segment(offset_samples+1 : offset_samples+n);
        else
            masker = masker_raw(offset_samples+1 : offset_samples+n);
        end

        % Apply the target gain (I never touched target gain when mixing
% on Audacity as I only manipulated the gain of the background noise).
        target = target * 10^(target_gain_db(t) / 20);

        % Derive the masker gain that was used for THIS masker x target
        % pair: solve for the gain that makes the broadband SNR equal
        % target_snr_db, given the raw (pre-adjustment) target and masker.
        raw_ratio_db      = 20*log10(rms(target) / rms(masker));
        required_gain_db  = raw_ratio_db - target_snr_db;
        masker = masker * 10^(required_gain_db / 20);

        fprintf('  %s x %s: derived masker gain = %.2f dB\n', cond.name, target_names{t}, required_gain_db);

        % Broadband SNR -- should now equal target_snr_db by construction;
        % this is really a check that the derivation ran correctly, not an
        % independent confirmation (that was already established separately).
        snr_broadband(t) = 20*log10(rms(target) / rms(masker));

        % Per-band SNR
        for b = 1:n_bands
            fc = center_freqs(b);
            [t_filt, m_filt] = bandpass_pair(target, masker, fs, fc, bandwidth_oct, filter_order);
            snr_by_band(t, b) = 20*log10(rms(t_filt) / rms(m_filt));
        end
    end

    results.(cond.name).snr_broadband  = snr_broadband;
    results.(cond.name).snr_by_band    = snr_by_band;
    results.(cond.name).mean_broadband = mean(snr_broadband);
    results.(cond.name).mean_by_band   = mean(snr_by_band, 1);

    fprintf('%s: mean broadband SNR across all %d targets = %.2f dB\n\n', ...
        cond.name, n_targets, results.(cond.name).mean_broadband);
end

%% --- CROSS-CONDITION SPREAD SUMMARY ---
% At each frequency band, how far apart are the conditions from each
% other (max - min across conditions' mean_by_band)? A small spread at a
% band means no meaningful condition-specific difference there; 
% a large spread flags where to
% look closer (and which condition is the outlier).
cond_names   = {conditions.name};
all_mean_by_band = nan(numel(cond_names), n_bands);
for c = 1:numel(cond_names)
    all_mean_by_band(c,:) = results.(cond_names{c}).mean_by_band;
end

band_spread = max(all_mean_by_band, [], 1) - min(all_mean_by_band, [], 1);

fprintf('--- Cross-condition spread by frequency band ---\n');
for b = 1:n_bands
    [~, max_idx] = max(all_mean_by_band(:,b));
    [~, min_idx] = min(all_mean_by_band(:,b));
    fprintf('  %7.1f Hz: spread = %5.2f dB  (highest: %-16s %.2f dB | lowest: %-16s %.2f dB)\n', ...
        center_freqs(b), band_spread(b), ...
        cond_names{max_idx}, all_mean_by_band(max_idx,b), ...
        cond_names{min_idx}, all_mean_by_band(min_idx,b));
end
fprintf('  Largest spread: %.2f dB at %.1f Hz\n\n', max(band_spread), center_freqs(band_spread == max(band_spread)));

%% --- COMBINED vs. THE OTHER FOUR (targeted comparison) ---
% My behavioral result showed "combined" differing from the other four
% conditions specifically (not rhythm_jittered vs. pitch_scrambled, etc.).
% The generic max-min spread above answers "does ANY pair diverge
% anywhere" -- So I'm trying to find out if combined's spectrum diverge
% from the rest, band by band?
combined_idx = find(strcmpi(cond_names, 'combined'), 1);
other_idx    = setdiff(1:numel(cond_names), combined_idx);

combined_vs_rest = all_mean_by_band(combined_idx,:) - mean(all_mean_by_band(other_idx,:), 1);

fprintf('--- Combined vs. mean of other four conditions, by band ---\n');
for b = 1:n_bands
    fprintf('  %7.1f Hz: combined - mean(others) = %+6.2f dB\n', center_freqs(b), combined_vs_rest(b));
end
[max_dev, max_dev_idx] = max(abs(combined_vs_rest));
fprintf('  Largest deviation: %+.2f dB at %.1f Hz\n\n', ...
    combined_vs_rest(max_dev_idx), center_freqs(max_dev_idx));

%% --- EXPORT: long-format CSV for inferential stats in R ---
% One row per (story x condition x band), for a repeated-measures ANOVA
% or mixed model testing the Condition x Band interaction -- that
% interaction is the direct test of whether the SPECTRAL PROFILE of
% masking differs by condition (a genuine confound), as opposed to just
% an overall level difference.
export_rows = {};
for c = 1:numel(cond_names)
    cname = cond_names{c};
    snr_matrix = results.(cname).snr_by_band;  % n_targets x n_bands
    for t = 1:size(snr_matrix,1)
        for b = 1:n_bands
            export_rows(end+1,:) = {target_names{t}, cname, center_freqs(b), snr_matrix(t,b)}; %#ok<SAGROW>
        end
    end
end
export_table = cell2table(export_rows, 'VariableNames', {'story','condition','center_freq_hz','snr_db'});
writetable(export_table, 'spectral_snr_by_band_long.csv');
fprintf('Exported long-format data to spectral_snr_by_band_long.csv (%d rows)\n\n', height(export_table));

%% --- PLOT ---
figure; hold on;
colors = lines(numel(cond_names));

for c = 1:numel(cond_names)
    plot(center_freqs, results.(cond_names{c}).mean_by_band, '-o', ...
        'Color', colors(c,:), 'LineWidth', 1.5, ...
        'DisplayName', strrep(cond_names{c}, '_', ' '));
end

yline(-10, '--k', 'Broadband target (-10 dB)', 'LineWidth', 1, 'HandleVisibility', 'off');
set(gca, 'XScale', 'log');
xlabel('Center frequency (Hz)');
ylabel('SNR (dB) = 20log_{10}(rms(target)/rms(masker))');
title('Frequency-resolved target-masker SNR by condition');
legend('Location', 'best');
grid on;

%% --- LOCAL FUNCTIONS ---
function [t_filt, m_filt] = bandpass_pair(target, masker, fs, fc, bandwidth_oct, order)
    % Zero-phase 1/N-octave Butterworth bandpass, applied identically to
    % target and masker so the SNR comparison is apples-to-apples.
    %
    % Uses second-order sections (SOS) rather than direct (b,a) transfer-
    % function coefficients: at narrow bandwidths relative to fs (common
    % here at the lower center frequencies), the (b,a) form becomes
    % numerically ill-conditioned and triggers "Matrix is close to
    % singular" warnings from filtfilt. SOS is mathematically the same
    % filter, just a more numerically stable representation of it.
    f_lo = fc * 2^(-bandwidth_oct/2);
    f_hi = fc * 2^( bandwidth_oct/2);

    f_lo = max(f_lo, 1);           % avoid zero/negative edge
    f_hi = min(f_hi, fs/2 - 1);    % avoid exceeding Nyquist

    assert(f_hi > f_lo, ...
        'Invalid band edges for center frequency %.1f Hz at fs = %d', fc, fs);

    [z, p, k] = butter(order, [f_lo f_hi]/(fs/2), 'bandpass');
    [sos, g]  = zp2sos(z, p, k);

    t_filt = filtfilt(sos, g, target);
    m_filt = filtfilt(sos, g, masker);
end
