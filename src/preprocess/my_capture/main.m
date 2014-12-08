% This is a new script to load in RGB, depth and mask from OSD
% Then reproject RGB into depth
% Then smooth
% Then crop
% Then save
clear
addpath('~/projects/shape_sharing/src/matlab/matlab_features')
addpath ('../bigbird/crop_smooth/')

load('../edges_and_compass/data/modelNyud.mat')
%%
addpath('/Users/Michael/builds/research_code/structured_edge_detection/release')
addpath(genpath('/Users/Michael/projects/shape_sharing/src/matlab/toolbox'))
addpath('../edges_and_compass/angled_edges/')
addpath('../edges_and_compass')
%matlabpool(6)

%% create base path and all the names
base_path = '/Users/Michael/projects/shape_sharing/data/other_3D/from_biryani/'
%%
dd = dir(base_path)
names = {}
for ii = 1:length(dd)
    if dd(ii).name(end-11:end) == 'depth.tiff'
  %      names{end+1} = 
    end
end
%% get names
%names = {'frame_20141120T134535.682741_'};
names = {'frame_20141120T185954.959422_'};
%names = {'frame_20141121T145136.414620_'}
%{    
frame_20141120T134535.682741_', ...
'frame_20141120T185954.959422_', ...
'frame_20141120T213448.378796_', ...
'frame_20141120T213442.525035_', ...
'frame_20141120T213440.257049_', ...
'frame_20141120T213449.827419_'}
%}
ii = 1
OVERWRITE = true;
%%
for ii = 1:length(names)
    
    name = names{ii};
    im.name = name;
    
    %% %%% LOADING
    rgb_path = fullfile(base_path, [name, 'rgb.tiff']);
    im.rgb = imread(rgb_path);
   % im.rgb = im.rgb(50:end, 1:550, :);
    
    depth_path = fullfile(base_path, [name, 'depth.tiff']);
    im.depth = double(imread(depth_path)) / 1000;
   % im.depth= im.depth(50:end, 1:550);
    
    %%%%% SEEING IF SHOUD SKIP
    save_name = fullfile(base_path, 'mdf', [name, '.mat']);

    if ~OVERWRITE && exist(save_name, 'file')
        disp(['Skipping ' save_name])
        continue
    end

    %% %%%%% SMOOTHING
    %plot_bb(bb_cropped)
    equ_grey = rgb2gray(im2double(im.rgb));
    im.smoothed_depth = fill_depth_colorization_ft_mex(equ_grey, im.depth);
    
    %% %%%% EDGES
    im.struct_edges = edgesDetect(im.smoothed_depth, model);
    im.struct_edges_canny = depth_canny(im.struct_edges, im.smoothed_depth);
    se = strel('disk',1);
    im.edges = imdilate(im.struct_edges_canny, se);
    
    
    %% %%%% EDGE DIREFTIONS???
    
    %% REPROJECT TO 3D
    im.K = [570.0, 0, 320.0; 0, 570.0, 240; 0, 0, 1];
    im.xyz = reproject(im.smoothed_depth, im.K, 2.0);
    
    %% NORMALS
    [im.norms, im.curve] = normals_wrapper( im.xyz, 'knn', 150 );
    
    %% PLANE DETECTION
    [im.seg, im.up] = segment_prism_mex(im.xyz, im.norms, im.curve, 2, 20000, 100, 0.4, 0.04);
    
    %% segment the points on the plane
    dists = dot(im.xyz, repmat(im.up(1:3), size(im.xyz, 1), 1), 2);
    errors = abs(dists + im.up(4));
    outliers_vector = errors < 0.02 | dists < -im.up(4);
    outliers = reshape(outliers_vector, size(im.smoothed_depth));
    imagesc(reshape(outliers, size(im.smoothed_depth)) + im.edges*2);
    
    im.mask = ~outliers & ~imdilate(im.edges, se) & ...
        (im.smoothed_depth< 1.2) & reshape(im.norms(:, 3)<-0.4, size(im.smoothed_depth)) & ...
        reshape(im.xyz(:, 1) < 0.35, size(im.smoothed_depth))
   % im.mask(1:50, :) = 0;
    
    %% Quickly augment the edges with depths on the plane
    new_edges = edge(im.mask);
    im.edges = imdilate(new_edges | im.struct_edges_canny, se);
    
    %% SPIDER
    im.spider = spider_wrapper(im.xyz, im.norms, im.edges, im.mask, im.K(1));
    
    %% removing shit
    im = rmfield(im, {'struct_edges', 'struct_edges_canny', 'curve', 'seg', 'depth'});
    
    %% SAving
    im.rgb = im2double(im.rgb);
    save(save_name, '-struct', 'im');
    

%%
    disp(['Done model ', name, ' ', num2str(ii)])
    
end
%%

%plotNormals(bb_cropped.xyz, bb_cropped.normals, 0.01)

%% plotting
close all
subplot(231)
%imagesc(im.depth)
axis image
subplot(232)
imagesc(im.smoothed_depth)
axis image
subplot(233)
imagesc(im.rgb)
axis image
subplot(234)
%imagesc(im.struct_edges)
axis image
subplot(235)
imagesc(im.edges)
axis image
subplot(236)
imagesc(im.mask)
axis image


%% slices
slices = [25, 50, 75, 100, 125, 150, 175, 200, 250, 250]
for ii = 1:length(slices)
    
    subplot(4, 4, ii)
    imagesc(flipud(squeeze(prediction(:, :, slices(ii)))'))
    set(gca, 'clim', [-0.03, 0.03])
    axis image
end
subplot(4, 4, ii+1)
imagesc(im.rgb)
axis image

%% displayin the spider
for ii = 1:12
    subplot(4, 3, ii)
    imagesc((im.spider(:, :, ii)))
    axis image
    colormap(jet)
    T = im.spider(:, :, ii);
    mind = prctile(T(:), 5);
    maxd = prctile(T(:), 95);
    set(gca, 'clim', [mind, maxd])
    colorbar
end



%% Saving the image

subplot(231)
imshow(im.rgb)
imwrite(im.rgb, 'preprocess_a.png')

im.dmin = nanmin(im.smoothed_depth(im.smoothed_depth(:)~=0))
im.dmax = nanmax(im.smoothed_depth(:))

subplot(232)
h = imagesc(im.depth);
set(h, 'AlphaData', im.depth~=0)
set(gca, 'clim', [im.dmin, im.dmax])
axis image off
temp_depth = im.depth;
temp_depth(temp_depth == 0) = nan;
imwrite(convert_to_jet(temp_depth, im.dmin, im.dmax), 'preprocess_b.png')

subplot(233)
imagesc(im.smoothed_depth)
set(gca, 'clim', [im.dmin, im.dmax])
axis image off
imwrite(convert_to_jet(im.smoothed_depth, im.dmin, im.dmax), 'preprocess_c.png')

subplot(234)
imshow(im.struct_edges)
imwrite(im.struct_edges, 'preprocess_d.png')

subplot(235)
imshow(im.edges)
imwrite(im.edges, 'preprocess_e.png')

colormap(jet)
axis image

