%% Modulation spectrum analysis of masking stimuli
%
% Extracts the amplitude-modulation ("envelope") spectrum of each masker
% and compares it across conditions. This checks whether conditions differ
% in their temporal modulation content (e.g. rhythmic regularity), which
% is a separate potential confound from the spectral one addressed in
% spectral_snr_analysis.m.
%
% Steps:
%  1. Extract the envelope of each masker segment via the Hilbert transform.
%  2. Low-pass filter the envelope to remove residual carrier structure,
%     keeping only slow amplitude fluctuations.
%  3. Take the magnitude spectrum of the envelope (FFT) -> "modulation
%     spectrum": how much energy the envelope has at each modulation rate.
%  4. Compare modulation spectra across conditions, focusing on rates
%     relevant to speech rhythm (roughly 2-20 Hz).
%
% DESIGN (matches spectral_snr_analysis.m): each masker is one audio
% track per condition, crossed with every target story; the actual
% segment analyzed for a given story is the same offset-adjusted window
% used there (masker starts at t=0, story starts onset_offset_sec later,
% window ends when the story ends). The target audio itself isn't used
% here -- only its length, to determine how much masker to extract.

clear; clc; close all;

%% --- USER SETTINGS ---
conditions = struct( ...
    'name', {'rhythm_jittered','pitch_scrambled','combined','reverse','music'}, ...
    'masker_files', { ...
        {'/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/background noise/onset_GoodBait.wav'}, ...
        {'/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/background noise/pitch_GoodBait.wav'}, ...
        {'/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/background noise/pitch_onset_GoodBait.wav'}, ...
        {''}, ...   % 'reverse' is derived below by time-reversing the 'music' file directly -- see note
        {'/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/background noise/unscram_goodbait.wav'} ...
    });

onset_offset_sec = 1.5;   % masker starts this many seconds before the story does

target_files = { ...
    '/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/stories/dam.wav', ...
    '/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/stories/donkey.wav', ...
    '/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/stories/grandfather.wav', ...
    '/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/stories/raiden.wav', ...
    '/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/stories/raven.wav', ...
    '/Users/minemuezzinoglu/Documents/MATLAB/audio/Study2 Analysis/stories/whitehorse.wav'
};
[~, target_names] = cellfun(@fileparts, target_files, 'UniformOutput', false);

presentation_fs = 44100;  % confirmed against the Audacity-exported combined files
offset_samples  = round(onset_offset_sec * presentation_fs);

env_lowpass_hz = 50;   % keep envelope fluctuations up to this rate
mod_freq_max   = 30;   % Hz, upper limit for plotting the modulation spectrum

mod_band_centers = [1 2 4 8 16];                       % Hz, octave-spaced
mod_band_edges   = [mod_band_centers'/sqrt(2), mod_band_centers'*sqrt(2)];
n_mod_bands      = numel(mod_band_centers);

%% --- COMPUTE ---
results = struct();

