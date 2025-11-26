classdef FluxPredictorApp < matlab.apps.AppBase
    %% Predict membrane distillation flux from operating parameters.
    %  Launch with: app = FluxPredictorApp;

    properties (Access = private)
        UIFigure             matlab.ui.Figure
        Grid                 matlab.ui.container.GridLayout
        ControlPanel         matlab.ui.container.Panel
        FeedTempField        matlab.ui.control.NumericEditField
        PermeateTempField    matlab.ui.control.NumericEditField
        HotFlowField         matlab.ui.control.NumericEditField
        ColdFlowField        matlab.ui.control.NumericEditField
        PoreSizeField        matlab.ui.control.NumericEditField
        ThicknessField       matlab.ui.control.NumericEditField
        PredictButton        matlab.ui.control.Button
        ReloadButton         matlab.ui.control.Button
        FluxDisplay          matlab.ui.control.Label
        Axes                 matlab.ui.control.UIAxes

        Model                % Trained regression model (LinearModel)
        TrainingData         table
        ActiveFeatureNames   cell
        FeatureNames         cell
        DataFile             string
        InputRanges          struct = struct( ...
            'FeedTemp', [30 90], ...
            'PermeateTemp', [5 25], ...
            'HotFlow', [300 1200], ...
            'ColdFlow', [300 1200], ...
            'PoreSize', [0.1 1.0], ...
            'Thickness', [80 200])
    end

    methods (Access = private)
        function startupFcn(app)
            % Called after UIFigure has been created
            app.DataFile = fullfile(fileparts(mfilename('fullpath')), 'MDData.xlsx');
            app.FeatureNames = { ...
                'FeedTemp', ...
                'PermeateTemp', ...
                'HotFlow', ...
                'ColdFlow', ...
                'PoreSize', ...
                'Thickness'};

            app.InputRanges = struct( ...
                'FeedTemp', [30 90], ...
                'PermeateTemp', [5 25], ...
                'HotFlow', [300 1200], ...
                'ColdFlow', [300 1200], ...
                'PoreSize', [0.1 1.0], ...
                'Thickness', [80 200]);

            app.reloadModel();
            app.updatePrediction();
        end

        function reloadModel(app)
            % Load the Excel data and fit a simple linear regression model.
            opts = detectImportOptions(app.DataFile, 'Sheet', 1, ...
                'VariableNamingRule', 'preserve');
            opts = setvartype(opts, app.FeatureNames, 'double');
            opts.SelectedVariableNames = [app.FeatureNames, {'Flux'}];
            data = readtable(app.DataFile, opts);
            data = rmmissing(data);

            % Fit a linear model using only the requested numeric predictors.
            X = data(:, app.FeatureNames);
            numericX = X{:, :};

            % Detect and drop linearly dependent predictors (including
            % constant columns that conflict with the intercept) to avoid
            % rank deficiency warnings from FITLM.
            design = [ones(size(numericX, 1), 1), numericX];
            [~, R, pivotIdx] = qr(design, 0);
            tol = max(size(design)) * eps(norm(R, 'fro'));
            rankR = sum(abs(diag(R)) > tol);

            % Exclude the intercept column (pivot value 1) when choosing
            % which predictors to keep.
            keptPivots = pivotIdx(1:rankR);
            independentIdx = sort(keptPivots(keptPivots > 1) - 1);

            if isempty(independentIdx)
                warning('FluxPredictorApp:NoPredictors', ...
                    'No independent predictors available after cleaning the data.');
                app.Model = [];
                app.TrainingData = [];
                app.ActiveFeatureNames = {};
                return;
            end

            if numel(independentIdx) < numel(app.FeatureNames)
                removedIdx = setdiff(1:numel(app.FeatureNames), independentIdx);
                removedNames = strjoin(app.FeatureNames(removedIdx), ', ');
                warning('FluxPredictorApp:DependentPredictors', ...
                    'Dependent predictors detected and removed: %s', removedNames);
            end

            app.ActiveFeatureNames = app.FeatureNames(independentIdx);
            X = data(:, app.ActiveFeatureNames);

            app.Model = fitlm(X, data.Flux, 'Intercept', true);
            app.TrainingData = data;

            app.updateAxes();
        end

        function val = getFieldValue(~, field)
            if isnan(field.Value)
                val = 0;
            else
                val = field.Value;
            end
        end

        function field = fieldForFeature(app, featureName)
            switch featureName
                case 'FeedTemp'
                    field = app.FeedTempField;
                case 'PermeateTemp'
                    field = app.PermeateTempField;
                case 'HotFlow'
                    field = app.HotFlowField;
                case 'ColdFlow'
                    field = app.ColdFlowField;
                case 'PoreSize'
                    field = app.PoreSizeField;
                case 'Thickness'
                    field = app.ThicknessField;
                otherwise
                    error('Unknown feature name: %s', featureName);
            end
        end

        function params = collectInput(app)
            params = zeros(1, numel(app.ActiveFeatureNames));
            for idx = 1:numel(app.ActiveFeatureNames)
                field = app.fieldForFeature(app.ActiveFeatureNames{idx});
                params(idx) = app.getFieldValue(field);
            end
        end

        function [isValid, message] = validateInputs(app)
            isValid = true;
            message = "";

            for idx = 1:numel(app.ActiveFeatureNames)
                name = app.ActiveFeatureNames{idx};
                range = app.InputRanges.(name);
                value = app.getFieldValue(app.fieldForFeature(name));

                if value < range(1) || value > range(2)
                    isValid = false;
                    message = sprintf('%s must be between %.2f and %.2f', name, range(1), range(2));
                    return;
                end
            end
        end

        function updatePrediction(app, ~, ~)
            if isempty(app.Model)
                app.FluxDisplay.Text = 'Model not trained yet';
                return;
            end

            [isValid, msg] = app.validateInputs();
            if ~isValid
                app.FluxDisplay.Text = ['Invalid input: ', msg];
                return;
            end

            params = app.collectInput();
            inputTable = array2table(params, 'VariableNames', app.ActiveFeatureNames);
            predictedFlux = predict(app.Model, inputTable);
            app.FluxDisplay.Text = sprintf('Predicted Flux: %.2f', predictedFlux);
        end

        function updateAxes(app)
            % Plot measured vs. predicted flux for training data.
            if isempty(app.Model) || isempty(app.TrainingData)
                return;
            end

            actual = app.TrainingData.Flux;
            predicted = predict(app.Model, app.TrainingData(:, app.ActiveFeatureNames));

            cla(app.Axes);
            scatter(app.Axes, actual, predicted, 60, 'filled');
            hold(app.Axes, 'on');
            lims = [min([actual; predicted]) max([actual; predicted])];
            plot(app.Axes, lims, lims, '--k');
            hold(app.Axes, 'off');
            grid(app.Axes, 'on');
            xlabel(app.Axes, 'Measured Flux');
            ylabel(app.Axes, 'Model Prediction');
            title(app.Axes, 'Training Fit');
        end

        function onReload(app, ~, ~)
            app.reloadModel();
            app.updatePrediction();
        end

        function onChooseDataFile(app, ~, ~)
            [file, path] = uigetfile({'*.xlsx;*.xls', 'Excel files'}, ...
                'Select data file');

            if isequal(file, 0)
                return;
            end

            app.DataFile = fullfile(path, file);

            try
                app.reloadModel();
                app.updatePrediction();
                app.FluxDisplay.Text = ['Model reloaded from ', file];
            catch ME
                warning('FluxPredictorApp:LoadFailed', ...
                    'Failed to load selected data file: %s', ME.message);
                app.FluxDisplay.Text = 'Failed to load selected data file';
            end
        end
    end

    methods (Access = private)
        function createComponents(app)
            % Build UI programmatically to avoid needing .mlapp files.
            app.UIFigure = uifigure('Name', 'Flux Predictor', 'Position', [100 100 720 420]);
            app.Grid = uigridlayout(app.UIFigure, [1 2]);
            app.Grid.ColumnWidth = {'fit', '1x'};

            app.ControlPanel = uipanel(app.Grid, 'Title', 'Inputs');
            app.ControlPanel.Layout.Row = 1;
            app.ControlPanel.Layout.Column = 1;
            controlsGrid = uigridlayout(app.ControlPanel, [10 2]);
            controlsGrid.RowHeight = repmat({'fit'}, 1, 10);
            controlsGrid.ColumnWidth = {'fit', 'fit'};

            % Feed temperature
            uilabel(controlsGrid, 'Text', 'Feed temperature (°C)');
            app.FeedTempField = uieditfield(controlsGrid, 'numeric', ...
                'Limits', app.InputRanges.FeedTemp, 'Value', 60, ...
                'ValueChangedFcn', @(src, evt) app.updatePrediction());

            % Permeate / cold stream temperature
            uilabel(controlsGrid, 'Text', 'Cold temperature (°C)');
            app.PermeateTempField = uieditfield(controlsGrid, 'numeric', ...
                'Limits', app.InputRanges.PermeateTemp, 'Value', 20, ...
                'ValueChangedFcn', @(src, evt) app.updatePrediction());

            % Hot flow rate
            uilabel(controlsGrid, 'Text', 'Hot flow rate (mL/h)');
            app.HotFlowField = uieditfield(controlsGrid, 'numeric', ...
                'Limits', app.InputRanges.HotFlow, 'Value', 600, ...
                'ValueChangedFcn', @(src, evt) app.updatePrediction());

            % Cold flow rate
            uilabel(controlsGrid, 'Text', 'Cold flow rate (mL/h)');
            app.ColdFlowField = uieditfield(controlsGrid, 'numeric', ...
                'Limits', app.InputRanges.ColdFlow, 'Value', 600, ...
                'ValueChangedFcn', @(src, evt) app.updatePrediction());

            % Membrane pore size
            uilabel(controlsGrid, 'Text', 'Pore size (µm)');
            app.PoreSizeField = uieditfield(controlsGrid, 'numeric', ...
                'Limits', app.InputRanges.PoreSize, 'Value', 0.22, ...
                'ValueChangedFcn', @(src, evt) app.updatePrediction());

            % Membrane thickness
            uilabel(controlsGrid, 'Text', 'Thickness (µm)');
            app.ThicknessField = uieditfield(controlsGrid, 'numeric', ...
                'Limits', app.InputRanges.Thickness, 'Value', 200, ...
                'ValueChangedFcn', @(src, evt) app.updatePrediction());

            % Buttons
            app.PredictButton = uibutton(controlsGrid, 'Text', 'Predict now', ...
                'ButtonPushedFcn', @(src, evt) app.updatePrediction());
            app.PredictButton.Layout.Column = [1 2];

            app.ReloadButton = uibutton(controlsGrid, 'Text', 'Reload & retrain', ...
                'ButtonPushedFcn', @(src, evt) app.onReload());
            app.ReloadButton.Layout.Column = [1 2];

            uploadButton = uibutton(controlsGrid, 'Text', 'Load data file...', ...
                'ButtonPushedFcn', @(src, evt) app.onChooseDataFile());
            uploadButton.Layout.Column = [1 2];

            % Output label
            app.FluxDisplay = uilabel(controlsGrid, 'Text', 'Predicted Flux: --', ...
                'FontWeight', 'bold');
            app.FluxDisplay.Layout.Column = [1 2];

            % Axes for training performance
            app.Axes = uiaxes(app.Grid);
            app.Axes.Layout.Row = 1;
            app.Axes.Layout.Column = 2;
            title(app.Axes, 'Training Fit');
            xlabel(app.Axes, 'Measured Flux');
            ylabel(app.Axes, 'Model Prediction');
        end
    end

    methods (Access = public)
        function app = FluxPredictorApp
            createComponents(app);
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @startupFcn);
        end

        function delete(app)
            delete(app.UIFigure);
        end
    end
end
