function [midi_versions] = destroy_structure_midi_excerpt_yi(fname, input_dir, output_dir, start_time_sec, end_time_sec, unscramble, rand_pitch, rand_dur, rand_onset)

prefixes = {'unscram_', 'scram_pitch_', 'scram_pitch_onset_', 'scram_onset_', 'scram_pitch_duration_', 'scram_duration_', 'reassign_pitch_'};
prefixes2 = {'reassign_pitch_onset_'};
%% not needed if using forMine.m
% 
% input_dir = '/Users/yiwei/Dropbox/Mine';
% output_dir = '/Users/yiwei/Dropbox/Mine';
% fname = 'RootBeerRag.mid';
% 
% unscramble = 1;
% rand_pitch=1; % need to set to 1 in order to get all the rest of the jitter conditions. 
% rand_dur=1; 
% rand_onset=1;

%% copy pasted from mdlMStrToNMat.m, so we know what each column of the nmat file does. 

%   1. Onset (beats) (calc'ed solely from ticks-per-quarter-note)
%   2. Duration beats
%   3. Channel
%   4. MIDI pitch
%   5. mIdI velocity
%   6. Onset (sec)
%   7. Duration (sec)

%% getting basic info of the midi file

%midiStructure = mdlMidiToMStr([input_dir '\' fname]);\
midiStructure = mdlMidiToMStr('/Users/minemuezzinoglu/Desktop/MATLAB/RootBeerRag.mid');
tpqn = midiStructure.ticks_per_quarter_note;
%nmat_original = readmidi([input_dir '\' fname]);
nmat_original = readmidi('/Users/minemuezzinoglu/Desktop/MATLAB/RootBeerRag.mid');
tempo = gettempo(nmat_original);

%% some optional code if you want to start/end the midi file at a specific time
% 
% % (yi: only need these 2 lines if you don't want any initial pause)
% 
% nmat_original(:,1) = nmat_original(:,1)-nmat_original(1,1); %get rid of initial pause if there is one
% nmat_original(:,6) = nmat_original(:,6)-nmat_original(1,6);
% 
% 
% % move to start time (yi: only need these 4 lines if you want your new
% midi file to start from a specific time of your original midi file)
% 
% start_index = min(find(nmat_original(:,6)>=start_time_sec));
% temp = nmat_original(start_index:size(nmat_original,1),:);
% temp(:,1) = temp(:,1)-temp(1,1);
% temp(:,6) = temp(:,6)-temp(1,6);
% 
% 
% % chop off everything after excerpt length (yi: only need these 2 lines if 
% % you want your new midi file to stop at a specific length)
% 
% end_index = min(find(temp(:,6)>excerpt_length_sec));
% nmat_original = temp(1:end_index,:);

%% writing the unscrambled version

if unscramble

    writemidi(nmat_original, [output_dir '/' prefixes{1} fname], tempo, tpqn);

end 

%% randomize pitch

if rand_pitch

    inst_notes = find(nmat_original(:,3)~=10); %3rd column indicates the MIDI
    %channel; 10 is percussion channel
    %so we leave its "pitch" alone
    all_notes = nmat_original(inst_notes,4); %4th column contains the pitch in semitones
    aton_notes = all_notes+6*rand(size(all_notes))-3; %add random value to
    %blur tonal pitch distribution
    aton_notes = round(aton_notes); %round to integer
    notes_sorted = sort(aton_notes);
    x=rand(size(notes_sorted));
    x(:,2)=1:size(all_notes,1);
    y=sortrows(x,1);

    nmat_jitter_pitch = nmat_original;
    nmat_jitter_pitch(inst_notes,4) = notes_sorted(y(:,2)); %randomly assign pitches to notes in piece
    writemidi(nmat_jitter_pitch, [output_dir '/' prefixes{2} fname], tempo, tpqn);

end

%% jitter note onset

beats_per_sec = mode(nmat_original(:,2)./nmat_original(:,7));

if rand_onset
    if rand_pitch

        jitter = rand(size(nmat_original(:,1)));

        % jitter both pitch and onset
        nmat_jitter_pitch_onset = nmat_jitter_pitch;

        % jitter onset in both columns 1 & 6 
        % columns 1 and 6 both have onset, but in different units
        nmat_jitter_pitch_onset(:,1) = nmat_jitter_pitch_onset(:,1)+jitter;
        nmat_jitter_pitch_onset(:,6) = nmat_jitter_pitch_onset(:,1)/beats_per_sec; 
        
        % make sure jittering does not mess up order.
        % this is where the original code has a bug so that the onset
        % timing was not sorted by channel, but across all channels. So I
        % deleted those two line (77-78) and added this function to sort
        % onset timing by channel. 

        % check how many channels are in this file
        channel_nums = unique(nmat_original(:,3));        
        all_channels = cell(length(channel_nums),1);
        for i = 1:length(channel_nums)
            temp_channel = [];
            temp_channel(:,:) = nmat_jitter_pitch_onset(nmat_jitter_pitch_onset(:,3) == channel_nums(i), :);
            temp_channel(:,1) = sort(temp_channel(:,1));
            temp_channel(:,6) = sort(temp_channel(:,6));
            all_channels{i} = temp_channel;
        end
        nmat_jitter_pitch_onset = cell2mat(all_channels);

        writemidi(nmat_jitter_pitch_onset, [output_dir '/' prefixes{3} fname], tempo, tpqn);
        
        % jitter only the onset while keeping the original pitch.
        nmat_jitter_onset = nmat_jitter_pitch_onset;
        nmat_jitter_onset(:,4) = nmat_original(:,4); %use unscrambled pitch
        writemidi(nmat_jitter_onset, [output_dir '/' prefixes{4} fname], tempo, tpqn);
    
    end
end
%% randomize duration

if rand_dur
    if rand_pitch

        all_durs_beats = nmat_original(:,2);
        clear x y
        x=rand(length(all_durs_beats),1);
        x(:,2)=1:length(all_durs_beats);
        y=sortrows(x,1);
        
        % jitter both pitch and duration
        nmat_pitch_duration = nmat_jitter_pitch;
        nmat_pitch_duration(:,2)=all_durs_beats(y(:,2)); %randomly assign durations to notes
        nmat_pitch_duration(:,7)=nmat_pitch_duration(:,2)/beats_per_sec; %columns 2 and 7 both
        %represent duration, just in diff units
        writemidi(nmat_pitch_duration, [output_dir '/' prefixes{5} fname], tempo, tpqn);

        % jitter only the duration while keeping the original pitch
        nmat_duration = nmat_pitch_duration;
        nmat_duration(:,4) = nmat_original(:,4); %use correct pitch
        writemidi(nmat_duration, [output_dir '/' prefixes{6} fname], tempo, tpqn);

    end
end
%% re-assign pitch values
if reassign_pitch
    inst_notes2 = find(nmat_original(:,3)~=10);
    all_notes2 = nmat_original(inst_notes2,4); 
    nmat_reassign = nmat_original;
    rand_all_notes2 = all_notes2(randperm(length(all_notes2)));
   channel_nums = unique(nmat_original(:,3));
    for jj = 1:length(channel_nums)
        channel_notes_index = find(nmat_original(:,3)==channel_nums(jj));
       channel_notes = nmat_original(channel_notes_index,4);
       rand_channel_notes = channel_notes(randperm(length(channel_notes)));
        for ii=1:length(channel_notes)
        nmat_reassign(ii, 4) = rand_channel_notes(ii);
        end
    end
    writemidi(nmat_reassign, [output_dir '/' prefixes{7} fname], tempo, tpqn);
    
end

%% re-assign pitch and jitter

beats_per_sec = mode(nmat_original(:,2)./nmat_original(:,7));

if rand_onset
    if reassign_pitch

        jitter = rand(size(nmat_original(:,1)));

        % jitter both pitch and onset
        nmat_jitter_pitch_onset = nmat_reassign;

        % jitter onset in both columns 1 & 6 
        % columns 1 and 6 both have onset, but in different units
        nmat_jitter_pitch_onset(:,1) = nmat_jitter_pitch_onset(:,1)+jitter;
        nmat_jitter_pitch_onset(:,6) = nmat_jitter_pitch_onset(:,1)/beats_per_sec; 
        
        % make sure jittering does not mess up order.
        % this is where the original code has a bug so that the onset
        % timing was not sorted by channel, but across all channels. So I
        % deleted those two line (77-78) and added this function to sort
        % onset timing by channel. 

        % check how many channels are in this file
        channel_nums = unique(nmat_original(:,3));        
        all_channels = cell(length(channel_nums),1);
        for i = 1:length(channel_nums)
            temp_channel = [];
            temp_channel(:,:) = nmat_jitter_pitch_onset(nmat_jitter_pitch_onset(:,3) == channel_nums(i), :);
            temp_channel(:,1) = sort(temp_channel(:,1));
            temp_channel(:,6) = sort(temp_channel(:,6));
            all_channels{i} = temp_channel;
        end
        nmat_jitter_pitch_onset = cell2mat(all_channels);

        writemidi(nmat_jitter_pitch_onset, [output_dir '/' prefixes2{1} fname], tempo, tpqn);
        
        % jitter only the onset while keeping the original pitch.
        nmat_jitter_onset = nmat_jitter_pitch_onset;
        nmat_jitter_onset(:,4) = nmat_original(:,4); %use unscrambled pitch
        writemidi(nmat_jitter_onset, [output_dir '/' prefixes{4} fname], tempo, tpqn);
    
    end
end


midi_versions = {};

