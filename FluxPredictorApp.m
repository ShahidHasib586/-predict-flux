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
        FeatureNames         cell
        DataFile             string
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

        function params = collectInput(app)
            params = [ ...
                app.getFieldValue(app.FeedTempField), ...
                app.getFieldValue(app.PermeateTempField), ...
                app.getFieldValue(app.HotFlowField), ...
                app.getFieldValue(app.ColdFlowField), ...
                app.getFieldValue(app.PoreSizeField), ...
                app.getFieldValue(app.ThicknessField)];
        end

        function updatePrediction(app, ~, ~)
            if isempty(app.Model)
                app.FluxDisplay.Text = 'Model not trained yet';
                return;
            end

            params = app.collectInput();
            predictedFlux = predict(app.Model, params);
            app.FluxDisplay.Text = sprintf('Predicted Flux: %.2f', predictedFlux);
        end

        function updateAxes(app)
            % Plot measured vs. predicted flux for training data.
            if isempty(app.Model) || isempty(app.TrainingData)
                return;
            end

            actual = app.TrainingData.Flux;
            predicted = predict(app.Model, app.TrainingData(:, app.FeatureNames));

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
            controlsGrid = uigridlayout(app.ControlPanel, [8 2]);
            controlsGrid.RowHeight = repmat({'fit'}, 1, 8);
            controlsGrid.ColumnWidth = {'fit', 'fit'};

            % Feed temperature
            uilabel(controlsGrid, 'Text', 'Feed temperature (°C)');
            app.FeedTempField = uieditfield(controlsGrid, 'numeric', ...
                'Limits', [0 Inf], 'Value', 60, 'ValueChangedFcn', @(src, evt) app.updatePrediction());

            % Permeate / cold stream temperature
            uilabel(controlsGrid, 'Text', 'Cold temperature (°C)');
            app.PermeateTempField = uieditfield(controlsGrid, 'numeric', ...
                'Limits', [0 Inf], 'Value', 20, 'ValueChangedFcn', @(src, evt) app.updatePrediction());

            % Hot flow rate
            uilabel(controlsGrid, 'Text', 'Hot flow rate (mL/min)');
            app.HotFlowField = uieditfield(controlsGrid, 'numeric', ...
                'Limits', [0 Inf], 'Value', 600, 'ValueChangedFcn', @(src, evt) app.updatePrediction());

            % Cold flow rate
            uilabel(controlsGrid, 'Text', 'Cold flow rate (mL/min)');
            app.ColdFlowField = uieditfield(controlsGrid, 'numeric', ...
                'Limits', [0 Inf], 'Value', 600, 'ValueChangedFcn', @(src, evt) app.updatePrediction());

            % Membrane pore size
            uilabel(controlsGrid, 'Text', 'Pore size (µm)');
            app.PoreSizeField = uieditfield(controlsGrid, 'numeric', ...
                'Limits', [0 Inf], 'Value', 0.22, 'ValueChangedFcn', @(src, evt) app.updatePrediction());

            % Membrane thickness
            uilabel(controlsGrid, 'Text', 'Thickness (µm)');
            app.ThicknessField = uieditfield(controlsGrid, 'numeric', ...
                'Limits', [0 Inf], 'Value', 200, 'ValueChangedFcn', @(src, evt) app.updatePrediction());

            % Buttons
            app.PredictButton = uibutton(controlsGrid, 'Text', 'Predict now', ...
                'ButtonPushedFcn', @(src, evt) app.updatePrediction());
            app.PredictButton.Layout.Column = [1 2];

            app.ReloadButton = uibutton(controlsGrid, 'Text', 'Reload & retrain', ...
                'ButtonPushedFcn', @(src, evt) app.onReload());
            app.ReloadButton.Layout.Column = [1 2];

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
