function [qt,theight] = FECGSYN_manalysis(abdm_temp,ref_temp,fs)
% This function calculates morphological features form signals given two
% templates (reference and abdm). Statistics are give as %.
%
% Input:
%  abdm_temp:       Template to be tested
%  path_ext:        Path for extracted dataset
%  fs:              Sampling frequency
%
%
% NI-FECG simulator toolbox, version 1.0, February 2014
% Released under the GNU General Public License
%
% Copyright (C) 2014  Joachim Behar & Fernando Andreotti
% Oxford university, Intelligent Patient Monitoring Group - Oxford 2014
% joachim.behar@eng.ox.ac.uk, fernando.andreotti@mailbox.tu-dresden.de
%
% Last updated : 26-09-2014
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>.

global debug

% resampling and repeating templates
FS_ECGPU = 250;     % default sampling frequency for ECGPUWAVE
gain = 200;        % saving gain for WFDB format


%% Preprocessing

% resample case input data not compatible with ECGPUWAVE
% upsampling to 500Hz so that foetal heart looks like an adult heart
abdm_temp = resample(abdm_temp,2*FS_ECGPU,fs);
ref_temp = resample(ref_temp,2*FS_ECGPU,fs);
T_LEN = length(abdm_temp);  % template length
    
wsign1 = abs(max(abdm_temp))>abs(min(abdm_temp));
wsign1 = 2*wsign1 - 1;
abdm_temp = gain*wsign1*abdm_temp/max(abs(abdm_temp)); % normalizing for
wsign2 = abs(max(ref_temp))>abs(min(ref_temp));      % comparing T-height
wsign2 = 2*wsign2 - 1;
ref_temp = gain*wsign2*ref_temp/max(abs(ref_temp));
abdm_sig = repmat(abdm_temp,1,20)';
ref_sig = repmat(ref_temp,1,20)';

% Preprocessing reference channel
% high-pass filter
Fstop = 0.5;  % Stopband Frequency
Fpass = 2;    % Passband Frequency
Astop = 60;   % Stopband Attenuation (dB)
Apass = 0.1;  % Passband Ripple (dB)
h = fdesign.highpass('fst,fp,ast,ap', Fstop, Fpass, Astop, Apass, FS_ECGPU);
Hhp = design(h, 'butter', ...
    'MatchExactly', 'stopband', ...
    'SOSScaleNorm', 'Linf', ...
    'SystemObject', true);
[b_hp,a_hp] = tf(Hhp);
% low-pass filter
Fpass = 80;   % Passband Frequency
Fstop = 100;  % Stopband Frequency
Apass = 1;    % Passband Ripple (dB)
Astop = 60;   % Stopband Attenuation (dB)
h = fdesign.lowpass('fp,fst,ap,ast', Fpass, Fstop, Apass, Astop, FS_ECGPU);
Hlp = design(h, 'butter', ...
    'MatchExactly', 'stopband', ...
    'SOSScaleNorm', 'Linf');
[b_lp,a_lp] = tf(Hlp);
clear Fstop Fpass Astop Apass h Hhp Hlp
ref_sig = filtfilt(b_lp,a_lp,ref_sig);
ref_sig = filtfilt(b_hp,a_hp,ref_sig);

%% Saving data as WFDB
% adapting annotations so that peak occur around 1/3 the cycle length
qrsref = round((0.5 - 1/6)*T_LEN);
qrsabdm = round((0.5 - 1/6)*T_LEN);
qrsref = arrayfun(@(x) qrsref + x*T_LEN,0:19)';
qrsabdm = arrayfun(@(x) qrsabdm + x*T_LEN,0:19)';

% writting to WFDB
tm1 = 1:length(abdm_sig); tm1 = tm1'-1;
tm2 = 1:length(ref_sig); tm2 = tm2'-1;
wrsamp(tm1,abdm_sig,'absig',FS_ECGPU,gain,'')
wrsamp(tm2,ref_sig,'refsig',FS_ECGPU,gain,'')
wrann('absig','qrs',qrsabdm,repmat('N',20,1));
wrann('refsig','qrs',qrsref,repmat('N',20,1));

