function do_system_testing(dataset, feature_path, result_path, model_path, ...
    feature_params, params, ...
    dataset_evaluation_mode, classifier_method, overwrite)
% System testing.
% 
% If extracted features are not found from disk, they are extracted but not saved.
%
% Parameters
% ----------
% dataset : class
%     dataset class
% 
% result_path : str
%     path where the results are saved.
% 
% feature_path : str
%     path where the features are saved.
% 
% model_path : str
%     path where the models are saved.
% 
% feature_params : struct
%     parameter struct
% 
% dataset_evaluation_mode : str ['folds', 'full']
%     evaluation mode, 'full' all material available is considered to belong to one fold.
% 
% classifier_method : str ['gmm', 'liblinear']
%     classifier method, currently only GMM and LIBLINEAR supported
% 
% overwrite : bool
%     overwrite existing models
% 
% Returns
% -------
% nothing
% 
% Raises
% -------
% error
%     classifier_method is unknown.
%     Model file not found.
%     Audio file not found.
% 

if isfield(params, 'transform')
    transformation = params.transform;
else
    transformation = 'identity';
end

if ~any(strcmp(classifier_method,{'gmm','liblinear'}))
    error(['Unknown classifier method [',classifier_method,']']);
end
% Check that target path exists, create if not
check_path(result_path);

feature_params_fs = feature_params.fs;

progress(1, 'Testing', 0, '');
parfor fold=dataset.folds(dataset_evaluation_mode)        
    current_result_file = get_result_filename(fold, result_path);
    if or(~exist(current_result_file, 'file'), overwrite)
        results = [];
        
        % Load class model container
        model_filename = get_model_filename(fold, model_path);
        if exist(model_filename, 'file')
            model_container = load_data(model_filename);
        else
            error(['Model file not found [', model_filename, ']']);
        end
        
        test_items = dataset.test(fold);

        for item_id=1:length(test_items)
            item = test_items(item_id);
            if fold == 1
                progress(0, 'Testing', ...
                    (item_id / length(test_items)), item.file,fold);
            end

            % Load features
            feature_filename = get_feature_filename(item.file, feature_path);
            if exist(feature_filename, 'file')
                feature_data = load_data(feature_filename);
                feature_data = feature_data.feat;
            else
                if exist(dataset.relative_to_absolute_path(item.file),'file')
                    [y, fs] = load_audio( ...
                        dataset.relative_to_absolute_path(item.file), ...
                        'mono', true, 'fs', feature_params_fs);
                else
                    error(['Audio file not found [',item.file,']']);
                end
                if isfield(feature_params, 'scattering')
                    feature_data = ...
                        scattering_extraction(y, feature_params.scattering.archs);
                else
                    feature_data = feature_extraction(y, fs, ...
                      'statistics', true, ...
                      'include_mfcc0', feature_params.include_mfcc0, ...
                      'include_delta', feature_params.include_delta, ...
                      'include_acceleration', feature_params.include_acceleration, ...
                      'mfcc_params', feature_params.mfcc, ...
                      'delta_params', feature_params.mfcc_delta, ...
                      'acceleration_params', feature_params.mfcc_acceleration); 
                end

                feature_data = feature_data.feat;

            end
            
            % Transform features
            if strcmp(transformation, 'log')
                feature_data = log(eps() + feature_data);
            end
            
            % Normalize features
            feature_data = model_container.normalizer.normalize(feature_data);

            % Concatenate azimuths
            if ~ismatrix(feature_data)
                feature_data = feature_data(:, :, floor(1+(end/2)));
            end
            
            % Do classification for the block
            if strcmp(classifier_method, 'gmm')
                current_result = ...
                    do_classification_gmm(feature_data, model_container);
            elseif strcmp(classifier_method, 'liblinear')
                current_result = ...
                    do_classification_liblinear(feature_data, model_container);
            else
               error(['Unknown classifier method ', classifier_method, ']']);
            end

            % Store the result
            results = [results; {item.file, current_result}];

        end

        % Save testing results
        fid = fopen(current_result_file, 'wt');
        for result_id=1:size(results,1)
            result_item = results(result_id,:);
            fprintf(fid,'%s\t%s\n', result_item{1}, result_item{2});
        end
        fclose(fid);
    end
end
disp('  ');
end
