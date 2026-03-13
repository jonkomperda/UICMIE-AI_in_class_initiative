function fourbar_ga_app
% FOURBAR_GA_APP Interactive four-bar path synthesis with a custom GA.
% Run this file, click points on the target-path axes, tune the GA values,
% and press "Run Genetic Algorithm" to synthesize and animate a linkage.

rng("shuffle");

state = struct();
state.userPoints = zeros(0, 2);
state.targetPoints = zeros(0, 2);
state.bestResult = [];
state.bestHistory = [];
state.isSelecting = false;
state.isRunning = false;
state.stopRequested = false;
state.previewFrame = 1;
state.view.lockAxes = false;
state.view.pathLimits = [];
state.view.linkageLimits = [];
state.view.autoZoomFactor = 1.5;

buildUi();
loadExamplePath();
logMessage("App ready. Click Select Path Points to sketch a new trajectory.");

    function buildUi()
        figColor = [0.95 0.96 0.98];
        panelColor = [0.92 0.93 0.96];

        state.fig = figure( ...
            "Name", "Four-Bar Linkage Genetic Algorithm Synthesizer", ...
            "NumberTitle", "off", ...
            "Color", figColor, ...
            "MenuBar", "none", ...
            "ToolBar", "none", ...
            "DefaultUicontrolForegroundColor", [0 0 0], ...
            "DefaultAxesXColor", [0 0 0], ...
            "DefaultAxesYColor", [0 0 0], ...
            "DefaultTextColor", [0 0 0], ...
            "Position", [80 50 1450 840], ...
            "WindowButtonDownFcn", @onFigureClick, ...
            "CloseRequestFcn", @onCloseFigure);

        state.controlsPanel = uipanel( ...
            "Parent", state.fig, ...
            "Title", "Controls", ...
            "FontSize", 11, ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor, ...
            "Position", [0.015 0.03 0.24 0.94]);

        state.pathAxes = axes( ...
            "Parent", state.fig, ...
            "Units", "normalized", ...
            "Position", [0.29 0.57 0.31 0.37], ...
            "Box", "on");
        title(state.pathAxes, "Target Path");
        xlabel(state.pathAxes, "X");
        ylabel(state.pathAxes, "Y");
        axis(state.pathAxes, "equal");
        grid(state.pathAxes, "on");
        styleAxes(state.pathAxes);

        state.historyAxes = axes( ...
            "Parent", state.fig, ...
            "Units", "normalized", ...
            "Position", [0.65 0.57 0.31 0.37], ...
            "Box", "on");
        title(state.historyAxes, "Fitness History");
        xlabel(state.historyAxes, "Generation");
        ylabel(state.historyAxes, "RMS Error");
        grid(state.historyAxes, "on");
        styleAxes(state.historyAxes);

        state.linkageAxes = axes( ...
            "Parent", state.fig, ...
            "Units", "normalized", ...
            "Position", [0.29 0.08 0.67 0.38], ...
            "Box", "on");
        title(state.linkageAxes, "Mechanism Evolution");
        xlabel(state.linkageAxes, "X");
        ylabel(state.linkageAxes, "Y");
        axis(state.linkageAxes, "equal");
        grid(state.linkageAxes, "on");
        styleAxes(state.linkageAxes);

        y = 0.93;
        dy = 0.038;
        editHeight = 0.038;
        labelHeight = 0.024;
        leftX = 0.05;
        editX = 0.62;
        editW = 0.28;

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.05 y 0.88 0.04], ...
            "String", "Path Definition", ...
            "FontWeight", "bold", ...
            "FontSize", 11, ...
            "HorizontalAlignment", "left", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor);
        y = y - 0.06;

        state.controls.exampleMenu = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "popupmenu", ...
            "Units", "normalized", ...
            "Position", [0.05 y 0.58 editHeight], ...
            "String", {"Lemniscate", "Rounded Rectangle", "Heart"}, ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", "white");

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.66 y 0.24 editHeight], ...
            "String", "Load", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "Callback", @onLoadExample);
        y = y - (dy + 0.005);

        state.controls.selectButton = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "togglebutton", ...
            "Units", "normalized", ...
            "Position", [0.05 y 0.39 editHeight], ...
            "String", "Select Path Points", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "Callback", @onSelectModeChanged);

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.47 y 0.20 editHeight], ...
            "String", "Undo", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "Callback", @onUndoPoint);

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.69 y 0.21 editHeight], ...
            "String", "Clear", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "Callback", @onClearPoints);
        y = y - (dy + 0.008);

        state.controls.closedPath = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "checkbox", ...
            "Units", "normalized", ...
            "Position", [0.05 y 0.42 editHeight], ...
            "String", "Closed Path", ...
            "Value", 0, ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor, ...
            "Callback", @onPathSettingChanged);

        state.controls.pathSamples = createLabeledEdit("Path Samples", "24", y, leftX, editX, editW, labelHeight, editHeight);
        y = y - (dy + 0.008);

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.05 y 0.24 editHeight], ...
            "String", "Fit Axes", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "Callback", @onFitAxes);

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.32 y 0.34 editHeight], ...
            "String", "Zoom Out 50%", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "Callback", @onZoomOutAxes);

        state.controls.lockAxesButton = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "togglebutton", ...
            "Units", "normalized", ...
            "Position", [0.69 y 0.21 editHeight], ...
            "String", "Lock View", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "Callback", @onLockAxesChanged);
        y = y - (dy + 0.008);

        state.controls.animationCycles = createLabeledEdit("Animation Cycles", "2", y, leftX, editX, editW, labelHeight, editHeight);
        y = y - (dy + 0.008);

        state.controls.framePause = createLabeledEdit("Frame Pause (s)", "0.03", y, leftX, editX, editW, labelHeight, editHeight);
        y = y - 0.065;

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.05 y 0.88 0.04], ...
            "String", "Genetic Algorithm", ...
            "FontWeight", "bold", ...
            "FontSize", 11, ...
            "HorizontalAlignment", "left", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor);
        y = y - 0.06;

        state.controls.populationSize = createLabeledEdit("Population", "140", y, leftX, editX, editW, labelHeight, editHeight);
        y = y - (dy + 0.008);
        state.controls.generations = createLabeledEdit("Generations", "220", y, leftX, editX, editW, labelHeight, editHeight);
        y = y - (dy + 0.008);
        state.controls.mutationRate = createLabeledEdit("Mutation Rate", "0.18", y, leftX, editX, editW, labelHeight, editHeight);
        y = y - (dy + 0.008);
        state.controls.crossoverRate = createLabeledEdit("Crossover Rate", "0.85", y, leftX, editX, editW, labelHeight, editHeight);
        y = y - (dy + 0.008);
        state.controls.eliteCount = createLabeledEdit("Elite Count", "6", y, leftX, editX, editW, labelHeight, editHeight);
        y = y - (dy + 0.008);
        state.controls.tournamentSize = createLabeledEdit("Tournament", "4", y, leftX, editX, editW, labelHeight, editHeight);
        state.controls.runButton = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.05 0.14 0.56 0.05], ...
            "String", "Run Genetic Algorithm", ...
            "FontWeight", "bold", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "Callback", @onRunGa);

        state.controls.stopButton = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.64 0.14 0.26 0.05], ...
            "String", "Stop", ...
            "Enable", "off", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "Callback", @onStopRun);

        state.controls.statusLabel = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.05 0.105 0.85 0.028], ...
            "String", "Status: idle", ...
            "HorizontalAlignment", "left", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor);

        state.controls.logBox = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "listbox", ...
            "Units", "normalized", ...
            "Position", [0.05 0.02 0.87 0.075], ...
            "String", {"Event log"}, ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", "white", ...
            "Max", 2, ...
            "Min", 0);

        refreshTargetData();
        refreshPlots();
    end

    function editHandle = createLabeledEdit(labelText, defaultValue, yPos, lx, ex, ew, lh, eh)
        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [lx yPos + 0.012 0.5 lh], ...
            "String", labelText, ...
            "HorizontalAlignment", "left", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", state.controlsPanel.BackgroundColor);

        editHandle = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "edit", ...
            "Units", "normalized", ...
            "Position", [ex yPos ew eh], ...
            "String", defaultValue, ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", "white");
    end

    function styleAxes(axHandle)
        set(axHandle, "XColor", [0 0 0], "YColor", [0 0 0], "GridColor", [0.35 0.35 0.35]);
        set(get(axHandle, "Title"), "Color", [0 0 0], "FontWeight", "bold");
        set(get(axHandle, "XLabel"), "Color", [0 0 0]);
        set(get(axHandle, "YLabel"), "Color", [0 0 0]);
    end

    function onFigureClick(~, ~)
        if ~state.isSelecting || ~isgraphics(state.pathAxes)
            return;
        end

        clickedObj = hittest(state.fig);
        clickedAxes = ancestor(clickedObj, "axes");
        if isempty(clickedAxes) || clickedAxes ~= state.pathAxes
            return;
        end

        point = get(state.pathAxes, "CurrentPoint");
        state.userPoints(end + 1, :) = point(1, 1:2);
        refreshTargetData();
        refreshPlots();
        logMessage(sprintf("Added point %d at (%.3f, %.3f).", size(state.userPoints, 1), point(1, 1), point(1, 2)));
    end

    function onSelectModeChanged(src, ~)
        state.isSelecting = logical(get(src, "Value"));
        if state.isSelecting
            set(state.fig, "Pointer", "crosshair");
            logMessage("Point selection enabled. Click inside the Target Path axes.");
        else
            set(state.fig, "Pointer", "arrow");
            logMessage("Point selection disabled.");
        end
    end

    function onUndoPoint(~, ~)
        if isempty(state.userPoints)
            logMessage("No points to undo.");
            return;
        end

        state.userPoints(end, :) = [];
        refreshTargetData();
        refreshPlots();
        logMessage("Removed the last path point.");
    end

    function onClearPoints(~, ~)
        state.userPoints = zeros(0, 2);
        state.targetPoints = zeros(0, 2);
        state.bestResult = [];
        state.bestHistory = [];
        refreshPlots();
        refreshHistoryPlot();
        logMessage("Cleared all path points.");
    end

    function onLoadExample(~, ~)
        loadExamplePath();
    end

    function onPathSettingChanged(~, ~)
        refreshTargetData();
        refreshPlots();
    end

    function onFitAxes(~, ~)
        state.view.lockAxes = false;
        state.view.pathLimits = [];
        state.view.linkageLimits = [];
        if isfield(state.controls, "lockAxesButton") && isgraphics(state.controls.lockAxesButton)
            set(state.controls.lockAxesButton, "Value", 0);
            set(state.controls.lockAxesButton, "String", "Lock View");
        end
        refreshPlots();
        logMessage("Axes reset to automatic fit with extra margin.");
    end

    function onZoomOutAxes(~, ~)
        zoomAxis(state.pathAxes, 1.5);
        zoomAxis(state.linkageAxes, 1.5);
        if state.view.lockAxes
            captureCurrentAxesLimits();
        end
        logMessage("Zoomed the path and mechanism axes out by 50%.");
    end

    function onLockAxesChanged(src, ~)
        state.view.lockAxes = logical(get(src, "Value"));
        if state.view.lockAxes
            set(src, "String", "Unlock View");
            captureCurrentAxesLimits();
            logMessage("Locked the current path and mechanism view extents.");
        else
            set(src, "String", "Lock View");
            state.view.pathLimits = [];
            state.view.linkageLimits = [];
            refreshPlots();
            logMessage("Unlocked the axes and returned to automatic fitting.");
        end
    end

    function loadExamplePath()
        menuValue = get(state.controls.exampleMenu, "Value");
        sampleCount = max(12, readInteger(state.controls.pathSamples, 24));

        switch menuValue
            case 1
                t = linspace(0, 2 * pi, sampleCount).';
                x = 2.2 * cos(t) ./ (1 + sin(t).^2);
                y = 1.5 * sin(t) .* cos(t) ./ (1 + sin(t).^2);
                state.userPoints = [x, y];
                set(state.controls.closedPath, "Value", 1);
                shapeName = "lemniscate";
            case 2
                rectanglePoints = [ ...
                    -2.5 -1.2;
                    -0.8 -1.2;
                     0.8 -1.2;
                     2.5 -1.2;
                     2.5 -0.2;
                     2.5  0.8;
                     2.5  1.2;
                     0.8  1.2;
                    -0.8  1.2;
                    -2.5  1.2;
                    -2.5  0.3;
                    -2.5 -0.7];
                state.userPoints = rectanglePoints;
                set(state.controls.closedPath, "Value", 1);
                shapeName = "rounded-rectangle style";
            otherwise
                t = linspace(0, 2 * pi, sampleCount).';
                x = 1.7 * (16 * sin(t).^3) / 17;
                y = (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) / 9;
                state.userPoints = [x, y];
                set(state.controls.closedPath, "Value", 1);
                shapeName = "heart";
        end

        refreshTargetData();
        state.bestResult = [];
        state.bestHistory = [];
        refreshPlots();
        refreshHistoryPlot();
        logMessage(sprintf("Loaded %s example path.", shapeName));
    end

    function refreshTargetData()
        if size(state.userPoints, 1) < 2
            state.targetPoints = state.userPoints;
            return;
        end

        sampleCount = max(8, readInteger(state.controls.pathSamples, 24));
        isClosed = logical(get(state.controls.closedPath, "Value"));
        state.targetPoints = resamplePath(state.userPoints, sampleCount, isClosed);
    end

    function pts = resamplePath(points, sampleCount, isClosed)
        pts = points;
        if size(points, 1) < 2
            return;
        end

        curve = points;
        if isClosed
            if norm(points(1, :) - points(end, :)) > 1e-9
                curve = [points; points(1, :)];
            end
        end

        deltas = diff(curve, 1, 1);
        segmentLengths = sqrt(sum(deltas.^2, 2));
        cumulative = [0; cumsum(segmentLengths)];
        totalLength = cumulative(end);

        if totalLength < 1e-9
            pts = repmat(points(1, :), sampleCount, 1);
            return;
        end

        if isClosed
            query = linspace(0, totalLength, sampleCount + 1).';
            query(end) = [];
        else
            query = linspace(0, totalLength, sampleCount).';
        end

        pts = [ ...
            interp1(cumulative, curve(:, 1), query, "linear"), ...
            interp1(cumulative, curve(:, 2), query, "linear")];
    end

    function onRunGa(~, ~)
        if state.isRunning
            return;
        end

        refreshTargetData();
        if size(state.targetPoints, 1) < 4
            errordlg("Please define at least four path points before running the optimizer.", "Need More Points");
            return;
        end

        options = readGaOptions();
        if isempty(options)
            return;
        end

        state.stopRequested = false;
        state.isRunning = true;
        state.bestResult = [];
        state.bestHistory = [];
        setBusyState(true);

        try
            logMessage("Initializing population and starting optimization.");
            [bestResult, history] = runGeneticAlgorithm(options);
            state.bestResult = bestResult;
            state.bestHistory = history;
            refreshPlots();
            refreshHistoryPlot();

            if ~isempty(bestResult)
                logMessage(sprintf("Best RMS error: %.5f", bestResult.rmsError));
                if bestResult.penalty > 0
                    logMessage(sprintf("Residual penalty term: %.5f", bestResult.penalty));
                end
                logMessage(sprintf("Lengths [ground crank coupler rocker] = [%.4f %.4f %.4f %.4f]", ...
                    bestResult.params.groundLength, ...
                    bestResult.params.crankLength, ...
                    bestResult.params.couplerLength, ...
                    bestResult.params.rockerLength));
                playFinalAnimation(bestResult, options);
            elseif state.stopRequested
                logMessage("Optimization stopped before a valid solution was finalized.");
            end
        catch err
            logMessage(sprintf("Run failed: %s", err.message));
            errordlg(err.message, "Run Failed");
        end

        state.isRunning = false;
        setBusyState(false);
    end

    function onStopRun(~, ~)
        if state.isRunning
            state.stopRequested = true;
            logMessage("Stop requested. Finishing the current generation.");
        end
    end

    function options = readGaOptions()
        options = struct();
        options.populationSize = readInteger(state.controls.populationSize, 140);
        options.generations = readInteger(state.controls.generations, 220);
        options.mutationRate = readDouble(state.controls.mutationRate, 0.18);
        options.crossoverRate = readDouble(state.controls.crossoverRate, 0.85);
        options.eliteCount = readInteger(state.controls.eliteCount, 6);
        options.tournamentSize = readInteger(state.controls.tournamentSize, 4);
        options.previewEvery = 5;
        options.stallLimit = 60;
        options.pathSamples = readInteger(state.controls.pathSamples, 24);
        options.animationCycles = readInteger(state.controls.animationCycles, 2);
        options.framePause = readDouble(state.controls.framePause, 0.03);
        options.closedPath = logical(get(state.controls.closedPath, "Value"));
        options.targetPoints = state.targetPoints;

        if options.populationSize < 10 || options.generations < 1 || options.eliteCount < 1
            errordlg("Population, generations, and elite count must be positive.", "Invalid Settings");
            options = [];
            return;
        end

        if options.eliteCount >= options.populationSize
            errordlg("Elite count must be smaller than the population size.", "Invalid Settings");
            options = [];
            return;
        end

        if options.tournamentSize < 2
            errordlg("Tournament size must be at least 2.", "Invalid Settings");
            options = [];
            return;
        end

        if options.mutationRate < 0 || options.mutationRate > 1 || options.crossoverRate < 0 || options.crossoverRate > 1
            errordlg("Mutation and crossover rates must be between 0 and 1.", "Invalid Settings");
            options = [];
            return;
        end
    end

    function [bestResult, history] = runGeneticAlgorithm(options)
        target = options.targetPoints;
        bounds = buildBounds(target);
        sigma = 0.12 * (bounds.upper - bounds.lower);
        population = initializePopulation(options.populationSize, bounds, target);
        scores = zeros(options.populationSize, 1);
        results = cell(options.populationSize, 1);

        for idx = 1:options.populationSize
            results{idx} = evaluateCandidate(population(idx, :), target);
            scores(idx) = results{idx}.fitness;
        end

        bestResult = [];
        bestScore = inf;
        history = nan(options.generations, 1);
        stallCounter = 0;

        for generation = 1:options.generations
            if state.stopRequested
                break;
            end

            [scores, order] = sort(scores, "ascend");
            population = population(order, :);
            results = results(order);
            history(generation) = scores(1);

            if scores(1) + 1e-9 < bestScore
                bestScore = scores(1);
                bestResult = results{1};
                stallCounter = 0;
            else
                stallCounter = stallCounter + 1;
            end

            state.bestHistory = history(1:generation);
            state.bestResult = bestResult;

            shouldPreview = generation == 1 || generation == options.generations || mod(generation, max(1, options.previewEvery)) == 0;
            if shouldPreview && ~isempty(bestResult)
                setStatus(sprintf("running generation %d / %d", generation, options.generations));
                refreshPlots();
                refreshHistoryPlot();
                logMessage(sprintf("Generation %d best RMS error: %.5f", generation, bestResult.rmsError));
                drawnow;
            else
                drawnow limitrate;
            end

            if stallCounter >= options.stallLimit
                logMessage(sprintf("Stopping early after %d stalled generations.", options.stallLimit));
                history = history(1:generation);
                break;
            end

            nextPopulation = zeros(size(population));
            nextPopulation(1:options.eliteCount, :) = population(1:options.eliteCount, :);

            insertIndex = options.eliteCount + 1;
            while insertIndex <= options.populationSize
                parentA = population(tournamentSelect(scores, options.tournamentSize), :);
                parentB = population(tournamentSelect(scores, options.tournamentSize), :);

                childA = parentA;
                childB = parentB;
                if rand < options.crossoverRate
                    [childA, childB] = blendCrossover(parentA, parentB, bounds);
                end

                childA = mutateIndividual(childA, bounds, sigma, options.mutationRate);
                childB = mutateIndividual(childB, bounds, sigma, options.mutationRate);

                nextPopulation(insertIndex, :) = childA;
                if insertIndex + 1 <= options.populationSize
                    nextPopulation(insertIndex + 1, :) = childB;
                end
                insertIndex = insertIndex + 2;
            end

            population = nextPopulation;
            for idx = 1:options.populationSize
                results{idx} = evaluateCandidate(population(idx, :), target);
                scores(idx) = results{idx}.fitness;
            end

            if generation == options.generations
                history = history(1:generation);
            end
        end

        if isempty(bestResult) && ~isempty(results)
            [~, bestIndex] = min(scores);
            bestResult = results{bestIndex};
        end

        history = history(isfinite(history));
        setStatus("idle");
    end

    function bounds = buildBounds(target)
        minXY = min(target, [], 1);
        maxXY = max(target, [], 1);
        center = mean(target, 1);
        span = max(maxXY - minXY);
        span = max(span, 1);
        margin = 3.5 * span;
        lenMin = 0.08 * span;
        lenMax = 4.0 * span;

        bounds.lower = [ ...
            center(1) - margin, ... % ground x
            center(2) - margin, ... % ground y
            0, ...                  % ground angle
            lenMin, ...             % ground length
            lenMin, ...             % crank
            lenMin, ...             % coupler
            lenMin, ...             % rocker
            -3.0 * span, ...        % coupler point x
            -3.0 * span, ...        % coupler point y
            0, ...                  % input start angle
            deg2rad(20), ...        % input sweep
            0, ...                  % branch selector
            0];                     % direction selector

        bounds.upper = [ ...
            center(1) + margin, ...
            center(2) + margin, ...
            2 * pi, ...
            lenMax, ...
            lenMax, ...
            lenMax, ...
            lenMax, ...
            3.0 * span, ...
            3.0 * span, ...
            2 * pi, ...
            2 * pi, ...
            1, ...
            1];
    end

    function population = initializePopulation(populationSize, bounds, target)
        variableCount = numel(bounds.lower);
        population = rand(populationSize, variableCount) .* (bounds.upper - bounds.lower) + bounds.lower;

        center = mean(target, 1);
        span = max(max(target) - min(target));
        span = max(span, 1);

        seedCount = min(12, populationSize);
        for idx = 1:seedCount
            seed = population(idx, :);
            seed(1:2) = center + 0.35 * span * randn(1, 2);
            seed(3) = mod((idx - 1) / seedCount * 2 * pi, 2 * pi);
            seed(4) = 1.6 * span * (0.65 + 0.2 * rand);
            seed(5) = 0.55 * span * (0.8 + 0.5 * rand);
            seed(6) = 1.15 * span * (0.8 + 0.5 * rand);
            seed(7) = 1.1 * span * (0.8 + 0.5 * rand);
            seed(8:9) = 0.3 * span * randn(1, 2);
            seed(10) = 2 * pi * rand;
            seed(11) = deg2rad(90 + 220 * rand);
            seed(12) = rand > 0.5;
            seed(13) = rand > 0.5;
            population(idx, :) = clampToBounds(seed, bounds);
        end
    end

    function result = evaluateCandidate(candidate, target)
        params = decodeCandidate(candidate, size(target, 1));
        result = struct();
        result.fitness = inf;
        result.rmsError = inf;
        result.penalty = inf;
        result.params = params;
        result.path = nan(size(target));
        result.A = nan(size(target));
        result.B = nan(size(target));
        result.C = nan(size(target));
        result.D = nan(size(target));
        result.isValid = false;

        inputAngles = params.inputAngles(:);
        sampleCount = numel(inputAngles);
        A = repmat(params.groundA, sampleCount, 1);
        D = repmat(params.groundD, sampleCount, 1);
        B = nan(sampleCount, 2);
        C = nan(sampleCount, 2);
        P = nan(sampleCount, 2);

        invalidCount = 0;
        branchSign = params.branchSign;
        for idx = 1:sampleCount
            B(idx, :) = params.groundA + params.crankLength * [cos(inputAngles(idx)), sin(inputAngles(idx))];
            [pointC, isValid] = circleIntersection(B(idx, :), params.couplerLength, params.groundD, params.rockerLength, branchSign);
            if ~isValid
                invalidCount = invalidCount + 1;
                continue;
            end

            C(idx, :) = pointC;
            direction = pointC - B(idx, :);
            directionNorm = norm(direction);
            if directionNorm < 1e-10
                invalidCount = invalidCount + 1;
                continue;
            end

            ux = direction / directionNorm;
            uy = [-ux(2), ux(1)];
            P(idx, :) = B(idx, :) + params.couplerPoint(1) * ux + params.couplerPoint(2) * uy;
        end

        penalties = 0;
        if invalidCount > 0
            penalties = penalties + 1000 * invalidCount;
        end

        if any(any(isnan(P)))
            penalties = penalties + 500 * sum(any(isnan(P), 2));
        end

        validMask = ~any(isnan(P), 2);
        if nnz(validMask) < max(4, floor(0.8 * sampleCount))
            penalties = penalties + 5000;
        end

        if any(validMask)
            distances = vecnorm(P(validMask, :) - target(validMask, :), 2, 2);
            fitError = sqrt(mean(distances .^ 2));
        else
            fitError = 1e6;
        end

        if nnz(validMask) >= 3
            smoothness = diff(P(validMask, :), 2, 1);
            penalties = penalties + 0.02 * mean(vecnorm(smoothness, 2, 2));
        end

        result.fitness = fitError + penalties;
        result.rmsError = fitError;
        result.penalty = penalties;
        result.path = P;
        result.A = A;
        result.B = B;
        result.C = C;
        result.D = D;
        result.isValid = invalidCount == 0 && all(validMask);
    end

    function params = decodeCandidate(candidate, sampleCount)
        params = struct();
        params.groundA = candidate(1:2);
        params.groundAngle = candidate(3);
        params.groundLength = candidate(4);
        params.crankLength = candidate(5);
        params.couplerLength = candidate(6);
        params.rockerLength = candidate(7);
        params.couplerPoint = candidate(8:9);
        params.thetaStart = candidate(10);
        params.thetaSpan = candidate(11);
        params.branchSign = 2 * (candidate(12) >= 0.5) - 1;
        params.directionSign = 2 * (candidate(13) >= 0.5) - 1;
        params.groundD = params.groundA + params.groundLength * [cos(params.groundAngle), sin(params.groundAngle)];
        params.inputAngles = params.thetaStart + params.directionSign * linspace(0, params.thetaSpan, sampleCount);
    end

    function [intersectionPoint, isValid] = circleIntersection(center1, radius1, center2, radius2, branchSign)
        delta = center2 - center1;
        distance = norm(delta);
        isValid = true;
        intersectionPoint = [nan, nan];

        if distance < 1e-12
            isValid = false;
            return;
        end

        if distance > radius1 + radius2 || distance < abs(radius1 - radius2)
            isValid = false;
            return;
        end

        ex = delta / distance;
        ey = [-ex(2), ex(1)];
        x = (radius1^2 - radius2^2 + distance^2) / (2 * distance);
        ySquared = radius1^2 - x^2;
        if ySquared < -1e-10
            isValid = false;
            return;
        end

        y = sqrt(max(0, ySquared));
        intersectionPoint = center1 + x * ex + branchSign * y * ey;
    end

    function index = tournamentSelect(scores, tournamentSize)
        contestantCount = numel(scores);
        picks = randi(contestantCount, tournamentSize, 1);
        [~, localBest] = min(scores(picks));
        index = picks(localBest);
    end

    function [childA, childB] = blendCrossover(parentA, parentB, bounds)
        alpha = -0.15 + 1.3 * rand(1, numel(parentA));
        childA = alpha .* parentA + (1 - alpha) .* parentB;
        childB = alpha .* parentB + (1 - alpha) .* parentA;
        childA = clampToBounds(childA, bounds);
        childB = clampToBounds(childB, bounds);
    end

    function individual = mutateIndividual(individual, bounds, sigma, mutationRate)
        for idx = 1:numel(individual)
            if rand < mutationRate
                if rand < 0.25
                    individual(idx) = bounds.lower(idx) + rand * (bounds.upper(idx) - bounds.lower(idx));
                else
                    individual(idx) = individual(idx) + sigma(idx) * randn;
                end
            end
        end
        individual = clampToBounds(individual, bounds);
    end

    function values = clampToBounds(values, bounds)
        values = min(max(values, bounds.lower), bounds.upper);
    end

    function refreshPlots()
        refreshTargetPlot();
        refreshLinkagePlot();
    end

    function refreshTargetPlot()
        cla(state.pathAxes);
        hold(state.pathAxes, "on");

        if ~isempty(state.userPoints)
            plot(state.pathAxes, state.userPoints(:, 1), state.userPoints(:, 2), "k.-", "LineWidth", 1.2, "MarkerSize", 14, "DisplayName", "Clicked points");
            if logical(get(state.controls.closedPath, "Value")) && size(state.userPoints, 1) > 2
                plot(state.pathAxes, [state.userPoints(end, 1), state.userPoints(1, 1)], ...
                    [state.userPoints(end, 2), state.userPoints(1, 2)], "k-", "LineWidth", 1.0, "HandleVisibility", "off");
            end
        end

        if ~isempty(state.targetPoints)
            plot(state.pathAxes, state.targetPoints(:, 1), state.targetPoints(:, 2), "-", ...
                "Color", [0.12 0.45 0.85], "LineWidth", 2.0, "DisplayName", "Resampled target");
            scatter(state.pathAxes, state.targetPoints(:, 1), state.targetPoints(:, 2), 36, ...
                "MarkerFaceColor", [0.12 0.45 0.85], "MarkerEdgeColor", "white", "DisplayName", "Target samples");
        end

        if ~isempty(state.bestResult) && isfield(state.bestResult, "path")
            validMask = ~any(isnan(state.bestResult.path), 2);
            if any(validMask)
                plot(state.pathAxes, state.bestResult.path(validMask, 1), state.bestResult.path(validMask, 2), "--", ...
                    "Color", [0.92 0.38 0.15], "LineWidth", 2.0, "DisplayName", "Best synthesized path");
            end
        end

        if ~isempty(findobj(state.pathAxes, "-property", "DisplayName"))
            legend(state.pathAxes, "Location", "best");
        else
            legend(state.pathAxes, "off");
        end
        axis(state.pathAxes, "equal");
        grid(state.pathAxes, "on");
        applyAxesView(state.pathAxes, collectVisiblePoints(), "path");
        hold(state.pathAxes, "off");
    end

    function refreshLinkagePlot()
        cla(state.linkageAxes);
        hold(state.linkageAxes, "on");

        if ~isempty(state.targetPoints)
            plot(state.linkageAxes, state.targetPoints(:, 1), state.targetPoints(:, 2), "-", ...
                "Color", [0.75 0.82 0.94], "LineWidth", 2.0, "DisplayName", "Target");
        end

        if isempty(state.bestResult)
            title(state.linkageAxes, "Mechanism Evolution");
            axis(state.linkageAxes, "equal");
            grid(state.linkageAxes, "on");
            applyAxesView(state.linkageAxes, collectVisiblePoints(), "linkage");
            legend(state.linkageAxes, "off");
            hold(state.linkageAxes, "off");
            return;
        end

        result = state.bestResult;
        validMask = ~any(isnan(result.path), 2);
        if any(validMask)
            plot(state.linkageAxes, result.path(validMask, 1), result.path(validMask, 2), "-", ...
                "Color", [0.92 0.38 0.15], "LineWidth", 2.1, "DisplayName", "Best path");
        end

        sampleCount = size(result.path, 1);
        state.previewFrame = mod(state.previewFrame, max(sampleCount, 1)) + 1;
        frameIndex = min(state.previewFrame, sampleCount);
        frameIndex = chooseValidFrame(validMask, frameIndex);

        if frameIndex > 0
            drawMechanismFrame(result, frameIndex, false);
        end

        title(state.linkageAxes, sprintf("Mechanism Evolution | RMS error %.5f", result.rmsError));
        axis(state.linkageAxes, "equal");
        grid(state.linkageAxes, "on");
        applyAxesView(state.linkageAxes, collectVisiblePoints(result), "linkage");
        if ~isempty(findobj(state.linkageAxes, "-property", "DisplayName"))
            legend(state.linkageAxes, "Location", "bestoutside");
        else
            legend(state.linkageAxes, "off");
        end
        hold(state.linkageAxes, "off");
    end

    function index = chooseValidFrame(validMask, preferred)
        index = 0;
        if ~any(validMask)
            return;
        end

        if validMask(preferred)
            index = preferred;
            return;
        end

        firstValid = find(validMask, 1, "first");
        index = firstValid;
    end

    function drawMechanismFrame(result, frameIndex, emphasize)
        if nargin < 3
            emphasize = false;
        end

        A = result.A(frameIndex, :);
        B = result.B(frameIndex, :);
        C = result.C(frameIndex, :);
        D = result.D(frameIndex, :);
        P = result.path(frameIndex, :);

        if any(isnan([A, B, C, D, P]))
            return;
        end

        if emphasize
            linkWidth = 3.0;
            pointSize = 90;
        else
            linkWidth = 2.4;
            pointSize = 70;
        end

        plot(state.linkageAxes, [A(1), B(1)], [A(2), B(2)], "-", "Color", [0.1 0.55 0.2], "LineWidth", linkWidth, "DisplayName", "Crank");
        plot(state.linkageAxes, [B(1), C(1)], [B(2), C(2)], "-", "Color", [0.95 0.65 0.1], "LineWidth", linkWidth, "DisplayName", "Coupler");
        plot(state.linkageAxes, [C(1), D(1)], [C(2), D(2)], "-", "Color", [0.45 0.2 0.7], "LineWidth", linkWidth, "DisplayName", "Rocker");
        plot(state.linkageAxes, [A(1), D(1)], [A(2), D(2)], "-", "Color", [0.2 0.2 0.2], "LineWidth", linkWidth, "DisplayName", "Ground");
        plot(state.linkageAxes, [B(1), P(1)], [B(2), P(2)], "--", "Color", [0.65 0.4 0.3], "LineWidth", 1.2, "DisplayName", "Coupler point arm");

        scatter(state.linkageAxes, [A(1), B(1), C(1), D(1)], [A(2), B(2), C(2), D(2)], pointSize, ...
            "filled", "MarkerFaceColor", [0.16 0.16 0.16], "MarkerEdgeColor", "white", "DisplayName", "Joints");
        scatter(state.linkageAxes, P(1), P(2), pointSize + 10, "filled", ...
            "MarkerFaceColor", [0.85 0.1 0.1], "MarkerEdgeColor", "white", "DisplayName", "Tracing point");
    end

    function pts = collectVisiblePoints(varargin)
        pts = zeros(0, 2);
        if ~isempty(state.userPoints)
            pts = [pts; state.userPoints];
        end
        if ~isempty(state.targetPoints)
            pts = [pts; state.targetPoints];
        end
        if nargin >= 1
            result = varargin{1};
            if isfield(result, "path")
                validMask = ~any(isnan(result.path), 2);
                pts = [pts; result.path(validMask, :)];
                validB = ~any(isnan(result.B), 2);
                validC = ~any(isnan(result.C), 2);
                pts = [pts; result.A(validB, :); result.B(validB, :); result.C(validC, :); result.D(validB, :)];
            end
        elseif ~isempty(state.bestResult)
            result = state.bestResult;
            validMask = ~any(isnan(result.path), 2);
            pts = [pts; result.path(validMask, :)];
            validB = ~any(isnan(result.B), 2);
            validC = ~any(isnan(result.C), 2);
            pts = [pts; result.A(validB, :); result.B(validB, :); result.C(validC, :); result.D(validB, :)];
        end
    end

    function applyAxesView(axHandle, points, axisKey)
        if state.view.lockAxes
            limits = [];
            switch axisKey
                case "path"
                    limits = state.view.pathLimits;
                case "linkage"
                    limits = state.view.linkageLimits;
            end

            if ~isempty(limits)
                xlim(axHandle, limits(1, :));
                ylim(axHandle, limits(2, :));
                return;
            end
        end

        padAxes(axHandle, points, state.view.autoZoomFactor);
    end

    function padAxes(axHandle, points, zoomFactor)
        if nargin < 3
            zoomFactor = state.view.autoZoomFactor;
        end

        if isempty(points)
            xlim(axHandle, [-7.5, 7.5]);
            ylim(axHandle, [-7.5, 7.5]);
            return;
        end

        minXY = min(points, [], 1);
        maxXY = max(points, [], 1);
        span = max(maxXY - minXY);
        span = max(span, 1);
        padding = 0.18 * span;
        xRange = [minXY(1) - padding, maxXY(1) + padding];
        yRange = [minXY(2) - padding, maxXY(2) + padding];

        centerX = mean(xRange);
        centerY = mean(yRange);
        halfWidth = max(diff(xRange) * zoomFactor / 2, 0.5);
        halfHeight = max(diff(yRange) * zoomFactor / 2, 0.5);
        xlim(axHandle, [centerX - halfWidth, centerX + halfWidth]);
        ylim(axHandle, [centerY - halfHeight, centerY + halfHeight]);
    end

    function zoomAxis(axHandle, factor)
        currentX = xlim(axHandle);
        currentY = ylim(axHandle);
        centerX = mean(currentX);
        centerY = mean(currentY);
        halfWidth = diff(currentX) * factor / 2;
        halfHeight = diff(currentY) * factor / 2;
        xlim(axHandle, [centerX - halfWidth, centerX + halfWidth]);
        ylim(axHandle, [centerY - halfHeight, centerY + halfHeight]);
    end

    function captureCurrentAxesLimits()
        state.view.pathLimits = [xlim(state.pathAxes); ylim(state.pathAxes)];
        state.view.linkageLimits = [xlim(state.linkageAxes); ylim(state.linkageAxes)];
    end

    function refreshHistoryPlot()
        cla(state.historyAxes);
        hold(state.historyAxes, "on");
        if ~isempty(state.bestHistory)
            plot(state.historyAxes, 1:numel(state.bestHistory), state.bestHistory, "-", ...
                "Color", [0.1 0.45 0.75], "LineWidth", 2.0);
        end
        title(state.historyAxes, "Fitness History");
        xlabel(state.historyAxes, "Generation");
        ylabel(state.historyAxes, "RMS Error + Penalty");
        grid(state.historyAxes, "on");
        hold(state.historyAxes, "off");
    end

    function playFinalAnimation(result, options)
        if isempty(result)
            return;
        end

        validMask = ~any(isnan(result.path), 2);
        validFrames = find(validMask);
        if isempty(validFrames)
            logMessage("No valid frames were available for the final animation.");
            return;
        end

        pauseTime = max(0, options.framePause);
        cycleCount = max(1, options.animationCycles);
        logMessage("Playing final linkage animation.");

        for cycle = 1:cycleCount
            for idx = 1:numel(validFrames)
                if state.stopRequested
                    break;
                end
                frameIndex = validFrames(idx);
                cla(state.linkageAxes);
                hold(state.linkageAxes, "on");
                plot(state.linkageAxes, state.targetPoints(:, 1), state.targetPoints(:, 2), "-", ...
                    "Color", [0.75 0.82 0.94], "LineWidth", 2.0, "DisplayName", "Target");
                plot(state.linkageAxes, result.path(validFrames, 1), result.path(validFrames, 2), "-", ...
                    "Color", [0.92 0.38 0.15], "LineWidth", 2.1, "DisplayName", "Synthesized path");
                drawMechanismFrame(result, frameIndex, true);
                title(state.linkageAxes, sprintf("Final Animation | cycle %d / %d | frame %d / %d", ...
                    cycle, cycleCount, idx, numel(validFrames)));
                axis(state.linkageAxes, "equal");
                grid(state.linkageAxes, "on");
                applyAxesView(state.linkageAxes, collectVisiblePoints(result), "linkage");
                if ~isempty(findobj(state.linkageAxes, "-property", "DisplayName"))
                    legend(state.linkageAxes, "Location", "bestoutside");
                else
                    legend(state.linkageAxes, "off");
                end
                hold(state.linkageAxes, "off");
                drawnow;
                pause(pauseTime);
            end
            if state.stopRequested
                break;
            end
        end

        state.stopRequested = false;
        refreshLinkagePlot();
    end

    function setBusyState(isBusy)
        if isBusy
            set(state.controls.runButton, "Enable", "off");
            set(state.controls.stopButton, "Enable", "on");
            setStatus("running");
        else
            set(state.controls.runButton, "Enable", "on");
            set(state.controls.stopButton, "Enable", "off");
            setStatus("idle");
        end
    end

    function setStatus(statusText)
        if isfield(state, "controls") && isfield(state.controls, "statusLabel") && isgraphics(state.controls.statusLabel)
            set(state.controls.statusLabel, "String", sprintf("Status: %s", statusText));
            drawnow limitrate;
        end
    end

    function value = readInteger(handleObj, defaultValue)
        value = round(str2double(get(handleObj, "String")));
        if ~isfinite(value)
            value = defaultValue;
            set(handleObj, "String", num2str(defaultValue));
        end
    end

    function value = readDouble(handleObj, defaultValue)
        value = str2double(get(handleObj, "String"));
        if ~isfinite(value)
            value = defaultValue;
            set(handleObj, "String", num2str(defaultValue));
        end
    end

    function logMessage(message)
        timestamp = datestr(now, "HH:MM:SS");
        newEntry = sprintf("[%s] %s", timestamp, message);
        if isfield(state, "controls") && isfield(state.controls, "logBox") && isgraphics(state.controls.logBox)
            existing = get(state.controls.logBox, "String");
            if ischar(existing)
                existing = cellstr(existing);
            end
            existing = [existing; {newEntry}];
            set(state.controls.logBox, "String", existing, "Value", numel(existing));
            drawnow limitrate;
        else
            fprintf("%s\n", newEntry);
        end
    end

    function onCloseFigure(~, ~)
        state.stopRequested = true;
        delete(state.fig);
    end
end