%% Segmentation using ECGPUWAVE
% ref signal
ecgpuwave('refsig','edr',[],[],'qrs'); % important to specify the QRS because it seems that ecgpuwave is crashing sometimes otherwise
[allref,alltypes_r] = rdann('refsig','edr');
if debug
    close all
    figure(1)
    ax(1)=subplot(2,1,1);
    plot(ref_sig./gain)
    hold on
    plot(allref,ref_sig(allref)./gain,'or')
    text(allref,ref_sig(allref)./gain+0.1,alltypes_r)
    title('Reference Signal')
end
% test signal
ecgpuwave('absig','edr',[],[],'qrs'); % important to specify the QRS because it seems that ecgpuwave is crashing sometimes otherwise
[alltest,alltypes_t] = rdann('absig','edr');
if debug
    figure(1)
    ax(2)=subplot(2,1,2);
    plot(abdm_sig./gain)
    hold on
    plot(alltest,abdm_sig(alltest)./gain,'or')
    text(alltest,abdm_sig(alltest)./gain+0.2,alltypes_t)
    linkaxes(ax,'x')
    title('Test Signal')
end

% == Calculate error on morphological analysis made by extracted data

%% QT-intervals from ref

[qs,tends,twave] = QTcalc(alltypes_r,allref,ref_sig,T_LEN);
% test if QT analysis feasible
if isempty(tends)
    theight = NaN;
    qt = NaN;
    disp('manalysis: Could not encounter QT wave for the template.')
    return
end

try
offset = sum(qrsref<qs(1))*T_LEN;
thref = abs(ref_sig(twave-offset));
qt_ref = mean(tends-qs)*1000/(2*FS_ECGPU);    % in ms
catch
    disp
end

if debug
    close all
    figure('units','normalized','outerposition',[0 0 1 1])
    ax(1)=subplot(2,1,1);
    plot(ref_temp./gain,'k','LineWidth',2)
    hold on
    plot(qs(1)-offset,ref_temp(qs(1)-offset)./gain,'rv','MarkerSize',10,'MarkerFaceColor','r')
    plot(tends(1)-offset,ref_temp(tends(1)-offset)./gain,'ms','MarkerSize',10,'MarkerFaceColor','m')
    plot(twave-offset,ref_temp(twave-offset)./gain,'go','MarkerSize',10,'MarkerFaceColor','g')
    title('Reference Signal')   
end
clear qs tends twave
%% QT-intervals from test

[qs,tends,twave] = QTcalc(alltypes_t,alltest,abdm_sig,T_LEN);
% test if QT analysis feasible
if isempty(tends)
    theight = NaN;
    qt = NaN;
    return
end

offset = sum(qrsref<qs(1))*T_LEN;
thtest = abs(abdm_temp(twave-offset));

if debug   
    figure(1)
    ax(2)=subplot(2,1,2);
    plot(abdm_temp./gain,'k','LineWidth',2)
    hold on
    plot(qs(1)-offset,abdm_temp(qs(1)-offset)./gain,'rv','MarkerSize',10,'MarkerFaceColor','r')
    plot(tends(1)-offset,abdm_temp(tends(1)-offset)./gain,'ms','MarkerSize',10,'MarkerFaceColor','m')
    plot(twave-offset,abdm_temp(twave-offset)./gain,'go','MarkerSize',10,'MarkerFaceColor','g')
    title('Test Signal')
    linkaxes(ax,'x')

end

qt_test = mean(tends-qs)*1000/(2*FS_ECGPU);   % in ms
clear qs tends twave
%% QT error
qt = qt_test - qt_ref;        % absolute error in ms

%% T-height estimation
theight = thtest/thref;

