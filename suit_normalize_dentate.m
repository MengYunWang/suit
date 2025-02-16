function suit_normalize_dentate(job,varargin);
% function suit_normalize_dentate(job,varargin);
% Uses the Dartel algorithm to Normalize the gray matter, white matter and 
% dentate ROI to the extended SUIT template SUIT_dartel2_x.nii, which also
% includes an average dentate template. 
% Dartel is written by John Ashburner and part of the SPM8 / SPM12 package.
%__________________________________________________________________________
% INPUT:
%   job:            job structure from the Batch system (can also be generated by code)
%       job.subjND: Nx1 Structure with individual subjects using fields
%           .gray:   Cell with file name of whole-brain gray-matter segmentation image e.g., {'c1T1.nii'}
%           .white:  Cell with file name of whole-brain white-matter segmentation image e.g., {'c2T1.nii'}
%           .dentateROI: Cell with file name of dentate nucelus
%           .isolation:  Cell with file name of isolation map e.g., {'c_T1_pcereb_corr.nii'}
%__________________________________________________________________________
% OUTPUT:
%    Writes two files in the directory of the gray-matter image:
%       'Affine_c1<filename>.nii': Matrix that contains linear part of the mapping
%       'u_a_c1<filename>.nii'   : Flow field that contains the nonlinear part of the mapping
%__________________________________________________________________________
% EXAMPLE:
%   for s = 1:N % for each subject
%       job.subjND(s).gray = {['<name>_' subjName{s} '_seg1.nii']}; % where subjName is a cell array of subject names
%       job.subjND(s).white = {['<name>_' subjName{s} '_seg2.nii']};
%       job.subjND(s).isolation = {['c_<name>_' subjName{s} '_pcereb.nii']};
%       job.subjND(s).dentateROI = {['<name>_' subjName{s} '_dentate.nii']};
%   end
%   suit_normalise_dartel(job);
% ----------------------------------------------------------------------
% Copyright (C) 2013 
% Joern Diedrichsen 07/04/2013 (j.diedrichsen@ucl.ac.uk)
% & George Prichard 
% Diedrichsen, J. (2006). A spatially unbiased atlas template of the human
% cerebellum. Neuroimage.
% Thanks to John Ashburner for help and
% Dagmar Timmann for data and motivation

% v.2.6: First version: SPM12 compatible
% v.2.7: Template for consistency renamed to SUIT_dartel2_x.nii
% v.3.0: No changes 


% Check input
global defaults;
suit_dir=fileparts(which('suit_normalize_dentate.m'));
template_dir=fullfile(suit_dir,'templates');
for i=1:6
    template{i}=sprintf('%s/SUIT_dartel2_%d.nii',template_dir,i);
end;
affine_prefix='a';


% Deal with variable arguments:
vararginoptions(varargin,{'template'});

SCCSid   = '3.0';
SPMid    = spm('FnBanner',mfilename,SCCSid);

% Now loop over Subjects
numsubj=length(job.subjND);
for s=1 % :numsubj
    S=job.subjND(s);
    
    % Read each Subjects images
    V(1)=spm_vol(S.gray{1});
    V(2)=spm_vol(S.white{1});
    V(3)=spm_vol(S.dentateROI{1});
    V(4)=spm_vol(S.isolation{1});
    [subj_dir,filename{1},ext{1}]=spm_fileparts(S.gray{1});
    [~,filename{2},ext{2}]=spm_fileparts(S.white{1});
    [~,filename{3},ext{3}]=spm_fileparts(S.dentateROI{1});
    VA=spm_vol([template{1} ',1']);
    
    % Make sure that mask volume is maximally 1 
    X=spm_read_vols(V(4)); 
    X=X./max(X(:)); 
    spm_write_vol(V(4),X); 
    
    % mask the images with the isolation map 
    for i=1:3 
        Vm(i)=V(i); 
        Vm(i).fname=fullfile(subj_dir,['m' filename{i} ext{i}]);
        Vm(i)=spm_imcalc(V([i 4]),Vm(i),'i1.*i2'); 
    end; 
    
    % get Affine Alignment to SUIT
    aflags.smosrc=5;
    aflags.regtype='subj';
    aflags.WF=[]; 
    aflags.weight=[];
    Affine=spmj_get_affine_mapping(Vm(1),VA,aflags);
    
    % Sample and bring into affine space 
    [X,Y,Z]=ndgrid(1:VA.dim(1),1:VA.dim(2),1:VA.dim(3));
    num_slice=size(Z,3); 
    for i=1:3
        [Xm,Ym,Zm]=spmj_affine_transform(X,Y,Z,inv(Affine*Vm(i).mat)*VA.mat);
        for z=1:num_slice
            Data(:,:,z,i)=spm_sample_vol(Vm(i),Xm(:,:,z),Ym(:,:,z),Zm(:,:,z),1);
        end;
    end;
    
    % Now normalize nuclei ROI to 1
    m=max(max(max(Data(:,:,:,3))));
    Data(:,:,:,i)=Data(:,:,:,3)./max(1,m);
    
    % adjust the probabilities of white and gray matter maps accordingly
    Data(:,:,:,1)=(1-Data(:,:,:,3)).*Data(:,:,:,1);
    Data(:,:,:,2)=(1-Data(:,:,:,3)).*Data(:,:,:,2);
    
    % Write out the affine-aligned images as precursor to Dartel
    % deformation
    for i=1:3
        Out(i)=V(i);
        Out(i).dim=VA.dim;
        Out(i).mat=VA.mat;
        Out(i).fname=fullfile(subj_dir,['a_' filename{i},ext{i}]);
        spm_write_vol(Out(i),Data(:,:,:,i));
    end;
    
    % Now morph the two using dartel
    rparam={[4 2 1e-06],[2 1 1e-06],[1 0.5 1e-06],[0.5 0.25 1e-06],[0.25 0.125 1e-06],[0.25 0.125 1e-06]};
    K=[0 0 1 2 4 6];
    w.images = {
        {Out(1).fname}
        {Out(2).fname}
        {Out(3).fname}
        }';
    w.settings.rform = 0;
    for i=1:6
        w.settings.param(i).its = 3;
        w.settings.param(i).rparam = rparam{i};
        w.settings.param(i).K = K(i);
        w.settings.param(i).template = {template{i}};
    end;
    w.settings.optim.lmreg = 0.01;
    w.settings.optim.cyc = 3;
    w.settings.optim.its = 3;
    spm_dartel_warp(w);
    save(fullfile(subj_dir,['Affine_' filename{1} '.mat']),'Affine');
    
    % Delete temporary files 
    for i=1:3 
        delete(Vm(i).fname);
        delete(Out(i).fname); 
    end; 
    
end;

function [y1,y2,y3] = spmj_affine_transform(x1,x2,x3,M)
% function [y1,y2,y3] = affine_transform(x1,x2,x3,M)
% -----------------------------------------------------------------
% Affine Transform for input stuff in any format (N-dim strcutures)
% -----------------------------------------------------------------
y1 = M(1,1)*x1 + M(1,2)*x2 + M(1,3)*x3 + M(1,4);
y2 = M(2,1)*x1 + M(2,2)*x2 + M(2,3)*x3 + M(2,4);
y3 = M(3,1)*x1 + M(3,2)*x2 + M(3,3)*x3 + M(3,4);