for c = 1:numel(conditions)
    cond      = conditions(c);
    n_targets = numel(target_files);
    mod_spectra = [];  % one modulation spectrum per story, stacked as rows
    freq_axis   = [];
    mod_snr     = nan(n_targets, n_mod_bands);   % NEW: one row per story, one column per band

    if strcmpi(cond.name, 'reverse')
        music_idx = find(strcmpi({conditions.name}, 'music'), 1);
        assert(~isempty(music_idx), 'No condition named "music" found to derive "reverse" from.');
        [masker_raw, fs_m] = audioread(conditions(music_idx).masker_files{1});
        masker_raw = mean(masker_raw, 2);
    else
        [masker_raw, fs_m] = audioread(cond.masker_files{1});
        masker_raw = mean(masker_raw, 2);  % force mono if stereo
    end

    if fs_m ~= presentation_fs
        masker_raw = resample(masker_raw, presentation_fs, fs_m);
        fs_m = presentation_fs;
    end

    for t = 1:n_targets
        [target, fs_t] = audioread(target_files{t});
        target = mean(target, 2);
        if fs_t ~= presentation_fs
            target = resample(target, presentation_fs, fs_t);
            fs_t = presentation_fs;
        end
        assert(fs_t == fs_m, ...
            'Sample rate mismatch after resampling: target "%s" vs masker for condition %s', target_names{t}, cond.name);

        % Same offset-adjusted window as spectral_snr_analysis.m
        n = min(length(target), length(masker_raw) - offset_samples);
        target = target(1:n);   % NEW: trim target to the analysis window

        if strcmpi(cond.name, 'reverse')
            needed_length    = offset_samples + n;
            pre_trim_segment = masker_raw(1:needed_length);
            reversed_segment = flipud(pre_trim_segment);
            masker = reversed_segment(offset_samples+1 : offset_samples+n);
        else
            masker = masker_raw(offset_samples+1 : offset_samples+n);
        end

        [mod_spec, f] = modulation_spectrum(masker, fs_m, env_lowpass_hz);

        % NEW: target modulation spectrum (same length as masker, so same f)
        [mod_spec_t, ~] = modulation_spectrum(target, fs_m, env_lowpass_hz);

        % NEW: modulation SNR in each band (10*log10 because these are powers)
        for b = 1:n_mod_bands
            in_band = f >= mod_band_edges(b,1) & f < mod_band_edges(b,2);
            P_t = sum(mod_spec_t(in_band).^2);
            P_m = sum(mod_spec(in_band).^2);
            mod_snr(t, b) = 10*log10(P_t / P_m);
        end

        if isempty(freq_axis)
            freq_axis = f;
        end
        % Interpolate onto a common frequency axis in case segments differ
        % in length; (:)' forces a row vector before stacking.
        mod_spec_interp = interp1(f, mod_spec, freq_axis, 'linear', 'extrap');
        mod_spectra = [mod_spectra; mod_spec_interp(:)']; %#ok<AGROW>
    end

    results.(cond.name).freq_axis         = freq_axis;
    results.(cond.name).mod_spectra       = mod_spectra;
    results.(cond.name).mean_mod_spectrum = mean(mod_spectra, 1);
    results.(cond.name).mod_snr           = mod_snr;            % NEW
    results.(cond.name).mean_mod_snr      = mean(mod_snr, 1);   % NEW
end


% YW comment: it looks like for every story, you get a mod_spectra for its masker, do
% you plan to compare mod_spectra of the masker to mod_spectra of the
% story? Or do you plan to run the same spectral_snr_analysis on your
% envelope_smooth of the target versus the envelope_smooth of the
% masker. These two options are similar to each other. 


%% --- SUMMARY: peak modulation magnitude near 2 Hz, all conditions ---
% Numeric values for the manuscript, rather than reading peak heights off
% the plot by eye. Reports the peak within a narrow window around the
% fundamental beat rate visible in the plot (~2 Hz), for every condition.
fprintf('--- Peak modulation magnitude near 2 Hz, by condition ---\n');
cond_names = {conditions.name};
peak_2hz = nan(numel(cond_names), 1);
for c = 1:numel(cond_names)
    f = results.(cond_names{c}).freq_axis;
    m = results.(cond_names{c}).mean_mod_spectrum;
    near_2hz = f >= 1.5 & f <= 2.5;
    peak_2hz(c) = max(m(near_2hz));
    fprintf('  %-16s peak near 2 Hz = %.5f\n', cond_names{c}, peak_2hz(c));
end
fprintf('  (music/reverse ratio: %.3f -- should be close to 1.0)\n\n', ...
    peak_2hz(strcmpi(cond_names,'reverse')) / peak_2hz(strcmpi(cond_names,'music')));

%% --- NEW: modulation SNR by band, all conditions ---
cond_names = {conditions.name};
all_mod_snr = nan(numel(cond_names), n_mod_bands);
for c = 1:numel(cond_names)
    all_mod_snr(c,:) = results.(cond_names{c}).mean_mod_snr;
end

fprintf('--- Modulation SNR (target vs masker envelope power), mean across stories ---\n');
fprintf('%-16s', 'condition');
fprintf('%8.0f Hz', mod_band_centers);
fprintf('\n');
for c = 1:numel(cond_names)
    fprintf('%-16s', cond_names{c});
    fprintf('%10.2f', all_mod_snr(c,:));
    fprintf('\n');
end

mod_spread = max(all_mod_snr, [], 1) - min(all_mod_snr, [], 1);
fprintf('%-16s', 'spread');
fprintf('%10.2f', mod_spread);
fprintf('\n\n');

%% --- PLOT ---
figure; hold on;
cond_names = {conditions.name};
colors = lines(numel(cond_names));

for c = 1:numel(cond_names)
    f = results.(cond_names{c}).freq_axis;
    m = results.(cond_names{c}).mean_mod_spectrum;
    keep = f <= mod_freq_max;
    if strcmpi(cond_names{c}, 'reverse')
        line_style = '--';
        line_width = 2.5;
    else
        line_style = '-';
        line_width = 1.5;
    end
    plot(f(keep), m(keep), line_style, 'Color', colors(c,:), 'LineWidth', line_width, ...
        'DisplayName', strrep(cond_names{c}, '_', ' '));
end

xlabel('Modulation frequency (Hz)');
ylabel('Modulation spectrum magnitude (a.u.)');
title('Envelope modulation spectrum by masker condition');
legend('Location', 'best');
grid on;

%% --- LOCAL FUNCTIONS ---
function [mod_spec, freq_axis] = modulation_spectrum(signal, fs, lowpass_hz)
    % Envelope via Hilbert transform
    envelope = abs(hilbert(signal));

    % Low-pass the envelope to remove residual carrier ripple.
    % Uses second-order sections (SOS) for numerical stability, same
    % reasoning as the bandpass filters in spectral_snr_analysis.m.
    [z, p, k] = butter(4, lowpass_hz/(fs/2), 'low');
    [sos, g]  = zp2sos(z, p, k);
    envelope_smooth = filtfilt(sos, g, envelope);

    % Normalize by mean level so the spectrum reflects relative
    % fluctuation (modulation depth), not overall loudness
    envelope_smooth = envelope_smooth / mean(envelope_smooth);

    % Remove DC (mean is now 1) before taking the spectrum
    envelope_ac = envelope_smooth - 1;

    n = length(envelope_ac);
    nfft = 2^nextpow2(n);
    spec = abs(fft(envelope_ac, nfft)) / n;
    spec = spec(1:nfft/2+1);
    spec(2:end-1) = 2*spec(2:end-1);  % single-sided spectrum correction

    freq_axis = (0:nfft/2)' * (fs/nfft);
    mod_spec = spec;
end