end


function [qs,tends,twave] = QTcalc(ann_types,ann_stamp,signal,T_LEN)
%% Function that contains heuristics behind QT interval calculation
% Attempted to keep binary operations for faster performance. Based on
% assumption that ECGPUWAVE only outputs a wave (p,N,t) if it can detect
% its begin and end. Only highest peak of T-waves marked as biphasic are
% considered for further analysis.
% 
% 
% Inputs
% ann_types:          Type of ALL annotations obtained from ECGPUWAVE
% ann_stamp:          Samplestamp of ALL annotations obtained from ECGPUWAVE
% T_LEN:              Length of template
% 
% Outputs
% qs:                 Q onset locations
% tends:              Locations of T-wave (end)
% twave:              Locations of T-waves (peak)
%
%
%

%== Disregard R-peaks not followed by T-waves
temp_types = ann_types;
temp_stamp = ann_stamp;
obrackts = arrayfun(@(x) strcmp(x,'('),ann_types);      % '('
cbrackts = arrayfun(@(x) strcmp(x,')'),ann_types);      % ')'
pees = arrayfun(@(x) strcmp(x,'p'),ann_types);      % 'p'
temp_types(obrackts|cbrackts|pees) = [];
temp_stamp(obrackts|cbrackts|pees) = [];
annstr = strcat({temp_types'});
idx=cell2mat(regexp(annstr,'Nt'));  % looking for 'N's followed by 't's
fullQT = temp_stamp(idx);           % valid R-peak sample-stamps




% == Q wave (start)
% is defined as an open bracket before the R-peak (no annotation between)
rees = arrayfun(@(x) strcmp(x,'N'),ann_types);          % 'R'
obrackts = arrayfun(@(x) strcmp(x,'('),ann_types);      % '(
idxr = find(rees);                  % R-peak annotation index (in ann_types)
idxqomplete = obrackts(idxr-1);     % finding QRS complexes with begin/end
qs = ann_stamp(idxr(idxqomplete)-1);  % Q locations
cleanqs = ones(size(rees));         % find incomplete beats (to T-elimination)

% == T-wave (end)
% Defined as closing parenthesis after T-wave peak
tees = arrayfun(@(x) strcmp(x,'t'),ann_types);
tees = tees&cleanqs;                            % ignoring T's without Q's
cbrackts = arrayfun(@(x) strcmp(x,')'),ann_types);



% treating T-waves detected as biphasic
biphasic = filter([1 1],1,tees);   % biphasic are marked with 2
idxbi = biphasic==2; idxbi = circshift(idxbi,-1);
tees_all = tees;    % saving for theight analysis


tees(idxbi) = 0;    % only considering latter T annotation




clear obrackts cbrackts cleanqs i idxqomplete 

% no2tees = tees_all;
% no2tees(idxbi|circshift(idxbi,1)) = 0;

% looking for T ends
idxcbrackt = find(tees)+1;
idxsense = cbrackts(idxcbrackt); % only keeping complete 't' followed by ')'
qs(~idxsense) = [];	% clearing incomplete waves
idxcbrackt = idxcbrackt(idxsense); % which c-brackts come right after T's
tends = ann_stamp(idxcbrackt); % T-end locations

% == T-height
if sum(idxbi) > 0
    twave = find(idxbi&tees_all,1);
    twave = [twave twave+1];
    twave = ann_stamp(twave);
    [~,idx] = max(abs(signal(twave)));
    twave = twave(idx);
else
    twave = ann_stamp(tees_all);
    csum = cumsum([0 ; T_LEN*ones(length(twave)-1,1)],1); % removing shift between beats
    twave = mean(twave-csum);
end

% % % isoeletric line
% % waves = find(ann_stamp<twave+length(ref_temp));
% % tbeg = ann_stamp(waves(end)) -length(ref_temp);
% % speak = ann_stamp(waves(end-1))-length(ref_temp);
end
