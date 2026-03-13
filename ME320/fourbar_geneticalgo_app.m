function fourbar_ga_app
% FOURBAR_GA_APP Interactive four-bar path synthesis with a custom GA.
% Run this file, click points on the target-path axes, tune the GA values,
% and press "Run Genetic Algorithm" to synthesize and animate a linkage.
%
% High-level workflow:
% 1. Build the GUI and initialize the app state.
% 2. Let the user define a target path, either by clicking points or by
%    loading a built-in example shape.
% 3. Read the solver settings from the GUI.
% 4. Run a custom genetic algorithm that searches mechanism parameters.
% 5. Preview the evolving mechanism and animate the final best result.
%
% Design note:
% The app stores all mutable runtime data in the nested `state` structure.
% GUI handles live under `state.controls`, while the current target path,
% best mechanism, animation view, and run state also live in `state`.

rng("shuffle");

% Runtime state that changes while the user interacts with the app.
state = struct();
state.userPoints = zeros(0, 2);      % Raw points clicked or loaded by the user.
state.targetPoints = zeros(0, 2);    % Resampled target path actually used by the solver.
state.bestResult = [];               % Best mechanism found so far.
state.bestHistory = [];              % Fitness history shown on the history plot.
state.isSelecting = false;           % Whether mouse clicks should add target-path points.
state.isRunning = false;             % Whether a GA solve is currently in progress.
state.stopRequested = false;         % Cooperative stop flag checked inside the GA loop.
state.previewFrame = 1;              % Current frame index for preview animation cycling.
state.view.lockAxes = false;         % Whether the current axis limits are frozen.
state.view.pathLimits = [];          % Stored limits for the target-path axes.
state.view.linkageLimits = [];       % Stored limits for the mechanism axes.
state.view.autoZoomFactor = 1.5;     % Default automatic "zoomed out" display factor.
state.exampleLibrary = getExampleLibrary();  % Built-in target shapes.
state.mechanismChoices = getMechanismChoices(); % Mechanism families available in the GUI.

buildUi();
loadExamplePath();
logMessage("App ready. Click Select Path Points to sketch a new trajectory.");

    % Build the entire GUI: figure, axes, control panel, and footer text.
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

        workerDefault = num2str(defaultWorkerCount());
        exampleNames = {state.exampleLibrary.name};
        mechanismLabels = {state.mechanismChoices.label};
        y = 0.93;
        dy = 0.034;
        editHeight = 0.034;
        labelHeight = 0.022;
        leftX = 0.05;
        editX = 0.62;
        editW = 0.28;

        % Path-definition controls: example shapes, point selection, and
        % path sampling options.
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
            "String", exampleNames, ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", "white", ...
            "TooltipString", "Built-in targets ranging from simple ellipses and rounded shapes to more challenging symbolic loops.");

        % View controls: fit, zoom, pan, and axis locking for both plots.
        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.66 y 0.24 editHeight], ...
            "String", "Load", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Load the selected built-in target path into the canvas.", ...
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
            "TooltipString", "Toggle manual point selection, then click inside the Target Path axes.", ...
            "Callback", @onSelectModeChanged);

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.47 y 0.20 editHeight], ...
            "String", "Undo", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Remove the last path point you added.", ...
            "Callback", @onUndoPoint);

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.69 y 0.21 editHeight], ...
            "String", "Clear", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Clear the path, history, and best mechanism preview.", ...
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
            "TooltipString", "Enable for loops such as hearts, rectangles, and symbols so cyclic alignment is used.", ...
            "Callback", @onPathSettingChanged);

        state.controls.pathSamples = createLabeledEdit("Path Samples", "36", y, leftX, editX, editW, labelHeight, editHeight, ...
            "Number of target samples. More points improve fidelity but increase solve time. Recommended: 28-48.");
        y = y - (dy + 0.008);

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.05 y + 0.012 0.34 labelHeight], ...
            "String", "Mechanism Mode", ...
            "HorizontalAlignment", "left", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor, ...
            "TooltipString", "Choose the mechanism family. Standard 4-bar is the default/simple option. The slider-enhanced and multi-slider variants add tracing freedom, and the advanced 5-bar/6-bar modes add slider-based tracer assemblies for harder shapes.");

        state.controls.mechanismMode = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "popupmenu", ...
            "Units", "normalized", ...
            "Position", [0.38 y 0.52 editHeight], ...
            "String", mechanismLabels, ...
            "Value", 1, ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", "white", ...
            "TooltipString", "Choose the mechanism family. Standard 4-bar is the default/simple option. The slider-enhanced and multi-slider variants add tracing freedom, and the advanced 5-bar/6-bar modes add slider-based tracer assemblies for harder shapes.", ...
            "Callback", @onMechanismModeChanged);
        y = y - (dy + 0.008);

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.05 y 0.20 editHeight], ...
            "String", "Fit Axes", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Auto-fit the target and mechanism plots with extra margin.", ...
            "Callback", @onFitAxes);

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.266 y 0.20 editHeight], ...
            "String", "Zoom In", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Shrink the current plot limits to zoom in. The new view is locked automatically.", ...
            "Callback", @onZoomInAxes);

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.482 y 0.20 editHeight], ...
            "String", "Zoom Out", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Expand the current plot limits by 50 percent. The new view is locked automatically.", ...
            "Callback", @onZoomOutAxes);

        state.controls.lockAxesButton = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "togglebutton", ...
            "Units", "normalized", ...
            "Position", [0.698 y 0.20 editHeight], ...
            "String", "Lock View", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Freeze the current path and mechanism axis extents while the solver updates.", ...
            "Callback", @onLockAxesChanged);
        y = y - (dy + 0.006);

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.05 y 0.20 editHeight], ...
            "String", "Pan Left", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Shift both plots left while keeping the current zoom. The new view is locked automatically.", ...
            "Callback", @(~, ~) onPanAxes(-0.18, 0, "left"));

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.266 y 0.20 editHeight], ...
            "String", "Pan Right", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Shift both plots right while keeping the current zoom. The new view is locked automatically.", ...
            "Callback", @(~, ~) onPanAxes(0.18, 0, "right"));

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.482 y 0.20 editHeight], ...
            "String", "Pan Up", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Shift both plots upward while keeping the current zoom. The new view is locked automatically.", ...
            "Callback", @(~, ~) onPanAxes(0, 0.18, "up"));

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.698 y 0.20 editHeight], ...
            "String", "Pan Down", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Shift both plots downward while keeping the current zoom. The new view is locked automatically.", ...
            "Callback", @(~, ~) onPanAxes(0, -0.18, "down"));
        y = y - (dy + 0.006);

        % Animation and tracing-point controls. The tracing-point checkbox
        % switches between a fixed tracer and a tracer that may move along
        % the mechanism over the cycle.
        state.controls.movingTracePoint = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "checkbox", ...
            "Units", "normalized", ...
            "Position", [0.05 y 0.48 editHeight], ...
            "String", "Moving Trace Point", ...
            "Value", 1, ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor, ...
            "TooltipString", "Enable a movable tracing point that can shift along joints or couplers over the cycle. Turn this off for a fixed tracing point relative to the mechanism.", ...
            "Callback", @onTracePointModeChanged);

        % Genetic-algorithm tuning controls.
        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.56 y + 0.012 0.20 labelHeight], ...
            "String", "Anim. Cycles", ...
            "HorizontalAlignment", "left", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor, ...
            "TooltipString", "How many times the final mechanism animation repeats. Recommended: 1-3.");

        state.controls.animationCycles = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "edit", ...
            "Units", "normalized", ...
            "Position", [0.79 y 0.11 editHeight], ...
            "String", "2", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", "white", ...
            "TooltipString", "How many times the final mechanism animation repeats. Recommended: 1-3.");
        y = y - (dy + 0.008);

        state.controls.framePause = createLabeledEdit("Frame Pause (s)", "0.03", y, leftX, editX, editW, labelHeight, editHeight, ...
            "Delay between final animation frames. Smaller values play faster. Recommended: 0.01-0.05.");
        y = y - 0.040;

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

        state.controls.populationSize = createLabeledEdit("Population", "320", y, leftX, editX, editW, labelHeight, editHeight, ...
            "Candidates per generation. Higher explores more broadly but takes longer. Recommended: 200-400.");
        y = y - (dy + 0.008);
        state.controls.generations = createLabeledEdit("Generations", "650", y, leftX, editX, editW, labelHeight, editHeight, ...
            "Maximum generations per attempt. Difficult paths often need 400-800.");
        y = y - (dy + 0.008);
        state.controls.mutationRate = createLabeledEdit("Mutation Rate", "0.28", y, leftX, editX, editW, labelHeight, editHeight, ...
            "Per-gene mutation probability. Raise this when runs stall. Recommended: 0.18-0.32.");
        y = y - (dy + 0.008);
        state.controls.crossoverRate = createLabeledEdit("Crossover Rate", "0.90", y, leftX, editX, editW, labelHeight, editHeight, ...
            "Chance that two parents are blended. Recommended: 0.80-0.95.");
        y = y - (dy + 0.008);
        state.controls.eliteCount = createLabeledEdit("Elite Count", "12", y, leftX, editX, editW, labelHeight, editHeight, ...
            "Top candidates copied unchanged into the next generation. Recommended: 6-15.");
        y = y - (dy + 0.008);
        state.controls.tournamentSize = createLabeledEdit("Tournament", "4", y, leftX, editX, editW, labelHeight, editHeight, ...
            "Selection pressure for parent choice. Recommended: 3-5.");
        y = y - (dy + 0.008);

        state.controls.workerLabel = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.05 y + 0.012 0.18 labelHeight], ...
            "String", "Workers", ...
            "HorizontalAlignment", "left", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor, ...
            "TooltipString", "Parallel workers used for fitness evaluation. Use 1 to disable parallelism. Recommended: 2-8.");

        state.controls.numWorkers = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "edit", ...
            "Units", "normalized", ...
            "Position", [0.23 y 0.12 editHeight], ...
            "String", workerDefault, ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", "white", ...
            "TooltipString", "Parallel workers used for fitness evaluation. Use 1 to disable parallelism. Recommended: 2-8.");

        state.controls.targetRmseLabel = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.42 y + 0.012 0.26 labelHeight], ...
            "String", "Target RMSE", ...
            "HorizontalAlignment", "left", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor, ...
            "TooltipString", "Desired RMS error goal. 0.05-0.10 is ambitious, 0.10-0.20 is more realistic.");

        state.controls.targetRmse = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "edit", ...
            "Units", "normalized", ...
            "Position", [0.71 y 0.19 editHeight], ...
            "String", "0.10", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", "white", ...
            "TooltipString", "Desired RMS error goal. 0.05-0.10 is ambitious, 0.10-0.20 is more realistic.");

        % Run / stop / status / log area.
        state.controls.runButton = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.05 0.102 0.56 0.042], ...
            "String", "Run Genetic Algorithm", ...
            "FontWeight", "bold", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Start the solve. If the target RMSE is not met, the app can offer stronger settings.", ...
            "Callback", @onRunGa);

        state.controls.stopButton = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.64 0.102 0.26 0.042], ...
            "String", "Stop", ...
            "Enable", "off", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Request a stop after the current generation finishes.", ...
            "Callback", @onStopRun);

        state.controls.statusLabel = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.05 0.073 0.85 0.022], ...
            "String", "Status: idle", ...
            "HorizontalAlignment", "left", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor);

        state.controls.logBox = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "listbox", ...
            "Units", "normalized", ...
            "Position", [0.05 0.020 0.87 0.045], ...
            "String", {"Event log"}, ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", "white", ...
            "Max", 2, ...
            "Min", 0);

        % Footer attribution shown outside the controls panel.
        state.controls.copyrightLabel = uicontrol( ...
            "Parent", state.fig, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.76 0.005 0.22 0.025], ...
            "String", char([169 ' Prof. Jon Komperda, University of Illinois Chicago, 2026']), ...
            "HorizontalAlignment", "right", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", figColor);

        refreshTargetData();
        refreshPlots();
    end

    % Small helper used throughout the control panel to place a text label
    % and a matching editable numeric/text field on the same row.
    function editHandle = createLabeledEdit(labelText, defaultValue, yPos, lx, ex, ew, lh, eh, tooltipText)
        if nargin < 9
            tooltipText = "";
        end

        uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [lx yPos + 0.012 0.5 lh], ...
            "String", labelText, ...
            "HorizontalAlignment", "left", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", state.controlsPanel.BackgroundColor, ...
            "TooltipString", tooltipText);

        editHandle = uicontrol( ...
            "Parent", state.controlsPanel, ...
            "Style", "edit", ...
            "Units", "normalized", ...
            "Position", [ex yPos ew eh], ...
            "String", defaultValue, ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", "white", ...
            "TooltipString", tooltipText);
    end

    % Apply consistent visual styling to each axes.
    function styleAxes(axHandle)
        set(axHandle, "XColor", [0 0 0], "YColor", [0 0 0], "GridColor", [0.35 0.35 0.35]);
        set(get(axHandle, "Title"), "Color", [0 0 0], "FontWeight", "bold");
        set(get(axHandle, "XLabel"), "Color", [0 0 0]);
        set(get(axHandle, "YLabel"), "Color", [0 0 0]);
    end

    % Choose a reasonable default number of workers for parallel
    % evaluation, while capping the requested value at 8.
    function workerCount = defaultWorkerCount()
        workerCount = 1;
        try
            workerCount = max(1, min(8, floor(double(feature("numcores")))));
        catch
            workerCount = 1;
        end
    end

    % List of built-in target trajectories available in the example menu.
    function library = getExampleLibrary()
        library = struct( ...
            'name', {'Ellipse', 'Circle', 'Rounded Rectangle', 'Rounded Square', 'Half Moon', 'Heart', 'Lemniscate', 'Teardrop', 'Bean', 'S Curve'}, ...
            'id', {'ellipse', 'circle', 'rounded_rectangle', 'rounded_square', 'half_moon', 'heart', 'lemniscate', 'teardrop', 'bean', 's_curve'}, ...
            'closed', {true, true, true, true, true, true, true, true, true, false});
    end

    % Mechanism families shown in the GUI popup. Each mode corresponds to
    % a different chromosome layout and kinematic evaluator.
    function choices = getMechanismChoices()
        choices = struct( ...
            'id', {'standard_fourbar', 'slider_fourbar', 'advanced_fourbar', 'fivebar', 'advanced_fivebar', 'sixbar', 'advanced_sixbar'}, ...
            'label', {'4-Bar Standard', '4-Bar Slider-Enhanced', '4-Bar Multi-Slider', '5-Bar Parallel', '5-Bar Slider-Enhanced', '6-Bar Stephenson', '6-Bar Slider-Enhanced'});
    end

    % Read the currently selected mechanism mode from the GUI popup.
    function mode = getSelectedMechanismMode()
        value = 1;
        if isfield(state, 'controls') && isfield(state.controls, 'mechanismMode') && isgraphics(state.controls.mechanismMode)
            value = get(state.controls.mechanismMode, "Value");
        end
        value = max(1, min(numel(state.mechanismChoices), value));
        mode = state.mechanismChoices(value).id;
    end

    % Convert an internal mechanism ID into a human-readable label.
    function label = mechanismModeToLabel(mode)
        label = '4-Bar Standard';
        if strcmp(mode, 'fourbar')
            label = '4-Bar Slider-Enhanced';
            return;
        end
        idx = 1;
        while idx <= numel(state.mechanismChoices)
            if strcmp(state.mechanismChoices(idx).id, mode)
                label = state.mechanismChoices(idx).label;
                return;
            end
            idx = idx + 1;
        end
    end

    % Rough complexity estimate used to scale GA defaults, restart limits,
    % and stall guidance by mechanism family.
    function factor = mechanismComplexityFactor(mode)
        switch mode
            case 'standard_fourbar'
                factor = 1.00;
            case {'slider_fourbar', 'fourbar'}
                factor = 1.15;
            case {'advanced_fourbar', 'fivebar', 'sixbar'}
                factor = 1.35;
            otherwise
                factor = 1.60;
        end
    end

    % Start or resize MATLAB's parallel pool, when available, so the
    % population can be evaluated candidate-by-candidate in parallel.
    function [useParallel, message] = prepareParallelPool(requestedWorkers)
        useParallel = false;
        if requestedWorkers <= 1
            message = "Parallel evaluation disabled. Using 1 worker.";
            return;
        end

        if isempty(ver("parallel")) || ~license("test", "Distrib_Computing_Toolbox")
            message = "Parallel Computing Toolbox not available. Falling back to serial evaluation.";
            return;
        end

        try
            pool = gcp("nocreate");
            if isempty(pool)
                parpool("local", requestedWorkers);
            elseif pool.NumWorkers ~= requestedWorkers
                delete(pool);
                parpool("local", requestedWorkers);
            end
            useParallel = true;
            message = sprintf("Parallel evaluation enabled on %d worker(s).", requestedWorkers);
        catch err
            message = sprintf("Could not start a %d-worker pool (%s). Falling back to serial evaluation.", ...
                requestedWorkers, err.message);
        end
    end

    % Concatenate history traces across multiple attempts, separating them
    % with NaN so the plot shows visible breaks between attempts.
    function combinedHistory = appendHistory(existingHistory, newHistory)
        if isempty(existingHistory)
            combinedHistory = newHistory(:);
        elseif isempty(newHistory)
            combinedHistory = existingHistory(:);
        else
            combinedHistory = [existingHistory(:); nan; newHistory(:)];
        end
    end

    % Push an options struct back into the GUI after automatic strengthening
    % or user-edited retry settings.
    function syncUiWithOptions(options)
        set(state.controls.populationSize, "String", num2str(options.populationSize));
        set(state.controls.generations, "String", num2str(options.generations));
        set(state.controls.mutationRate, "String", sprintf('%.3f', options.mutationRate));
        set(state.controls.crossoverRate, "String", sprintf('%.3f', options.crossoverRate));
        set(state.controls.eliteCount, "String", num2str(options.eliteCount));
        set(state.controls.tournamentSize, "String", num2str(options.tournamentSize));
        set(state.controls.pathSamples, "String", num2str(options.pathSamples));
        set(state.controls.targetRmse, "String", sprintf('%.3f', options.targetRmse));
        if isfield(options, 'allowMovingTracePoint') && isfield(state.controls, 'movingTracePoint') && isgraphics(state.controls.movingTracePoint)
            set(state.controls.movingTracePoint, "Value", double(options.allowMovingTracePoint));
        end
    end

    % Post a concise recommendation into the UI log when the search stalls.
    function showStallGuidance(bestResult, options)
        complexity = mechanismComplexityFactor(options.mechanismMode);
        setStatus("stalled");
        if isempty(bestResult)
            logMessage("The search stalled before finding a valid mechanism. Try raising population, generations, or mutation rate.");
        else
            logMessage(sprintf("The search stalled near RMS %.4f.", bestResult.rmsError));
        end
        suggestedPop = round([240, 420] * complexity);
        suggestedGen = round([520, 900] * complexity);
        suggestedSamples = round([32, 48] + 4 * (complexity - 1));
        logMessage(sprintf("Suggestions: population %d-%d, generations %d-%d, mutation %.2f-%.2f, workers 2-8, and %d-%d path samples for this mechanism.", ...
            suggestedPop(1), suggestedPop(2), ...
            suggestedGen(1), suggestedGen(2), ...
            max(0.20, options.mutationRate), min(0.48, options.mutationRate + 0.12), ...
            suggestedSamples(1), suggestedSamples(2)));
    end

    % Ask the user whether to stop, continue once more, or continue with
    % stronger GA settings after a run stalls or misses the target RMSE.
    function choice = promptForContinuation(bestResult, options, runInfo)
        if isempty(bestResult)
            prompt = sprintf(['The run ended with no valid mechanism.\n\n' ...
                'Try stronger settings with more population, generations, and mutation?\n' ...
                'You can review and edit the proposed GA settings before continuing.']);
        elseif runInfo.stalled
            prompt = sprintf(['The search stalled at RMS %.4f, above the target %.4f.\n\n' ...
                'Do you want to continue with stronger settings?\n' ...
                'You can review and edit the proposed GA settings before continuing.'], ...
                bestResult.rmsError, options.targetRmse);
        else
            prompt = sprintf(['Best RMS is %.4f, above the target %.4f.\n\n' ...
                'Do you want to continue searching?\n' ...
                'You can review and edit stronger GA settings if you choose that option.'], ...
                bestResult.rmsError, options.targetRmse);
        end

        response = questdlg(prompt, "Continue Search?", ...
            "Continue with stronger settings", "Continue once more", "Stop", ...
            "Continue with stronger settings");
        if isempty(response)
            choice = "Stop";
        else
            choice = string(response);
        end
    end

    % Heuristic retry policy: increase population/generation budget,
    % mutation rate, and sample count for a stronger follow-up attempt.
    function options = strengthenOptions(options)
        complexity = mechanismComplexityFactor(options.mechanismMode);
        options.populationSize = min(1400, max(options.populationSize + round(50 * complexity), round((1.28 + 0.08 * complexity) * options.populationSize)));
        options.generations = min(2400, max(options.generations + round(140 * complexity), round((1.28 + 0.08 * complexity) * options.generations)));
        options.mutationRate = min(0.55, options.mutationRate + 0.03 + 0.015 * complexity);
        options.eliteCount = min(max(8, round(0.05 * options.populationSize)), max(10, floor(0.10 * options.populationSize)));
        options.tournamentSize = min(6, max(3, options.tournamentSize));
        options.pathSamples = min(72, max(options.pathSamples, round(34 + 6 * complexity)));
        options.targetPoints = resamplePath(state.userPoints, options.pathSamples, options.closedPath);
        state.targetPoints = options.targetPoints;
        options.maxRestarts = max(options.maxRestarts, 2 + ceil(complexity));
        options.stallLimit = max(90, round((0.18 + 0.03 * complexity) * options.generations));
    end

    % Compact one-line summary of the GA settings used for a run attempt.
    function logGaSettingsSummary(prefix, options)
        traceModeLabel = "moving";
        if isfield(options, 'allowMovingTracePoint') && ~options.allowMovingTracePoint
            traceModeLabel = "fixed";
        end
        logMessage(sprintf('%s | mode=%s | trace=%s | population=%d generations=%d mutation=%.3f crossover=%.3f elite=%d tournament=%d', ...
            prefix, ...
            mechanismModeToLabel(options.mechanismMode), ...
            traceModeLabel, ...
            options.populationSize, ...
            options.generations, ...
            options.mutationRate, ...
            options.crossoverRate, ...
            options.eliteCount, ...
            options.tournamentSize));
    end

    % Log a mechanism-specific summary of the best design parameters found.
    function logBestMechanismSummary(result)
        if isempty(result) || ~isfield(result, 'params')
            return;
        end

        if isfield(result.params, 'tracePointMode')
            logMessage(sprintf("Tracing point mode used: %s", char(result.params.tracePointMode)));
        end

        switch result.mechanismMode
            case 'standard_fourbar'
                logMessage(sprintf("4-bar lengths [ground crank coupler rocker] = [%.4f %.4f %.4f %.4f]", ...
                    result.params.groundLength, ...
                    result.params.crankLength, ...
                    result.params.couplerLength, ...
                    result.params.rockerLength));
                logMessage(sprintf("4-bar coupler point [blend normalOffset blendAmp offsetAmp] = [%.4f %.4f %.4f %.4f]", ...
                    result.params.traceBlend, ...
                    result.params.connectorOffset, ...
                    result.params.traceBlendAmp, ...
                    result.params.offsetAmp));
            case 'advanced_fourbar'
                logMessage(sprintf("Advanced 4-bar lengths [ground crank coupler rocker] = [%.4f %.4f %.4f %.4f]", ...
                    result.params.groundLength, ...
                    result.params.crankLength, ...
                    result.params.couplerLength, ...
                    result.params.rockerLength));
                logMessage(sprintf("Advanced 4-bar slider amps [B1 B2 B3 C1 C2 C3] = [%.4f %.4f %.4f %.4f %.4f %.4f]", ...
                    result.params.sliderAmpB1, ...
                    result.params.sliderAmpB2, ...
                    result.params.sliderAmpB3, ...
                    result.params.sliderAmpC1, ...
                    result.params.sliderAmpC2, ...
                    result.params.sliderAmpC3));
            case {'slider_fourbar', 'fourbar'}
                logMessage(sprintf("Slider 4-bar lengths [ground crank coupler rocker] = [%.4f %.4f %.4f %.4f]", ...
                    result.params.groundLength, ...
                    result.params.crankLength, ...
                    result.params.couplerLength, ...
                    result.params.rockerLength));
                logMessage(sprintf("Slider 4-bar tracer [blend offset blendAmp offsetAmp] = [%.4f %.4f %.4f %.4f]", ...
                    result.params.traceBlend, ...
                    result.params.connectorOffset, ...
                    result.params.traceBlendAmp, ...
                    result.params.offsetAmp));
            case 'advanced_fivebar'
                logMessage(sprintf("Advanced 5-bar lengths [ground left crank left distal right crank right distal] = [%.4f %.4f %.4f %.4f %.4f]", ...
                    result.params.groundLength, ...
                    result.params.leftCrankLength, ...
                    result.params.leftDistalLength, ...
                    result.params.rightCrankLength, ...
                    result.params.rightDistalLength));
                logMessage(sprintf("Advanced 5-bar sliders [leftAmp rightAmp bridgeLong bridgeNormal] = [%.4f %.4f %.4f %.4f]", ...
                    result.params.leftSliderAmp, ...
                    result.params.rightSliderAmp, ...
                    result.params.bridgeLongAmp, ...
                    result.params.bridgeNormalAmp));
            case 'fivebar'
                logMessage(sprintf("5-bar lengths [ground left crank left distal right crank right distal] = [%.4f %.4f %.4f %.4f %.4f]", ...
                    result.params.groundLength, ...
                    result.params.leftCrankLength, ...
                    result.params.leftDistalLength, ...
                    result.params.rightCrankLength, ...
                    result.params.rightDistalLength));
                logMessage(sprintf("5-bar coupling [phase ratio blend normalOffset blendAmp offsetAmp] = [%.4f %.4f %.4f %.4f %.4f %.4f]", ...
                    result.params.phaseOffset, ...
                    result.params.crankRatio, ...
                    result.params.traceBlend, ...
                    result.params.connectorOffset, ...
                    result.params.traceBlendAmp, ...
                    result.params.offsetAmp));
            case 'sixbar'
                logMessage(sprintf("6-bar base lengths [ground crank coupler rocker] = [%.4f %.4f %.4f %.4f]", ...
                    result.params.groundLength, ...
                    result.params.crankLength, ...
                    result.params.couplerLength, ...
                    result.params.rockerLength));
                logMessage(sprintf("6-bar auxiliary [couplerLink rockerLink couplerBlend groundBlend] = [%.4f %.4f %.4f %.4f]", ...
                    result.params.auxCouplerLength, ...
                    result.params.auxRockerLength, ...
                    result.params.couplerBlend, ...
                    result.params.auxGroundBlend));
                logMessage(sprintf("6-bar offsets [coupler ground trace] = [%.4f %.4f %.4f]", ...
                    result.params.couplerOffset, ...
                    result.params.auxGroundOffset, ...
                    result.params.traceOffset));
                logMessage(sprintf("6-bar trace motion [blend blendAmp offsetAmp] = [%.4f %.4f %.4f]", ...
                    result.params.traceBlend, ...
                    result.params.traceBlendAmp, ...
                    result.params.traceOffsetAmp));
            case 'advanced_sixbar'
                logMessage(sprintf("Advanced 6-bar base lengths [ground crank coupler rocker] = [%.4f %.4f %.4f %.4f]", ...
                    result.params.groundLength, ...
                    result.params.crankLength, ...
                    result.params.couplerLength, ...
                    result.params.rockerLength));
                logMessage(sprintf("Advanced 6-bar sliders [JAmp FAmp bridgeLong bridgeNormal] = [%.4f %.4f %.4f %.4f]", ...
                    result.params.sliderJAmp, ...
                    result.params.sliderFAmp, ...
                    result.params.bridgeLongAmp, ...
                    result.params.bridgeNormalAmp));
            otherwise
                logMessage(sprintf("Lengths [ground crank coupler rocker] = [%.4f %.4f %.4f %.4f]", ...
                    result.params.groundLength, ...
                    result.params.crankLength, ...
                    result.params.couplerLength, ...
                    result.params.rockerLength));
                logMessage(sprintf("Slider amplitudes [B1 B2 C1 C2] = [%.4f %.4f %.4f %.4f]", ...
                    result.params.sliderAmpB1, ...
                    result.params.sliderAmpB2, ...
                    result.params.sliderAmpC1, ...
                    result.params.sliderAmpC2));
        end
    end

    % Modal dialog that lets the user edit the automatically proposed
    % stronger GA settings before the next retry begins.
    function [options, didAccept] = customizeStrongerSettings(proposedOptions, bestResult, runInfo)
        options = normalizeRetryOptions(proposedOptions);
        didAccept = false;

        dialogColor = [0.95 0.96 0.98];
        panelColor = [0.92 0.93 0.96];
        workingOptions = options;
        editHandles = struct();
        wasApplied = false;

        dlg = dialog( ...
            "Name", "Adjust Stronger GA Settings", ...
            "WindowStyle", "modal", ...
            "Color", dialogColor, ...
            "Position", [220 140 620 500], ...
            "CloseRequestFcn", @onCancelDialog);

        if isempty(bestResult)
            summaryText = 'The previous run stalled before finding a valid linkage. Review the stronger settings below, then click Use These Settings to continue.';
        elseif runInfo.stalled
            summaryText = sprintf(['The search stalled at RMSE %.4f (target %.4f).\n' ...
                'Stronger settings are preloaded below, and you can change any field before the next attempt.'], ...
                bestResult.rmsError, proposedOptions.targetRmse);
        else
            summaryText = sprintf(['Best RMSE so far is %.4f (target %.4f).\n' ...
                'Stronger settings are preloaded below, and you can change any field before the next attempt.'], ...
                bestResult.rmsError, proposedOptions.targetRmse);
        end

        uicontrol( ...
            "Parent", dlg, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.06 0.84 0.88 0.12], ...
            "String", summaryText, ...
            "HorizontalAlignment", "left", ...
            "FontWeight", "bold", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", dialogColor);

        uipanel( ...
            "Parent", dlg, ...
            "Units", "normalized", ...
            "Position", [0.05 0.22 0.90 0.56], ...
            "Title", "Retry Settings", ...
            "FontSize", 10, ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor);

        uicontrol( ...
            "Parent", dlg, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.09 0.73 0.24 0.035], ...
            "String", "Parameter", ...
            "HorizontalAlignment", "left", ...
            "FontWeight", "bold", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor);

        uicontrol( ...
            "Parent", dlg, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.45 0.73 0.16 0.035], ...
            "String", "Value", ...
            "HorizontalAlignment", "center", ...
            "FontWeight", "bold", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", panelColor);

        uicontrol( ...
            "Parent", dlg, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.64 0.73 0.13 0.04], ...
            "String", "Decrease All", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Reduce all stronger GA settings by one step.", ...
            "Callback", @(~, ~) adjustAllFields(-1));

        uicontrol( ...
            "Parent", dlg, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.79 0.73 0.11 0.04], ...
            "String", "Increase All", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.8 0.8 0.8], ...
            "TooltipString", "Increase all stronger GA settings by one step.", ...
            "Callback", @(~, ~) adjustAllFields(1));

        addSettingRow('populationSize', 'Population', 'Candidates per generation. Stronger retries often use 300-700.', 0.65);
        addSettingRow('generations', 'Generations', 'Maximum generations in the retry. Stronger retries often use 650-1500.', 0.58);
        addSettingRow('mutationRate', 'Mutation Rate', 'Per-gene mutation probability. Raise this when the search is trapped. Stronger retries often use 0.22-0.40.', 0.51);
        addSettingRow('crossoverRate', 'Crossover Rate', 'Chance that parents blend. A common range is 0.82-0.95.', 0.44);
        addSettingRow('eliteCount', 'Elite Count', 'Top survivors copied directly into the next generation. Typical range is 8-20.', 0.37);
        addSettingRow('tournamentSize', 'Tournament', 'Selection pressure for parent choice. Typical range is 3-5.', 0.30);

        uicontrol( ...
            "Parent", dlg, ...
            "Style", "text", ...
            "Units", "normalized", ...
            "Position", [0.07 0.15 0.86 0.055], ...
            "String", ['Recommended strong-retry ranges: population 300-700, generations 650-1500, mutation 0.22-0.40, ' ...
                       'crossover 0.82-0.95, elite 8-20, tournament 3-5.'], ...
            "HorizontalAlignment", "left", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", dialogColor);

        uicontrol( ...
            "Parent", dlg, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.28 0.06 0.24 0.07], ...
            "String", "Use These Settings", ...
            "FontWeight", "bold", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.76 0.83 0.76], ...
            "Callback", @onApplyDialog);

        uicontrol( ...
            "Parent", dlg, ...
            "Style", "pushbutton", ...
            "Units", "normalized", ...
            "Position", [0.56 0.06 0.16 0.07], ...
            "String", "Cancel", ...
            "ForegroundColor", [0 0 0], ...
            "BackgroundColor", [0.84 0.80 0.80], ...
            "Callback", @onCancelDialog);

        uiwait(dlg);

        if wasApplied
            options = normalizeRetryOptions(workingOptions);
            options.targetPoints = resamplePath(state.userPoints, options.pathSamples, options.closedPath);
            state.targetPoints = options.targetPoints;
            options.stallLimit = max(80, round(0.22 * options.generations));
            didAccept = true;
        else
            options = proposedOptions;
        end

        function addSettingRow(fieldName, labelText, tooltipText, yPos)
            fieldKey = char(fieldName);

            uicontrol( ...
                "Parent", dlg, ...
                "Style", "text", ...
                "Units", "normalized", ...
                "Position", [0.09 yPos 0.27 0.045], ...
                "String", labelText, ...
                "HorizontalAlignment", "left", ...
                "ForegroundColor", [0 0 0], ...
                "BackgroundColor", panelColor, ...
                "TooltipString", tooltipText);

            uicontrol( ...
                "Parent", dlg, ...
                "Style", "pushbutton", ...
                "Units", "normalized", ...
                "Position", [0.36 yPos 0.08 0.045], ...
                "String", "-", ...
                "FontWeight", "bold", ...
                "ForegroundColor", [0 0 0], ...
                "BackgroundColor", [0.8 0.8 0.8], ...
                "TooltipString", tooltipText, ...
                "Callback", @(~, ~) adjustField(fieldKey, -1));

            editHandles.(fieldKey) = uicontrol( ...
                "Parent", dlg, ...
                "Style", "edit", ...
                "Units", "normalized", ...
                "Position", [0.46 yPos 0.18 0.045], ...
                "String", formatRetryValue(fieldKey, workingOptions.(fieldKey)), ...
                "ForegroundColor", [0 0 0], ...
                "BackgroundColor", "white", ...
                "TooltipString", tooltipText, ...
                "Callback", @(src, ~) onEditField(src, fieldKey));

            uicontrol( ...
                "Parent", dlg, ...
                "Style", "pushbutton", ...
                "Units", "normalized", ...
                "Position", [0.66 yPos 0.08 0.045], ...
                "String", "+", ...
                "FontWeight", "bold", ...
                "ForegroundColor", [0 0 0], ...
                "BackgroundColor", [0.8 0.8 0.8], ...
                "TooltipString", tooltipText, ...
                "Callback", @(~, ~) adjustField(fieldKey, 1));
        end

        function adjustAllFields(direction)
            pullValuesFromDialog();
            fields = {'populationSize', 'generations', 'mutationRate', 'crossoverRate', 'eliteCount', 'tournamentSize'};
            idx = 1;
            while idx <= numel(fields)
                workingOptions = applyFieldStep(workingOptions, fields{idx}, direction);
                idx = idx + 1;
            end
            workingOptions = normalizeRetryOptions(workingOptions);
            refreshDialogValues();
        end

        function adjustField(fieldName, direction)
            pullValuesFromDialog();
            workingOptions = applyFieldStep(workingOptions, fieldName, direction);
            workingOptions = normalizeRetryOptions(workingOptions);
            refreshDialogValues();
        end

        function onEditField(src, fieldName)
            rawValue = str2double(get(src, "String"));
            if isnan(rawValue)
                set(src, "String", formatRetryValue(fieldName, workingOptions.(fieldName)));
                return;
            end
            workingOptions.(fieldName) = rawValue;
            workingOptions = normalizeRetryOptions(workingOptions);
            refreshDialogValues();
        end

        function pullValuesFromDialog()
            fieldNames = fieldnames(editHandles);
            idx = 1;
            while idx <= numel(fieldNames)
                fieldName = fieldNames{idx};
                rawValue = str2double(get(editHandles.(fieldName), "String"));
                if isfinite(rawValue)
                    workingOptions.(fieldName) = rawValue;
                end
                idx = idx + 1;
            end
        end

        function refreshDialogValues()
            fieldNames = fieldnames(editHandles);
            idx = 1;
            while idx <= numel(fieldNames)
                fieldName = fieldNames{idx};
                set(editHandles.(fieldName), "String", formatRetryValue(fieldName, workingOptions.(fieldName)));
                idx = idx + 1;
            end
        end

        function onApplyDialog(~, ~)
            pullValuesFromDialog();
            workingOptions = normalizeRetryOptions(workingOptions);
            wasApplied = true;
            if isgraphics(dlg)
                uiresume(dlg);
                delete(dlg);
            end
        end

        function onCancelDialog(~, ~)
            wasApplied = false;
            if isgraphics(dlg)
                uiresume(dlg);
                delete(dlg);
            end
        end
    end

    % Increase or decrease one retry-setting field by a single UI step.
    function options = applyFieldStep(options, fieldName, direction)
        switch fieldName
            case 'populationSize'
                options.populationSize = options.populationSize + 40 * direction;
            case 'generations'
                options.generations = options.generations + 100 * direction;
            case 'mutationRate'
                options.mutationRate = options.mutationRate + 0.02 * direction;
            case 'crossoverRate'
                options.crossoverRate = options.crossoverRate + 0.02 * direction;
            case 'eliteCount'
                options.eliteCount = options.eliteCount + direction;
            case 'tournamentSize'
                options.tournamentSize = options.tournamentSize + direction;
        end
    end

    % Clamp retry settings to safe ranges before they are applied.
    function options = normalizeRetryOptions(options)
        options.populationSize = max(20, min(1200, round(options.populationSize)));
        options.generations = max(50, min(2500, round(options.generations)));
        options.mutationRate = max(0.01, min(0.60, options.mutationRate));
        options.crossoverRate = max(0.50, min(0.99, options.crossoverRate));

        maxElite = max(1, options.populationSize - 1);
        options.eliteCount = max(1, min(maxElite, round(options.eliteCount)));

        maxTournament = max(2, options.populationSize - 1);
        options.tournamentSize = max(2, min(maxTournament, round(options.tournamentSize)));
    end

    % Format retry-setting values for the modal dialog edit boxes.
    function valueText = formatRetryValue(fieldName, value)
        switch fieldName
            case {'populationSize', 'generations', 'eliteCount', 'tournamentSize'}
                valueText = num2str(round(value));
            otherwise
                valueText = sprintf('%.3f', value);
        end
    end

    % Mouse-click callback used when manual path selection is enabled.
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

    % Toggle between "click to add points" mode and normal GUI interaction.
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

    % Remove the most recently added clicked point.
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

    % Clear the current user path and any stored solution preview/history.
    function onClearPoints(~, ~)
        state.userPoints = zeros(0, 2);
        state.targetPoints = zeros(0, 2);
        state.bestResult = [];
        state.bestHistory = [];
        refreshPlots();
        refreshHistoryPlot();
        logMessage("Cleared all path points.");
    end

    % Load the example shape currently selected in the popup menu.
    function onLoadExample(~, ~)
        loadExamplePath();
    end

    % Rebuild the resampled target when path-related settings change.
    function onPathSettingChanged(~, ~)
        refreshTargetData();
        refreshPlots();
    end

    % Toggle between a fixed tracer and a tracer that can move relative to
    % the mechanism during evaluation.
    function onTracePointModeChanged(src, ~)
        if logical(get(src, "Value"))
            logMessage("Tracing point mode set to moving. New runs can move the tracing point over the cycle.");
        else
            logMessage("Tracing point mode set to fixed. New runs will keep the tracing point fixed relative to the mechanism.");
        end
    end

    % Reset previews when the user switches to a different mechanism family.
    function onMechanismModeChanged(~, ~)
        if state.isRunning
            return;
        end

        state.bestResult = [];
        state.bestHistory = [];
        refreshPlots();
        refreshHistoryPlot();
        logMessage(sprintf("Mechanism mode set to %s.", mechanismModeToLabel(getSelectedMechanismMode())));
    end

    % Return the target and mechanism plots to automatic fitted extents.
    function onFitAxes(~, ~)
        state.view.lockAxes = false;
        state.view.pathLimits = [];
        state.view.linkageLimits = [];
        updateLockAxesButtonState();
        refreshPlots();
        logMessage("Axes reset to automatic fit with extra margin.");
    end

    % Zoom both plots inward around their current centers.
    function onZoomInAxes(~, ~)
        zoomAxis(state.pathAxes, 1 / 1.5);
        zoomAxis(state.linkageAxes, 1 / 1.5);
        engageManualViewLock();
        logMessage("Zoomed the path and mechanism axes in.");
    end

    % Zoom both plots outward around their current centers.
    function onZoomOutAxes(~, ~)
        zoomAxis(state.pathAxes, 1.5);
        zoomAxis(state.linkageAxes, 1.5);
        engageManualViewLock();
        logMessage("Zoomed the path and mechanism axes out by 50%.");
    end

    % Pan both plots by a fraction of their current width/height.
    function onPanAxes(dxFraction, dyFraction, directionLabel)
        panAxis(state.pathAxes, dxFraction, dyFraction);
        panAxis(state.linkageAxes, dxFraction, dyFraction);
        engageManualViewLock();
        logMessage(sprintf("Panned the path and mechanism views %s.", directionLabel));
    end

    % Legacy helper for width/height scaling of the plot extents.
    function onResizeAxes(scaleX, scaleY, resizeLabel)
        scaleAxisLimits(state.pathAxes, scaleX, scaleY);
        scaleAxisLimits(state.linkageAxes, scaleX, scaleY);
        engageManualViewLock();
        logMessage(sprintf("Adjusted the axis extents and %s.", resizeLabel));
    end

    % Once the user manually adjusts a view, preserve those axis limits.
    function engageManualViewLock()
        state.view.lockAxes = true;
        captureCurrentAxesLimits();
        updateLockAxesButtonState();
    end

    % Keep the lock/unlock button text synchronized with the current state.
    function updateLockAxesButtonState()
        if ~isfield(state.controls, "lockAxesButton") || ~isgraphics(state.controls.lockAxesButton)
            return;
        end

        if state.view.lockAxes
            set(state.controls.lockAxesButton, "Value", 1, "String", "Unlock View");
        else
            set(state.controls.lockAxesButton, "Value", 0, "String", "Lock View");
        end
    end

    % Toggle between automatic axis fitting and fixed manually chosen limits.
    function onLockAxesChanged(src, ~)
        state.view.lockAxes = logical(get(src, "Value"));
        if state.view.lockAxes
            captureCurrentAxesLimits();
            updateLockAxesButtonState();
            logMessage("Locked the current path and mechanism view extents.");
        else
            state.view.pathLimits = [];
            state.view.linkageLimits = [];
            updateLockAxesButtonState();
            refreshPlots();
            logMessage("Unlocked the axes and returned to automatic fitting.");
        end
    end

    % Build and load the currently selected built-in target shape.
    function loadExamplePath()
        menuValue = get(state.controls.exampleMenu, "Value");
        sampleCount = max(12, readInteger(state.controls.pathSamples, 32));
        menuValue = max(1, min(numel(state.exampleLibrary), menuValue));
        exampleSpec = state.exampleLibrary(menuValue);
        [state.userPoints, isClosed] = buildExamplePath(exampleSpec.id, sampleCount);
        set(state.controls.closedPath, "Value", double(isClosed));

        refreshTargetData();
        state.bestResult = [];
        state.bestHistory = [];
        refreshPlots();
        refreshHistoryPlot();
        logMessage(sprintf("Loaded %s example path.", exampleSpec.name));
    end

    % Generate one of the built-in example trajectories.
    function [points, isClosed] = buildExamplePath(shapeId, sampleCount)
        t = linspace(0, 2 * pi, sampleCount).';
        isClosed = true;

        switch shapeId
            case 'ellipse'
                points = [2.8 * cos(t), 1.7 * sin(t)];
            case 'circle'
                points = [2.1 * cos(t), 2.1 * sin(t)];
            case 'rounded_rectangle'
                points = superellipsePath(2.85, 1.55, 4.6, sampleCount);
            case 'rounded_square'
                points = superellipsePath(2.1, 2.1, 4.8, sampleCount);
            case 'half_moon'
                points = crescentPath(sampleCount);
            case 'heart'
                points = [ ...
                    1.7 * (16 * sin(t).^3) / 17, ...
                    (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) / 9];
            case 'lemniscate'
                points = [ ...
                    2.2 * cos(t) ./ (1 + sin(t).^2), ...
                    1.5 * sin(t) .* cos(t) ./ (1 + sin(t).^2)];
            case 'teardrop'
                radial = 1.15 * (1 - 0.72 * cos(t));
                points = [1.8 * radial .* cos(t), 1.25 * radial .* sin(t)];
            case 'bean'
                radial = 1.75 + 0.35 * sin(t) - 0.28 * cos(2 * t);
                points = [1.15 * radial .* cos(t), 0.92 * radial .* sin(t)];
            otherwise
                s = linspace(-2.8, 2.8, sampleCount).';
                points = [s, 1.05 * sin(1.1 * s) + 0.16 * s.^3 / max(abs(s).^3)];
                isClosed = false;
        end

        points = centerExamplePath(points);
    end

    % Superellipse helper used for rounded rectangles and rounded squares.
    function points = superellipsePath(a, b, exponent, sampleCount)
        angle = linspace(0, 2 * pi, sampleCount).';
        cosTerm = sign(cos(angle)) .* abs(cos(angle)).^(2 / exponent);
        sinTerm = sign(sin(angle)) .* abs(sin(angle)).^(2 / exponent);
        points = [a * cosTerm, b * sinTerm];
    end

    % Crescent / half-moon helper built from an outer arc and an inner arc.
    function points = crescentPath(sampleCount)
        outerCount = max(6, round(0.56 * sampleCount));
        innerCount = max(6, sampleCount - outerCount + 2);
        outerTheta = linspace(deg2rad(78), deg2rad(282), outerCount).';
        innerTheta = linspace(deg2rad(282), deg2rad(78), innerCount).';

        outerArc = [2.45 * cos(outerTheta), 2.05 * sin(outerTheta)];
        innerCenter = [0.85, 0];
        innerArc = [innerCenter(1) + 1.62 * cos(innerTheta), innerCenter(2) + 1.43 * sin(innerTheta)];
        points = [outerArc; innerArc(2:end-1, :)];
    end

    % Translate an example path so its centroid is near the origin.
    function points = centerExamplePath(points)
        points = points - mean(points, 1);
    end

    % Resample the current user path into the target path used by the GA.
    function refreshTargetData()
        if size(state.userPoints, 1) < 2
            state.targetPoints = state.userPoints;
            return;
        end

        sampleCount = max(8, readInteger(state.controls.pathSamples, 32));
        isClosed = logical(get(state.controls.closedPath, "Value"));
        state.targetPoints = resamplePath(state.userPoints, sampleCount, isClosed);
    end

    % Arc-length resampling of the user-specified path so target points are
    % distributed more evenly along the curve.
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

    % Main "Run Genetic Algorithm" callback. This validates the inputs,
    % launches the solver, handles retries, and plays the final animation.
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
            [options.useParallel, poolMessage] = prepareParallelPool(options.numWorkers);
            logMessage(poolMessage);

            bestOverall = [];
            combinedHistory = [];
            seedGenes = [];
            currentOptions = options;
            attempt = 1;

            logMessage(sprintf("Running %s synthesis on %d target samples.", ...
                mechanismModeToLabel(currentOptions.mechanismMode), size(currentOptions.targetPoints, 1)));

            while ~state.stopRequested
                logMessage(sprintf("Attempt %d | %s | pop=%d gen=%d mut=%.2f workers=%d", ...
                    attempt, ...
                    mechanismModeToLabel(currentOptions.mechanismMode), ...
                    currentOptions.populationSize, currentOptions.generations, currentOptions.mutationRate, currentOptions.numWorkers));

                [attemptBest, attemptHistory, runInfo] = runGeneticAlgorithm(currentOptions, seedGenes);
                combinedHistory = appendHistory(combinedHistory, attemptHistory);
                state.bestHistory = combinedHistory;

                if ~isempty(attemptBest) && (isempty(bestOverall) || attemptBest.fitness < bestOverall.fitness)
                    bestOverall = attemptBest;
                    seedGenes = bestOverall.genes;
                end

                state.bestResult = bestOverall;
                refreshPlots();
                refreshHistoryPlot();

                if isempty(bestOverall)
                    if runInfo.stalled
                        showStallGuidance([], currentOptions);
                    end
                    choice = promptForContinuation([], currentOptions, runInfo);
                    if strcmp(choice, "Stop")
                        break;
                    elseif strcmp(choice, "Continue with stronger settings")
                        proposedOptions = strengthenOptions(currentOptions);
                        [currentOptions, didAccept] = customizeStrongerSettings(proposedOptions, [], runInfo);
                        if ~didAccept
                            logMessage("Stronger-setting continuation canceled. Keeping the best result from the completed attempts.");
                            break;
                        end
                        syncUiWithOptions(currentOptions);
                        logGaSettingsSummary("Using stronger settings", currentOptions);
                    else
                        logMessage("Continuing once more with the current settings.");
                    end
                    attempt = attempt + 1;
                    continue;
                end

                if bestOverall.rmsError <= currentOptions.targetRmse
                    logMessage(sprintf("Target RMSE %.4f reached.", currentOptions.targetRmse));
                    break;
                end

                if state.stopRequested
                    break;
                end

                if runInfo.stalled
                    showStallGuidance(bestOverall, currentOptions);
                end

                choice = promptForContinuation(bestOverall, currentOptions, runInfo);
                if strcmp(choice, "Stop")
                    break;
                elseif strcmp(choice, "Continue with stronger settings")
                    proposedOptions = strengthenOptions(currentOptions);
                    [currentOptions, didAccept] = customizeStrongerSettings(proposedOptions, bestOverall, runInfo);
                    if ~didAccept
                        logMessage("Stronger-setting continuation canceled. Keeping the best result from the completed attempts.");
                        break;
                    end
                    syncUiWithOptions(currentOptions);
                    logGaSettingsSummary("Using stronger settings", currentOptions);
                else
                    logMessage("Continuing once more with the current settings and a warm start from the best candidate.");
                end

                attempt = attempt + 1;
            end

            state.bestResult = bestOverall;
            state.bestHistory = combinedHistory;
            refreshPlots();
            refreshHistoryPlot();

            if ~isempty(bestOverall)
                logMessage(sprintf("Best RMS error: %.5f", bestOverall.rmsError));
                if bestOverall.penalty > 0
                    logMessage(sprintf("Residual penalty term: %.5f", bestOverall.penalty));
                end
                logBestMechanismSummary(bestOverall);
                if ~state.stopRequested
                    playFinalAnimation(bestOverall, currentOptions);
                end
            end
        catch err
            logMessage(sprintf("Run failed: %s", err.message));
            errordlg(err.message, "Run Failed");
        end

        state.isRunning = false;
        setBusyState(false);
    end

    % Cooperative stop request. The active generation is allowed to finish.
    function onStopRun(~, ~)
        if state.isRunning
            state.stopRequested = true;
            logMessage("Stop requested. Finishing the current generation.");
        end
    end

    % Read all editable GUI settings into a single options structure.
    %
    % This is the main place to look if you want to know which variables are
    % user-editable from the GUI and what defaults are used.
    function options = readGaOptions()
        options = struct();
        options.populationSize = readInteger(state.controls.populationSize, 320);
        options.generations = readInteger(state.controls.generations, 650);
        options.mutationRate = readDouble(state.controls.mutationRate, 0.28);
        options.crossoverRate = readDouble(state.controls.crossoverRate, 0.90);
        options.eliteCount = readInteger(state.controls.eliteCount, 12);
        options.tournamentSize = readInteger(state.controls.tournamentSize, 4);
        options.pathSamples = readInteger(state.controls.pathSamples, 36);
        options.animationCycles = readInteger(state.controls.animationCycles, 2);
        options.framePause = readDouble(state.controls.framePause, 0.03);
        options.numWorkers = readInteger(state.controls.numWorkers, defaultWorkerCount());
        options.targetRmse = readDouble(state.controls.targetRmse, 0.10);
        options.closedPath = logical(get(state.controls.closedPath, "Value"));
        options.allowMovingTracePoint = logical(get(state.controls.movingTracePoint, "Value"));
        options.targetPoints = state.targetPoints;
        options.mechanismMode = getSelectedMechanismMode();
        options.mechanismLabel = mechanismModeToLabel(options.mechanismMode);
        complexity = mechanismComplexityFactor(options.mechanismMode);
        options.previewEvery = max(4, round(6 + complexity));
        options.stallLimit = max(80, round((0.16 + 0.03 * complexity) * options.generations));
        options.maxRestarts = 2 + ceil(complexity);

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

        if options.numWorkers < 1
            errordlg("Workers must be at least 1.", "Invalid Settings");
            options = [];
            return;
        end

        if options.targetRmse <= 0
            errordlg("Target RMSE must be greater than 0.", "Invalid Settings");
            options = [];
            return;
        end

        if options.mutationRate < 0 || options.mutationRate > 1 || options.crossoverRate < 0 || options.crossoverRate > 1
            errordlg("Mutation and crossover rates must be between 0 and 1.", "Invalid Settings");
            options = [];
            return;
        end
    end

    % Custom genetic algorithm:
    % - initialize a population inside parameter bounds
    % - evaluate every candidate linkage
    % - preserve elites
    % - create children via tournament selection, blend crossover, mutation
    % - inject immigrants and restart around the best design if stalled
    % - finish with a local random/sweep refinement pass
    function [bestResult, history, runInfo] = runGeneticAlgorithm(options, warmStartGenes)
        if nargin < 2
            warmStartGenes = [];
        end

        target = options.targetPoints;
        bounds = buildBounds(target, options.mechanismMode);
        sigmaBase = 0.12 * (bounds.upper - bounds.lower);
        sigma = sigmaBase;
        mutationBase = options.mutationRate;
        population = initializePopulation(options.populationSize, bounds, target, warmStartGenes, options.mechanismMode);
        [scores, results] = evaluatePopulation(population, target, options.closedPath, options.useParallel, options.mechanismMode, options.allowMovingTracePoint);

        bestResult = [];
        bestScore = inf;
        history = nan(options.generations, 1);
        stallCounter = 0;
        restartCount = 0;
        runInfo = struct("stalled", false, "exitReason", "completed", "restartCount", 0);

        for generation = 1:options.generations
            if state.stopRequested
                runInfo.exitReason = "user_stop";
                break;
            end

            % Sort so the best individual is always at the top of the
            % population, making elitism and logging straightforward.
            [scores, order] = sort(scores, "ascend");
            population = population(order, :);
            results = results(order);
            history(generation) = scores(1);

            % Track the best-so-far individual across all generations.
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
                if restartCount < options.maxRestarts && ~state.stopRequested
                    restartCount = restartCount + 1;
                    runInfo.restartCount = restartCount;
                    % Restarts broaden the search around the best design
                    % found so far by raising mutation and sampling a fresh
                    % population around that design.
                    mutationBase = min(0.60, mutationBase + 0.03 + 0.01 * restartCount);
                    sigma = min(0.45 * (bounds.upper - bounds.lower), sigmaBase * (1 + 0.30 * restartCount));
                    if ~isempty(bestResult)
                        restartSeed = bestResult.genes;
                    else
                        restartSeed = population(1, :);
                    end
                    logMessage(sprintf("Restarting search basin %d / %d after %d stalled generations.", ...
                        restartCount, options.maxRestarts, options.stallLimit));
                    population = initializePopulation(options.populationSize, bounds, target, restartSeed, options.mechanismMode);
                    [scores, results] = evaluatePopulation(population, target, options.closedPath, options.useParallel, options.mechanismMode, options.allowMovingTracePoint);
                    stallCounter = 0;
                    continue;
                end

                runInfo.stalled = true;
                runInfo.exitReason = "stalled";
                logMessage(sprintf("Stopping early after %d stalled generations.", options.stallLimit));
                history = history(1:generation);
                break;
            end

            nextPopulation = zeros(size(population));
            % Elitism: copy the best candidates unchanged into the next
            % generation so good solutions are never lost.
            nextPopulation(1:options.eliteCount, :) = population(1:options.eliteCount, :);

            insertIndex = options.eliteCount + 1;
            effectiveMutation = min(0.60, mutationBase * (1 + 1.5 * stallCounter / max(1, options.stallLimit)));
            effectiveSigma = sigma * (1 + stallCounter / max(1, options.stallLimit));
            while insertIndex <= options.populationSize
                % Tournament selection: sample a small subset of the
                % population and choose the best member as a parent.
                parentA = population(tournamentSelect(scores, options.tournamentSize), :);
                parentB = population(tournamentSelect(scores, options.tournamentSize), :);

                childA = parentA;
                childB = parentB;
                if rand < options.crossoverRate
                    % Blend crossover creates children by mixing parent genes.
                    [childA, childB] = blendCrossover(parentA, parentB, bounds);
                end

                % Mutation perturbs genes with Gaussian noise.
                childA = mutateIndividual(childA, bounds, effectiveSigma, effectiveMutation);
                childB = mutateIndividual(childB, bounds, effectiveSigma, effectiveMutation);

                nextPopulation(insertIndex, :) = childA;
                if insertIndex + 1 <= options.populationSize
                    nextPopulation(insertIndex + 1, :) = childB;
                end
                insertIndex = insertIndex + 2;
            end

            if stallCounter >= max(3, floor(0.45 * options.stallLimit))
                % Immigrants inject diversity when the population begins to
                % collapse around one basin too early.
                immigrantCount = max(6, ceil((0.12 + 0.03 * restartCount) * options.populationSize));
                nextPopulation(end - immigrantCount + 1:end, :) = initializePopulation( ...
                    immigrantCount, bounds, target, population(1, :), options.mechanismMode);
            end

            population = nextPopulation;
            [scores, results] = evaluatePopulation(population, target, options.closedPath, options.useParallel, options.mechanismMode, options.allowMovingTracePoint);

            if generation == options.generations
                history = history(1:generation);
            end
        end

        if isempty(bestResult) && ~isempty(results)
            [~, bestIndex] = min(scores);
            bestResult = results{bestIndex};
        end

        if ~isempty(bestResult)
            % Final local cleanup after the global GA search.
            bestResult = refineCandidate(bestResult.genes, target, bounds, bestResult, options.closedPath, options.mechanismMode, options.allowMovingTracePoint);
        end

        history = history(isfinite(history));
        setStatus("idle");
    end

    % Build lower/upper parameter bounds for the selected mechanism mode.
    %
    % Each mechanism family has its own chromosome layout. The bounds define
    % the search box explored by the GA for that layout.
    function bounds = buildBounds(target, mechanismMode)
        minXY = min(target, [], 1);
        maxXY = max(target, [], 1);
        center = mean(target, 1);
        span = max(maxXY - minXY);
        span = max(span, 1);
        margin = 3.5 * span;
        lenMin = 0.08 * span;
        lenMax = 4.0 * span;

        switch mechanismMode
            case 'standard_fourbar'
                bounds.lower = [ ...
                    center(1) - margin, ... % ground x
                    center(2) - margin, ... % ground y
                    0, ...                  % ground angle
                    lenMin, ...             % ground length
                    lenMin, ...             % crank
                    lenMin, ...             % coupler
                    lenMin, ...             % rocker
                    0, ...                  % coupler-point blend
                    -1.2 * span, ...        % coupler-point offset
                    0, ...                  % dynamic blend amplitude
                    0, ...                  % dynamic blend phase
                    0, ...                  % dynamic offset amplitude
                    0, ...                  % dynamic offset phase
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
                    1, ...
                    1.2 * span, ...
                    0.45, ...
                    2 * pi, ...
                    0.8 * span, ...
                    2 * pi, ...
                    2 * pi, ...
                    2 * pi, ...
                    1, ...
                    1];
            case 'advanced_fourbar'
                bounds.lower = [ ...
                    center(1) - margin, ... % ground x
                    center(2) - margin, ... % ground y
                    0, ...                  % ground angle
                    lenMin, ...             % ground length
                    lenMin, ...             % crank
                    lenMin, ...             % coupler
                    lenMin, ...             % rocker
                    -pi, ...                % slider B rail angle
                    -2.0 * span, ...        % slider B offset
                    0, ...                  % slider B amplitude 1
                    0, ...                  % slider B phase 1
                    0, ...                  % slider B amplitude 2
                    0, ...                  % slider B phase 2
                    -pi, ...                % slider C rail angle
                    -2.0 * span, ...        % slider C offset
                    0, ...                  % slider C amplitude 1
                    0, ...                  % slider C phase 1
                    0, ...                  % slider C amplitude 2
                    0, ...                  % slider C phase 2
                    0, ...                  % trace blend
                    -1.5 * span, ...        % connector offset
                    0, ...                  % dynamic blend amplitude
                    0, ...                  % dynamic blend phase
                    0, ...                  % dynamic offset amplitude
                    0, ...                  % dynamic offset phase
                    0, ...                  % input start angle
                    deg2rad(20), ...        % input sweep
                    0, ...                  % branch selector
                    0, ...                  % direction selector
                    0, ...                  % slider B amplitude 3
                    0, ...                  % slider B phase 3
                    0, ...                  % slider C amplitude 3
                    0, ...                  % slider C phase 3
                    0, ...                  % dynamic bridge scale
                    0, ...                  % bridge longitudinal amplitude
                    0, ...                  % bridge longitudinal phase
                    0, ...                  % bridge normal amplitude
                    0];                     % bridge normal phase

                bounds.upper = [ ...
                    center(1) + margin, ...
                    center(2) + margin, ...
                    2 * pi, ...
                    lenMax, ...
                    lenMax, ...
                    lenMax, ...
                    lenMax, ...
                    pi, ...
                    2.0 * span, ...
                    1.4 * span, ...
                    2 * pi, ...
                    0.8 * span, ...
                    2 * pi, ...
                    pi, ...
                    2.0 * span, ...
                    1.4 * span, ...
                    2 * pi, ...
                    0.8 * span, ...
                    2 * pi, ...
                    1, ...
                    1.5 * span, ...
                    0.45, ...
                    2 * pi, ...
                    0.8 * span, ...
                    2 * pi, ...
                    2 * pi, ...
                    2 * pi, ...
                    1, ...
                    1, ...
                    0.6 * span, ...
                    2 * pi, ...
                    0.6 * span, ...
                    2 * pi, ...
                    1, ...
                    0.8 * span, ...
                    2 * pi, ...
                    0.8 * span, ...
                    2 * pi];
            case 'fivebar'
                bounds.lower = [ ...
                    center(1) - margin, ... % ground x
                    center(2) - margin, ... % ground y
                    0, ...                  % ground angle
                    lenMin, ...             % ground length
                    lenMin, ...             % left crank
                    lenMin, ...             % left distal
                    lenMin, ...             % right crank
                    lenMin, ...             % right distal
                    -pi, ...                % phase offset
                    0.55, ...               % crank ratio
                    0, ...                  % trace blend
                    -1.5 * span, ...        % connector offset
                    0, ...                  % dynamic blend amplitude
                    0, ...                  % dynamic blend phase
                    0, ...                  % dynamic offset amplitude
                    0, ...                  % dynamic offset phase
                    0, ...                  % input start
                    deg2rad(25), ...        % input sweep
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
                    lenMax, ...
                    pi, ...
                    1.85, ...
                    1, ...
                    1.5 * span, ...
                    0.45, ...
                    2 * pi, ...
                    0.8 * span, ...
                    2 * pi, ...
                    2 * pi, ...
                    2 * pi, ...
                    1, ...
                    1];
            case 'advanced_fivebar'
                bounds.lower = [ ...
                    center(1) - margin, ... % ground x
                    center(2) - margin, ... % ground y
                    0, ...                  % ground angle
                    lenMin, ...             % ground length
                    lenMin, ...             % left crank
                    lenMin, ...             % left distal
                    lenMin, ...             % right crank
                    lenMin, ...             % right distal
                    -pi, ...                % phase offset
                    0.55, ...               % crank ratio
                    0, ...                  % left slider blend
                    -pi, ...                % left slider angle
                    0, ...                  % left slider amplitude
                    0, ...                  % left slider phase
                    0, ...                  % right slider blend
                    -pi, ...                % right slider angle
                    0, ...                  % right slider amplitude
                    0, ...                  % right slider phase
                    0, ...                  % bridge blend
                    0, ...                  % bridge longitudinal amplitude
                    0, ...                  % bridge longitudinal phase
                    0, ...                  % bridge normal amplitude
                    0, ...                  % bridge normal phase
                    0, ...                  % input start
                    deg2rad(25), ...        % input sweep
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
                    lenMax, ...
                    pi, ...
                    1.85, ...
                    1, ...
                    pi, ...
                    1.0 * span, ...
                    2 * pi, ...
                    1, ...
                    pi, ...
                    1.0 * span, ...
                    2 * pi, ...
                    1, ...
                    0.8 * span, ...
                    2 * pi, ...
                    0.8 * span, ...
                    2 * pi, ...
                    2 * pi, ...
                    2 * pi, ...
                    1, ...
                    1];
            case 'sixbar'
                bounds.lower = [ ...
                    center(1) - margin, ... % ground x
                    center(2) - margin, ... % ground y
                    0, ...                  % ground angle
                    lenMin, ...             % ground length
                    lenMin, ...             % crank
                    lenMin, ...             % coupler
                    lenMin, ...             % rocker
                    0, ...                  % auxiliary ground blend
                    -1.5 * span, ...        % auxiliary ground offset
                    0, ...                  % coupler blend
                    -1.2 * span, ...        % coupler offset
                    lenMin, ...             % auxiliary coupler link
                    lenMin, ...             % auxiliary rocker link
                    0, ...                  % trace blend
                    -1.2 * span, ...        % trace offset
                    0, ...                  % dynamic blend amplitude
                    0, ...                  % dynamic blend phase
                    0, ...                  % dynamic offset amplitude
                    0, ...                  % dynamic offset phase
                    0, ...                  % input start
                    deg2rad(20), ...        % input sweep
                    0, ...                  % base branch selector
                    0, ...                  % auxiliary branch selector
                    0];                     % direction selector

                bounds.upper = [ ...
                    center(1) + margin, ...
                    center(2) + margin, ...
                    2 * pi, ...
                    lenMax, ...
                    lenMax, ...
                    lenMax, ...
                    lenMax, ...
                    1, ...
                    1.5 * span, ...
                    1, ...
                    1.2 * span, ...
                    lenMax, ...
                    lenMax, ...
                    1, ...
                    1.2 * span, ...
                    0.45, ...
                    2 * pi, ...
                    0.8 * span, ...
                    2 * pi, ...
                    2 * pi, ...
                    2 * pi, ...
                    1, ...
                    1, ...
                    1];
            case 'advanced_sixbar'
                bounds.lower = [ ...
                    center(1) - margin, ... % ground x
                    center(2) - margin, ... % ground y
                    0, ...                  % ground angle
                    lenMin, ...             % ground length
                    lenMin, ...             % crank
                    lenMin, ...             % coupler
                    lenMin, ...             % rocker
                    0, ...                  % auxiliary ground blend
                    -1.5 * span, ...        % auxiliary ground offset
                    0, ...                  % coupler blend
                    -1.2 * span, ...        % coupler offset
                    lenMin, ...             % auxiliary coupler link
                    lenMin, ...             % auxiliary rocker link
                    0, ...                  % slider J blend
                    -pi, ...                % slider J angle
                    0, ...                  % slider J amplitude
                    0, ...                  % slider J phase
                    0, ...                  % slider F blend
                    -pi, ...                % slider F angle
                    0, ...                  % slider F amplitude
                    0, ...                  % slider F phase
                    0, ...                  % bridge blend
                    0, ...                  % bridge longitudinal amplitude
                    0, ...                  % bridge longitudinal phase
                    0, ...                  % bridge normal amplitude
                    0, ...                  % bridge normal phase
                    0, ...                  % input start
                    deg2rad(20), ...        % input sweep
                    0, ...                  % base branch selector
                    0, ...                  % auxiliary branch selector
                    0];                     % direction selector

                bounds.upper = [ ...
                    center(1) + margin, ...
                    center(2) + margin, ...
                    2 * pi, ...
                    lenMax, ...
                    lenMax, ...
                    lenMax, ...
                    lenMax, ...
                    1, ...
                    1.5 * span, ...
                    1, ...
                    1.2 * span, ...
                    lenMax, ...
                    lenMax, ...
                    1, ...
                    pi, ...
                    1.0 * span, ...
                    2 * pi, ...
                    1, ...
                    pi, ...
                    1.0 * span, ...
                    2 * pi, ...
                    1, ...
                    0.8 * span, ...
                    2 * pi, ...
                    0.8 * span, ...
                    2 * pi, ...
                    2 * pi, ...
                    2 * pi, ...
                    1, ...
                    1, ...
                    1];
            otherwise
                bounds.lower = [ ...
                    center(1) - margin, ... % ground x
                    center(2) - margin, ... % ground y
                    0, ...                  % ground angle
                    lenMin, ...             % ground length
                    lenMin, ...             % crank
                    lenMin, ...             % coupler
                    lenMin, ...             % rocker
                    -pi, ...                % slider B rail angle
                    -2.0 * span, ...        % slider B offset
                    0, ...                  % slider B amplitude 1
                    0, ...                  % slider B phase 1
                    0, ...                  % slider B amplitude 2
                    0, ...                  % slider B phase 2
                    -pi, ...                % slider C rail angle
                    -2.0 * span, ...        % slider C offset
                    0, ...                  % slider C amplitude 1
                    0, ...                  % slider C phase 1
                    0, ...                  % slider C amplitude 2
                    0, ...                  % slider C phase 2
                    0, ...                  % trace blend
                    -1.5 * span, ...        % connector offset
                    0, ...                  % dynamic blend amplitude
                    0, ...                  % dynamic blend phase
                    0, ...                  % dynamic offset amplitude
                    0, ...                  % dynamic offset phase
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
                    pi, ...
                    2.0 * span, ...
                    1.4 * span, ...
                    2 * pi, ...
                    0.8 * span, ...
                    2 * pi, ...
                    pi, ...
                    2.0 * span, ...
                    1.4 * span, ...
                    2 * pi, ...
                    0.8 * span, ...
                    2 * pi, ...
                    1, ...
                    1.5 * span, ...
                    0.45, ...
                    2 * pi, ...
                    0.8 * span, ...
                    2 * pi, ...
                    2 * pi, ...
                    2 * pi, ...
                    1, ...
                    1];
        end
    end

    % Create the initial population. A small number of heuristic seeds are
    % placed near the target scale so the GA starts from plausible linkages.
    function population = initializePopulation(populationSize, bounds, target, warmStartGenes, mechanismMode)
        if nargin < 4
            warmStartGenes = [];
        end
        if nargin < 5
            mechanismMode = 'standard_fourbar';
        end

        variableCount = numel(bounds.lower);
        population = rand(populationSize, variableCount) .* (bounds.upper - bounds.lower) + bounds.lower;

        center = mean(target, 1);
        span = max(max(target) - min(target));
        span = max(span, 1);

        seedStart = 1;
        if ~isempty(warmStartGenes) && numel(warmStartGenes) == variableCount
            population(1, :) = clampToBounds(warmStartGenes, bounds);
            warmCloneCount = min(8, populationSize - 1);
            for idx = 1:warmCloneCount
                clone = warmStartGenes + 0.05 * (bounds.upper - bounds.lower) .* randn(1, variableCount);
                population(1 + idx, :) = clampToBounds(clone, bounds);
            end
            seedStart = 2 + warmCloneCount;
        end

        seedEnd = min(populationSize, seedStart + 11);
        seedDivisor = max(1, seedEnd - seedStart + 1);
        for idx = seedStart:seedEnd
            seed = population(idx, :);
            seed(1:2) = center + 0.35 * span * randn(1, 2);
            seed(3) = mod((idx - seedStart) / seedDivisor * 2 * pi, 2 * pi);

            switch mechanismMode
                case 'standard_fourbar'
                    seed(4) = 1.55 * span * (0.65 + 0.22 * rand);
                    seed(5) = 0.52 * span * (0.8 + 0.45 * rand);
                    seed(6) = 1.10 * span * (0.8 + 0.45 * rand);
                    seed(7) = 1.02 * span * (0.8 + 0.45 * rand);
                    seed(8) = 0.15 + 0.7 * rand;
                    seed(9) = 0.10 * span * randn;
                    seed(10) = 0.08 + 0.16 * rand;
                    seed(11) = 2 * pi * rand;
                    seed(12) = 0.05 * span * rand;
                    seed(13) = 2 * pi * rand;
                    seed(14) = 2 * pi * rand;
                    seed(15) = deg2rad(95 + 220 * rand);
                    seed(16) = rand > 0.5;
                    seed(17) = rand > 0.5;
                case 'advanced_fourbar'
                    seed(4) = 1.65 * span * (0.65 + 0.24 * rand);
                    seed(5) = 0.58 * span * (0.8 + 0.5 * rand);
                    seed(6) = 1.18 * span * (0.8 + 0.5 * rand);
                    seed(7) = 1.12 * span * (0.8 + 0.5 * rand);
                    seed(8) = -pi + 2 * pi * rand;
                    seed(9) = 0.22 * span * randn;
                    seed(10) = 0.28 * span * rand;
                    seed(11) = 2 * pi * rand;
                    seed(12) = 0.14 * span * rand;
                    seed(13) = 2 * pi * rand;
                    seed(14) = -pi + 2 * pi * rand;
                    seed(15) = 0.22 * span * randn;
                    seed(16) = 0.28 * span * rand;
                    seed(17) = 2 * pi * rand;
                    seed(18) = 0.14 * span * rand;
                    seed(19) = 2 * pi * rand;
                    seed(20) = 0.15 + 0.7 * rand;
                    seed(21) = 0.12 * span * randn;
                    seed(22) = 0.10 + 0.18 * rand;
                    seed(23) = 2 * pi * rand;
                    seed(24) = 0.05 * span * rand;
                    seed(25) = 2 * pi * rand;
                    seed(26) = 2 * pi * rand;
                    seed(27) = deg2rad(110 + 210 * rand);
                    seed(28) = rand > 0.5;
                    seed(29) = rand > 0.5;
                    seed(30) = 0.10 * span * rand;
                    seed(31) = 2 * pi * rand;
                    seed(32) = 0.10 * span * rand;
                    seed(33) = 2 * pi * rand;
                    seed(34) = 0.2 + 0.6 * rand;
                    seed(35) = 0.10 * span * rand;
                    seed(36) = 2 * pi * rand;
                    seed(37) = 0.12 * span * rand;
                    seed(38) = 2 * pi * rand;
                case 'fivebar'
                    seed(4) = 1.7 * span * (0.65 + 0.25 * rand);
                    seed(5) = 0.85 * span * (0.8 + 0.45 * rand);
                    seed(6) = 1.35 * span * (0.8 + 0.45 * rand);
                    seed(7) = 0.82 * span * (0.8 + 0.45 * rand);
                    seed(8) = 1.32 * span * (0.8 + 0.45 * rand);
                    seed(9) = -0.6 + 1.2 * rand;
                    seed(10) = 0.85 + 0.35 * rand;
                    seed(11) = 0.15 + 0.7 * rand;
                    seed(12) = 0.12 * span * randn;
                    seed(13) = 0.08 + 0.16 * rand;
                    seed(14) = 2 * pi * rand;
                    seed(15) = 0.05 * span * rand;
                    seed(16) = 2 * pi * rand;
                    seed(17) = 2 * pi * rand;
                    seed(18) = deg2rad(110 + 190 * rand);
                    seed(19) = rand > 0.5;
                    seed(20) = rand > 0.5;
                case 'advanced_fivebar'
                    seed(4) = 1.75 * span * (0.65 + 0.25 * rand);
                    seed(5) = 0.90 * span * (0.8 + 0.45 * rand);
                    seed(6) = 1.40 * span * (0.8 + 0.45 * rand);
                    seed(7) = 0.88 * span * (0.8 + 0.45 * rand);
                    seed(8) = 1.36 * span * (0.8 + 0.45 * rand);
                    seed(9) = -0.8 + 1.6 * rand;
                    seed(10) = 0.82 + 0.40 * rand;
                    seed(11) = 0.18 + 0.6 * rand;
                    seed(12) = -pi + 2 * pi * rand;
                    seed(13) = 0.16 * span * rand;
                    seed(14) = 2 * pi * rand;
                    seed(15) = 0.18 + 0.6 * rand;
                    seed(16) = -pi + 2 * pi * rand;
                    seed(17) = 0.16 * span * rand;
                    seed(18) = 2 * pi * rand;
                    seed(19) = 0.20 + 0.6 * rand;
                    seed(20) = 0.12 * span * rand;
                    seed(21) = 2 * pi * rand;
                    seed(22) = 0.14 * span * rand;
                    seed(23) = 2 * pi * rand;
                    seed(24) = 2 * pi * rand;
                    seed(25) = deg2rad(120 + 180 * rand);
                    seed(26) = rand > 0.5;
                    seed(27) = rand > 0.5;
                case 'sixbar'
                    seed(4) = 1.7 * span * (0.65 + 0.25 * rand);
                    seed(5) = 0.58 * span * (0.8 + 0.45 * rand);
                    seed(6) = 1.18 * span * (0.8 + 0.45 * rand);
                    seed(7) = 1.08 * span * (0.8 + 0.45 * rand);
                    seed(8) = 0.25 + 0.5 * rand;
                    seed(9) = 0.14 * span * randn;
                    seed(10) = 0.25 + 0.5 * rand;
                    seed(11) = 0.12 * span * randn;
                    seed(12) = 0.95 * span * (0.8 + 0.45 * rand);
                    seed(13) = 0.88 * span * (0.8 + 0.45 * rand);
                    seed(14) = 0.15 + 0.7 * rand;
                    seed(15) = 0.10 * span * randn;
                    seed(16) = 0.08 + 0.16 * rand;
                    seed(17) = 2 * pi * rand;
                    seed(18) = 0.06 * span * rand;
                    seed(19) = 2 * pi * rand;
                    seed(20) = 2 * pi * rand;
                    seed(21) = deg2rad(100 + 210 * rand);
                    seed(22) = rand > 0.5;
                    seed(23) = rand > 0.5;
                    seed(24) = rand > 0.5;
                case 'advanced_sixbar'
                    seed(4) = 1.8 * span * (0.65 + 0.25 * rand);
                    seed(5) = 0.62 * span * (0.8 + 0.45 * rand);
                    seed(6) = 1.22 * span * (0.8 + 0.45 * rand);
                    seed(7) = 1.14 * span * (0.8 + 0.45 * rand);
                    seed(8) = 0.25 + 0.5 * rand;
                    seed(9) = 0.14 * span * randn;
                    seed(10) = 0.25 + 0.5 * rand;
                    seed(11) = 0.12 * span * randn;
                    seed(12) = 1.00 * span * (0.8 + 0.45 * rand);
                    seed(13) = 0.92 * span * (0.8 + 0.45 * rand);
                    seed(14) = 0.18 + 0.6 * rand;
                    seed(15) = -pi + 2 * pi * rand;
                    seed(16) = 0.16 * span * rand;
                    seed(17) = 2 * pi * rand;
                    seed(18) = 0.18 + 0.6 * rand;
                    seed(19) = -pi + 2 * pi * rand;
                    seed(20) = 0.16 * span * rand;
                    seed(21) = 2 * pi * rand;
                    seed(22) = 0.20 + 0.6 * rand;
                    seed(23) = 0.12 * span * rand;
                    seed(24) = 2 * pi * rand;
                    seed(25) = 0.14 * span * rand;
                    seed(26) = 2 * pi * rand;
                    seed(27) = 2 * pi * rand;
                    seed(28) = deg2rad(110 + 200 * rand);
                    seed(29) = rand > 0.5;
                    seed(30) = rand > 0.5;
                    seed(31) = rand > 0.5;
                otherwise
                    seed(4) = 1.6 * span * (0.65 + 0.2 * rand);
                    seed(5) = 0.55 * span * (0.8 + 0.5 * rand);
                    seed(6) = 1.15 * span * (0.8 + 0.5 * rand);
                    seed(7) = 1.1 * span * (0.8 + 0.5 * rand);
                    seed(8) = -pi + 2 * pi * rand;
                    seed(9) = 0.25 * span * randn;
                    seed(10) = 0.25 * span * rand;
                    seed(11) = 2 * pi * rand;
                    seed(12) = 0.12 * span * rand;
                    seed(13) = 2 * pi * rand;
                    seed(14) = -pi + 2 * pi * rand;
                    seed(15) = 0.25 * span * randn;
                    seed(16) = 0.25 * span * rand;
                    seed(17) = 2 * pi * rand;
                    seed(18) = 0.12 * span * rand;
                    seed(19) = 2 * pi * rand;
                    seed(20) = rand;
                    seed(21) = 0.15 * span * randn;
                    seed(22) = 0.10 + 0.18 * rand;
                    seed(23) = 2 * pi * rand;
                    seed(24) = 0.05 * span * rand;
                    seed(25) = 2 * pi * rand;
                    seed(26) = 2 * pi * rand;
                    seed(27) = deg2rad(90 + 220 * rand);
                    seed(28) = rand > 0.5;
                    seed(29) = rand > 0.5;
            end
            population(idx, :) = clampToBounds(seed, bounds);
        end
    end

    % Evaluate all candidates in the population, optionally in parallel.
    function [scores, results] = evaluatePopulation(population, target, isClosedPath, useParallel, mechanismMode, allowMovingTracePoint)
        candidateCount = size(population, 1);
        scores = zeros(candidateCount, 1);
        results = cell(candidateCount, 1);

        if useParallel && candidateCount > 1
            try
                parfor idx = 1:candidateCount
                    result = linkageEvaluateCandidate(population(idx, :), target, isClosedPath, mechanismMode, allowMovingTracePoint);
                    scores(idx) = result.fitness;
                    results{idx} = result;
                end
                return;
            catch err
                logMessage(sprintf("Parallel evaluation failed (%s). Reverting to serial evaluation.", err.message));
            end
        end

        for idx = 1:candidateCount
            result = linkageEvaluateCandidate(population(idx, :), target, isClosedPath, mechanismMode, allowMovingTracePoint);
            scores(idx) = result.fitness;
            results{idx} = result;
        end
    end

    % Legacy four-bar evaluator kept for compatibility/reference.
    function result = evaluateCandidate(candidate, target, isClosedPath)
        params = decodeCandidate(candidate, size(target, 1));
        result = struct();
        result.fitness = inf;
        result.rmsError = inf;
        result.penalty = inf;
        result.genes = candidate;
        result.params = params;
        result.path = nan(size(target));
        result.A = nan(size(target));
        result.B = nan(size(target));
        result.C = nan(size(target));
        result.D = nan(size(target));
        result.sliderB = nan(size(target));
        result.sliderC = nan(size(target));
        result.order = 1:size(target, 1);
        result.isValid = false;

        inputAngles = params.inputAngles(:);
        sampleCount = numel(inputAngles);
        A = repmat(params.groundA, sampleCount, 1);
        D = repmat(params.groundD, sampleCount, 1);
        B = nan(sampleCount, 2);
        C = nan(sampleCount, 2);
        sliderB = nan(sampleCount, 2);
        sliderC = nan(sampleCount, 2);
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
            theta = inputAngles(idx);
            dirB = cos(params.sliderAngleB) * ux + sin(params.sliderAngleB) * uy;
            dirC = cos(params.sliderAngleC) * ux + sin(params.sliderAngleC) * uy;
            displacementB = params.sliderOffsetB ...
                + params.sliderAmpB1 * sin(theta + params.sliderPhaseB1) ...
                + params.sliderAmpB2 * sin(2 * theta + params.sliderPhaseB2);
            displacementC = params.sliderOffsetC ...
                + params.sliderAmpC1 * sin(theta + params.sliderPhaseC1) ...
                + params.sliderAmpC2 * sin(2 * theta + params.sliderPhaseC2);

            sliderB(idx, :) = B(idx, :) + displacementB * dirB;
            sliderC(idx, :) = C(idx, :) + displacementC * dirC;
            connector = sliderC(idx, :) - sliderB(idx, :);
            connectorNorm = norm(connector);
            if connectorNorm < 1e-10
                invalidCount = invalidCount + 1;
                continue;
            end
            connectorUnit = connector / connectorNorm;
            connectorNormal = [-connectorUnit(2), connectorUnit(1)];
            P(idx, :) = (1 - params.traceBlend) * sliderB(idx, :) ...
                + params.traceBlend * sliderC(idx, :) ...
                + params.connectorOffset * connectorNormal;
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

        if all(validMask) && isClosedPath
            order = bestClosedCurveOrder(P, target);
            A = A(order, :);
            B = B(order, :);
            C = C(order, :);
            D = D(order, :);
            sliderB = sliderB(order, :);
            sliderC = sliderC(order, :);
            P = P(order, :);
        else
            order = 1:sampleCount;
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

        penalties = penalties + 0.01 * ( ...
            abs(params.sliderOffsetB) + abs(params.sliderOffsetC) + ...
            params.sliderAmpB1 + params.sliderAmpB2 + ...
            params.sliderAmpC1 + params.sliderAmpC2 + ...
            abs(params.connectorOffset));

        result.fitness = fitError + penalties;
        result.rmsError = fitError;
        result.penalty = penalties;
        result.path = P;
        result.A = A;
        result.B = B;
        result.C = C;
        result.D = D;
        result.sliderB = sliderB;
        result.sliderC = sliderC;
        result.order = order;
        result.isValid = invalidCount == 0 && all(validMask);
    end

    % Decode the legacy slider-enhanced four-bar chromosome into a struct.
    function params = decodeCandidate(candidate, sampleCount)
        params = struct();
        params.groundA = candidate(1:2);
        params.groundAngle = candidate(3);
        params.groundLength = candidate(4);
        params.crankLength = candidate(5);
        params.couplerLength = candidate(6);
        params.rockerLength = candidate(7);
        params.sliderAngleB = candidate(8);
        params.sliderOffsetB = candidate(9);
        params.sliderAmpB1 = candidate(10);
        params.sliderPhaseB1 = candidate(11);
        params.sliderAmpB2 = candidate(12);
        params.sliderPhaseB2 = candidate(13);
        params.sliderAngleC = candidate(14);
        params.sliderOffsetC = candidate(15);
        params.sliderAmpC1 = candidate(16);
        params.sliderPhaseC1 = candidate(17);
        params.sliderAmpC2 = candidate(18);
        params.sliderPhaseC2 = candidate(19);
        params.traceBlend = candidate(20);
        params.connectorOffset = candidate(21);
        params.thetaStart = candidate(22);
        params.thetaSpan = candidate(23);
        params.branchSign = 2 * (candidate(24) >= 0.5) - 1;
        params.directionSign = 2 * (candidate(25) >= 0.5) - 1;
        params.groundD = params.groundA + params.groundLength * [cos(params.groundAngle), sin(params.groundAngle)];
        params.inputAngles = params.thetaStart + params.directionSign * linspace(0, params.thetaSpan, sampleCount);
        params.sliderRailHalfLengthB = max(0.15 * params.couplerLength, ...
            abs(params.sliderOffsetB) + params.sliderAmpB1 + params.sliderAmpB2);
        params.sliderRailHalfLengthC = max(0.15 * params.couplerLength, ...
            abs(params.sliderOffsetC) + params.sliderAmpC1 + params.sliderAmpC2);
    end

    % Best cyclic/reversed alignment between a synthesized closed path and
    % the target closed path.
    function order = bestClosedCurveOrder(pathPoints, targetPoints)
        pointCount = size(targetPoints, 1);
        bestScore = inf;
        order = 1:pointCount;
        forward = 1:pointCount;
        reverse = pointCount:-1:1;

        for shift = 0:(pointCount - 1)
            candidateOrder = circshift(forward, [0, shift]);
            score = sqrt(mean(vecnorm(pathPoints(candidateOrder, :) - targetPoints, 2, 2).^2));
            if score < bestScore
                bestScore = score;
                order = candidateOrder;
            end

            candidateOrder = circshift(reverse, [0, shift]);
            score = sqrt(mean(vecnorm(pathPoints(candidateOrder, :) - targetPoints, 2, 2).^2));
            if score < bestScore
                bestScore = score;
                order = candidateOrder;
            end
        end
    end

    % Simple local-improvement stage applied after the GA:
    % random perturbations plus a one-coordinate-at-a-time sweep.
    function bestResult = refineCandidate(seedGenes, target, bounds, currentBest, isClosedPath, mechanismMode, allowMovingTracePoint)
        bestResult = currentBest;
        bestGenes = seedGenes;
        scales = [0.08, 0.04, 0.02, 0.01];
        range = bounds.upper - bounds.lower;

        for scale = scales
            for trial = 1:36
                candidate = bestGenes + scale * (bounds.upper - bounds.lower) .* randn(size(bestGenes));
                candidate = clampToBounds(candidate, bounds);
                trialResult = linkageEvaluateCandidate(candidate, target, isClosedPath, mechanismMode, allowMovingTracePoint);
                if trialResult.fitness + 1e-9 < bestResult.fitness
                    bestResult = trialResult;
                    bestGenes = candidate;
                end
            end

            for geneIdx = 1:numel(bestGenes)
                step = 0.35 * scale * range(geneIdx);
                if step < 1e-10
                    continue;
                end
                for direction = [-1, 1]
                    candidate = bestGenes;
                    candidate(geneIdx) = candidate(geneIdx) + direction * step;
                    candidate = clampToBounds(candidate, bounds);
                    trialResult = linkageEvaluateCandidate(candidate, target, isClosedPath, mechanismMode, allowMovingTracePoint);
                    if trialResult.fitness + 1e-9 < bestResult.fitness
                        bestResult = trialResult;
                        bestGenes = candidate;
                    end
                end
            end
        end
    end

    % Circle-circle intersection utility used by the legacy nested solver.
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

    % Tournament-selection parent chooser for the GA.
    function index = tournamentSelect(scores, tournamentSize)
        contestantCount = numel(scores);
        picks = randi(contestantCount, tournamentSize, 1);
        [~, localBest] = min(scores(picks));
        index = picks(localBest);
    end

    % Arithmetic/blend crossover that mixes two parent chromosomes.
    function [childA, childB] = blendCrossover(parentA, parentB, bounds)
        alpha = -0.15 + 1.3 * rand(1, numel(parentA));
        childA = alpha .* parentA + (1 - alpha) .* parentB;
        childB = alpha .* parentB + (1 - alpha) .* parentA;
        childA = clampToBounds(childA, bounds);
        childB = clampToBounds(childB, bounds);
    end

    % Gaussian mutation with per-gene mutation probability.
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

    % Clamp one chromosome or vector to the allowed parameter bounds.
    function values = clampToBounds(values, bounds)
        values = min(max(values, bounds.lower), bounds.upper);
    end

    % Refresh both the target-path plot and the mechanism plot.
    function refreshPlots()
        refreshTargetPlot();
        refreshLinkagePlot();
    end

    % Draw the target path, clicked points, and current best synthesized path.
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

    % Draw the best mechanism found so far together with its traced path.
    function refreshLinkagePlot()
        cla(state.linkageAxes);
        hold(state.linkageAxes, "on");

        if ~isempty(state.targetPoints)
            plot(state.linkageAxes, state.targetPoints(:, 1), state.targetPoints(:, 2), "-", ...
                "Color", [0.75 0.82 0.94], "LineWidth", 2.0, "DisplayName", "Target");
        end

        if isempty(state.bestResult)
            title(state.linkageAxes, sprintf("%s Evolution", mechanismModeToLabel(getSelectedMechanismMode())));
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

        title(state.linkageAxes, sprintf("%s Evolution | RMS error %.5f", ...
            mechanismModeToLabel(result.mechanismMode), result.rmsError));
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

    % Choose a valid animation frame when some sampled configurations failed.
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

    % Recover the input angle associated with a displayed animation frame.
    function angleValue = getResultAngleAtFrame(result, frameIndex, angleField)
        angleValue = nan;
        if ~isfield(result, "params") || ~isfield(result.params, angleField)
            return;
        end

        angleSeries = result.params.(angleField);
        if isempty(angleSeries)
            return;
        end

        sourceIndex = frameIndex;
        if isfield(result, "order") && numel(result.order) >= frameIndex
            mappedIndex = result.order(frameIndex);
            if isfinite(mappedIndex) && mappedIndex >= 1 && mappedIndex <= numel(angleSeries)
                sourceIndex = mappedIndex;
            end
        end
        angleValue = angleSeries(sourceIndex);
    end

    % Draw one frame of the current mechanism geometry for preview or final
    % animation, depending on the selected mechanism family.
    function drawMechanismFrame(result, frameIndex, emphasize)
        if nargin < 3
            emphasize = false;
        end

        if emphasize
            linkWidth = 3.0;
            pointSize = 90;
        else
            linkWidth = 2.4;
            pointSize = 70;
        end

        switch result.mechanismMode
            case 'standard_fourbar'
                A = result.A(frameIndex, :);
                B = result.B(frameIndex, :);
                C = result.C(frameIndex, :);
                D = result.D(frameIndex, :);
                P = result.path(frameIndex, :);
                if any(isnan([A, B, C, D, P]))
                    return;
                end

                theta = getResultAngleAtFrame(result, frameIndex, "inputAngles");
                traceBlend = result.params.traceBlend;
                if isfinite(theta)
                    traceBlend = min(max(result.params.traceBlend + result.params.traceBlendAmp * sin(theta + result.params.traceBlendPhase), 0), 1);
                end
                traceBase = (1 - traceBlend) * B + traceBlend * C;

                plot(state.linkageAxes, [A(1), B(1)], [A(2), B(2)], "-", "Color", [0.1 0.55 0.2], "LineWidth", linkWidth, "DisplayName", "Crank");
                plot(state.linkageAxes, [B(1), C(1)], [B(2), C(2)], "-", "Color", [0.95 0.65 0.1], "LineWidth", linkWidth, "DisplayName", "Coupler");
                plot(state.linkageAxes, [C(1), D(1)], [C(2), D(2)], "-", "Color", [0.45 0.2 0.7], "LineWidth", linkWidth, "DisplayName", "Rocker");
                plot(state.linkageAxes, [A(1), D(1)], [A(2), D(2)], "-", "Color", [0.2 0.2 0.2], "LineWidth", linkWidth, "DisplayName", "Ground");
                plot(state.linkageAxes, [traceBase(1), P(1)], [traceBase(2), P(2)], ":", "Color", [0.65 0.4 0.3], "LineWidth", 1.1, "DisplayName", "Tracing point offset");
                scatter(state.linkageAxes, [A(1), B(1), C(1), D(1)], [A(2), B(2), C(2), D(2)], pointSize, ...
                    "filled", "MarkerFaceColor", [0.16 0.16 0.16], "MarkerEdgeColor", "white", "DisplayName", "Joints");
            case {'fivebar', 'advanced_fivebar'}
                A = result.A(frameIndex, :);
                B = result.B(frameIndex, :);
                C = result.C(frameIndex, :);
                D = result.D(frameIndex, :);
                E = result.E(frameIndex, :);
                P = result.path(frameIndex, :);
                if any(isnan([A, B, C, D, E, P]))
                    return;
                end

                plot(state.linkageAxes, [A(1), D(1)], [A(2), D(2)], "-", "Color", [0.2 0.2 0.2], "LineWidth", linkWidth, "DisplayName", "Ground");
                plot(state.linkageAxes, [A(1), B(1)], [A(2), B(2)], "-", "Color", [0.1 0.55 0.2], "LineWidth", linkWidth, "DisplayName", "Left crank");
                plot(state.linkageAxes, [D(1), C(1)], [D(2), C(2)], "-", "Color", [0.45 0.2 0.7], "LineWidth", linkWidth, "DisplayName", "Right crank");
                plot(state.linkageAxes, [B(1), E(1)], [B(2), E(2)], "-", "Color", [0.95 0.65 0.1], "LineWidth", linkWidth, "DisplayName", "Left distal");
                plot(state.linkageAxes, [C(1), E(1)], [C(2), E(2)], "-", "Color", [0.2 0.55 0.8], "LineWidth", linkWidth, "DisplayName", "Right distal");
                if strcmp(result.mechanismMode, 'advanced_fivebar')
                    SL = result.sliderB(frameIndex, :);
                    SR = result.sliderC(frameIndex, :);
                    plot(state.linkageAxes, [E(1), SL(1)], [E(2), SL(2)], ":", "Color", [0.95 0.65 0.1], "LineWidth", 1.0, "DisplayName", "Left slider offset");
                    plot(state.linkageAxes, [E(1), SR(1)], [E(2), SR(2)], ":", "Color", [0.2 0.55 0.8], "LineWidth", 1.0, "DisplayName", "Right slider offset");
                    plot(state.linkageAxes, [SL(1), SR(1)], [SL(2), SR(2)], "-", "Color", [0.65 0.4 0.3], "LineWidth", 1.6, "DisplayName", "Slider connector");
                    scatter(state.linkageAxes, [SL(1), SR(1)], [SL(2), SR(2)], pointSize - 12, ...
                        "filled", "MarkerFaceColor", [0.95 0.82 0.18], "MarkerEdgeColor", [0.15 0.15 0.15], "DisplayName", "Sliders");
                else
                    theta = getResultAngleAtFrame(result, frameIndex, "leftInputAngles");
                    traceBlend = result.params.traceBlend;
                    if isfinite(theta)
                        traceBlend = min(max(result.params.traceBlend + result.params.traceBlendAmp * sin(theta + result.params.traceBlendPhase), 0), 1);
                    end
                    midpoint = 0.5 * (B + C);
                    traceBase = (1 - traceBlend) * E + traceBlend * midpoint;
                    plot(state.linkageAxes, [traceBase(1), P(1)], [traceBase(2), P(2)], ":", "Color", [0.65 0.4 0.3], "LineWidth", 1.2, "DisplayName", "Trace offset");
                end
                scatter(state.linkageAxes, [A(1), B(1), C(1), D(1), E(1)], [A(2), B(2), C(2), D(2), E(2)], pointSize, ...
                    "filled", "MarkerFaceColor", [0.16 0.16 0.16], "MarkerEdgeColor", "white", "DisplayName", "Joints");
            case {'sixbar', 'advanced_sixbar'}
                A = result.A(frameIndex, :);
                B = result.B(frameIndex, :);
                C = result.C(frameIndex, :);
                D = result.D(frameIndex, :);
                E = result.E(frameIndex, :);
                F = result.F(frameIndex, :);
                J = result.J(frameIndex, :);
                P = result.path(frameIndex, :);
                if any(isnan([A, B, C, D, E, F, J, P]))
                    return;
                end

                plot(state.linkageAxes, [A(1), B(1)], [A(2), B(2)], "-", "Color", [0.1 0.55 0.2], "LineWidth", linkWidth, "DisplayName", "Crank");
                plot(state.linkageAxes, [B(1), C(1)], [B(2), C(2)], "-", "Color", [0.95 0.65 0.1], "LineWidth", linkWidth, "DisplayName", "Coupler");
                plot(state.linkageAxes, [C(1), D(1)], [C(2), D(2)], "-", "Color", [0.45 0.2 0.7], "LineWidth", linkWidth, "DisplayName", "Rocker");
                plot(state.linkageAxes, [A(1), D(1)], [A(2), D(2)], "-", "Color", [0.2 0.2 0.2], "LineWidth", linkWidth, "DisplayName", "Ground");
                plot(state.linkageAxes, [B(1), J(1), C(1)], [B(2), J(2), C(2)], "--", "Color", [0.85 0.72 0.35], "LineWidth", 1.0, "DisplayName", "Coupler point");
                plot(state.linkageAxes, [J(1), E(1)], [J(2), E(2)], "-", "Color", [0.2 0.55 0.8], "LineWidth", linkWidth, "DisplayName", "Aux coupler");
                plot(state.linkageAxes, [F(1), E(1)], [F(2), E(2)], "-", "Color", [0.8 0.35 0.2], "LineWidth", linkWidth, "DisplayName", "Aux rocker");
                if strcmp(result.mechanismMode, 'advanced_sixbar')
                    SJ = result.sliderB(frameIndex, :);
                    SF = result.sliderC(frameIndex, :);
                    plot(state.linkageAxes, [J(1), SJ(1)], [J(2), SJ(2)], ":", "Color", [0.2 0.55 0.8], "LineWidth", 1.0, "DisplayName", "J-slider offset");
                    plot(state.linkageAxes, [F(1), SF(1)], [F(2), SF(2)], ":", "Color", [0.8 0.35 0.2], "LineWidth", 1.0, "DisplayName", "F-slider offset");
                    plot(state.linkageAxes, [SJ(1), SF(1)], [SJ(2), SF(2)], "-", "Color", [0.65 0.4 0.3], "LineWidth", 1.6, "DisplayName", "Slider connector");
                    scatter(state.linkageAxes, [SJ(1), SF(1)], [SJ(2), SF(2)], pointSize - 12, ...
                        "filled", "MarkerFaceColor", [0.95 0.82 0.18], "MarkerEdgeColor", [0.15 0.15 0.15], "DisplayName", "Sliders");
                else
                    theta = getResultAngleAtFrame(result, frameIndex, "inputAngles");
                    traceBlend = result.params.traceBlend;
                    if isfinite(theta)
                        traceBlend = min(max(result.params.traceBlend + result.params.traceBlendAmp * sin(theta + result.params.traceBlendPhase), 0), 1);
                    end
                    traceBase = (1 - traceBlend) * J + traceBlend * E;
                    plot(state.linkageAxes, [traceBase(1), P(1)], [traceBase(2), P(2)], ":", "Color", [0.6 0.5 0.35], "LineWidth", 1.1, "DisplayName", "Trace offset");
                end
                scatter(state.linkageAxes, [A(1), B(1), C(1), D(1), E(1), F(1), J(1)], [A(2), B(2), C(2), D(2), E(2), F(2), J(2)], pointSize, ...
                    "filled", "MarkerFaceColor", [0.16 0.16 0.16], "MarkerEdgeColor", "white", "DisplayName", "Joints");
            otherwise
                A = result.A(frameIndex, :);
                B = result.B(frameIndex, :);
                C = result.C(frameIndex, :);
                D = result.D(frameIndex, :);
                P = result.path(frameIndex, :);
                if any(isnan([A, B, C, D, P]))
                    return;
                end

                direction = C - B;
                directionNorm = norm(direction);
                if directionNorm < 1e-10
                    return;
                end
                ux = direction / directionNorm;
                uy = [-ux(2), ux(1)];
                railDirB = cos(result.params.sliderAngleB) * ux + sin(result.params.sliderAngleB) * uy;
                railDirC = cos(result.params.sliderAngleC) * ux + sin(result.params.sliderAngleC) * uy;
                SB = result.sliderB(frameIndex, :);
                SC = result.sliderC(frameIndex, :);
                railB = [B - result.params.sliderRailHalfLengthB * railDirB; B + result.params.sliderRailHalfLengthB * railDirB];
                railC = [C - result.params.sliderRailHalfLengthC * railDirC; C + result.params.sliderRailHalfLengthC * railDirC];

                plot(state.linkageAxes, [A(1), B(1)], [A(2), B(2)], "-", "Color", [0.1 0.55 0.2], "LineWidth", linkWidth, "DisplayName", "Crank");
                plot(state.linkageAxes, [B(1), C(1)], [B(2), C(2)], "-", "Color", [0.95 0.65 0.1], "LineWidth", linkWidth, "DisplayName", "Coupler");
                plot(state.linkageAxes, [C(1), D(1)], [C(2), D(2)], "-", "Color", [0.45 0.2 0.7], "LineWidth", linkWidth, "DisplayName", "Rocker");
                plot(state.linkageAxes, [A(1), D(1)], [A(2), D(2)], "-", "Color", [0.2 0.2 0.2], "LineWidth", linkWidth, "DisplayName", "Ground");
                plot(state.linkageAxes, railB(:, 1), railB(:, 2), "--", "Color", [0.1 0.55 0.2], "LineWidth", 1.2, "DisplayName", "Slider rail B");
                plot(state.linkageAxes, railC(:, 1), railC(:, 2), "--", "Color", [0.45 0.2 0.7], "LineWidth", 1.2, "DisplayName", "Slider rail C");
                plot(state.linkageAxes, [SB(1), SC(1)], [SB(2), SC(2)], "-", "Color", [0.65 0.4 0.3], "LineWidth", 1.6, "DisplayName", "Slider connector");
                plot(state.linkageAxes, [B(1), SB(1)], [B(2), SB(2)], ":", "Color", [0.1 0.55 0.2], "LineWidth", 1.0, "DisplayName", "Slider offset B");
                plot(state.linkageAxes, [C(1), SC(1)], [C(2), SC(2)], ":", "Color", [0.45 0.2 0.7], "LineWidth", 1.0, "DisplayName", "Slider offset C");
                if ~strcmp(result.mechanismMode, 'advanced_fourbar')
                    theta = getResultAngleAtFrame(result, frameIndex, "inputAngles");
                    traceBlend = result.params.traceBlend;
                    if isfinite(theta)
                        traceBlend = min(max(result.params.traceBlend + result.params.traceBlendAmp * sin(theta + result.params.traceBlendPhase), 0), 1);
                    end
                    traceBase = (1 - traceBlend) * SB + traceBlend * SC;
                    plot(state.linkageAxes, [traceBase(1), P(1)], [traceBase(2), P(2)], ":", ...
                        "Color", [0.65 0.4 0.3], "LineWidth", 1.1, "DisplayName", "Trace offset");
                end
                scatter(state.linkageAxes, [A(1), B(1), C(1), D(1)], [A(2), B(2), C(2), D(2)], pointSize, ...
                    "filled", "MarkerFaceColor", [0.16 0.16 0.16], "MarkerEdgeColor", "white", "DisplayName", "Joints");
                scatter(state.linkageAxes, [SB(1), SC(1)], [SB(2), SC(2)], pointSize - 10, ...
                    "filled", "MarkerFaceColor", [0.95 0.82 0.18], "MarkerEdgeColor", [0.15 0.15 0.15], "DisplayName", "Sliders");
                if strcmp(result.mechanismMode, 'advanced_fourbar')
                    bridgePoint = result.E(frameIndex, :);
                    if ~any(isnan(bridgePoint))
                        scatter(state.linkageAxes, bridgePoint(1), bridgePoint(2), pointSize - 18, ...
                            "filled", "MarkerFaceColor", [0.25 0.7 0.9], "MarkerEdgeColor", "white", "DisplayName", "Bridge point");
                    end
                end
        end

        scatter(state.linkageAxes, P(1), P(2), pointSize + 10, "filled", ...
            "MarkerFaceColor", [0.85 0.1 0.1], "MarkerEdgeColor", "white", "DisplayName", "Tracing point");
    end

    % Gather points that should influence automatic axis fitting.
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
                pts = appendResultJoints(pts, result);
            end
        elseif ~isempty(state.bestResult)
            result = state.bestResult;
            validMask = ~any(isnan(result.path), 2);
            pts = [pts; result.path(validMask, :)];
            pts = appendResultJoints(pts, result);
        end
    end

    % Add joint and slider coordinates from a result struct to a point list.
    function pts = appendResultJoints(pts, result)
        fieldList = {'A', 'B', 'C', 'D', 'E', 'F', 'J', 'sliderB', 'sliderC'};
        idx = 1;
        while idx <= numel(fieldList)
            fieldName = fieldList{idx};
            if isfield(result, fieldName)
                fieldValue = result.(fieldName);
                if ~isempty(fieldValue) && size(fieldValue, 2) == 2
                    validMask = ~any(isnan(fieldValue), 2);
                    pts = [pts; fieldValue(validMask, :)];
                end
            end
            idx = idx + 1;
        end
    end

    % Apply either the stored locked axis limits or automatic fitted limits.
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

    % Fit an axes around a point cloud with padding and a zoom factor.
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

    % Uniform zoom around the center of an axes.
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

    % Translate the current axis limits by a fraction of their span.
    function panAxis(axHandle, dxFraction, dyFraction)
        currentX = xlim(axHandle);
        currentY = ylim(axHandle);
        xShift = diff(currentX) * dxFraction;
        yShift = diff(currentY) * dyFraction;
        xlim(axHandle, currentX + xShift);
        ylim(axHandle, currentY + yShift);
    end

    % Width/height scaling helper kept for future UI adjustments.
    function scaleAxisLimits(axHandle, scaleX, scaleY)
        currentX = xlim(axHandle);
        currentY = ylim(axHandle);
        centerX = mean(currentX);
        centerY = mean(currentY);
        halfWidth = max(diff(currentX) * scaleX / 2, 0.25);
        halfHeight = max(diff(currentY) * scaleY / 2, 0.25);
        xlim(axHandle, [centerX - halfWidth, centerX + halfWidth]);
        ylim(axHandle, [centerY - halfHeight, centerY + halfHeight]);
    end

    % Save the current plot limits so they can be locked during updates.
    function captureCurrentAxesLimits()
        state.view.pathLimits = [xlim(state.pathAxes); ylim(state.pathAxes)];
        state.view.linkageLimits = [xlim(state.linkageAxes); ylim(state.linkageAxes)];
    end

    % Draw the best-fitness history over generations and retry attempts.
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

    % Play the final multi-cycle mechanism animation after a run completes.
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
                title(state.linkageAxes, sprintf("%s Final Animation | cycle %d / %d | frame %d / %d", ...
                    mechanismModeToLabel(result.mechanismMode), cycle, cycleCount, idx, numel(validFrames)));
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

    % Enable/disable run controls while a solve is active.
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

    % Update the small status label in the lower-left panel.
    function setStatus(statusText)
        if isfield(state, "controls") && isfield(state.controls, "statusLabel") && isgraphics(state.controls.statusLabel)
            set(state.controls.statusLabel, "String", sprintf("Status: %s", statusText));
            drawnow limitrate;
        end
    end

    % Parse an integer from a GUI edit box, restoring the default on failure.
    function value = readInteger(handleObj, defaultValue)
        value = round(str2double(get(handleObj, "String")));
        if ~isfinite(value)
            value = defaultValue;
            set(handleObj, "String", num2str(defaultValue));
        end
    end

    % Parse a floating-point value from a GUI edit box.
    function value = readDouble(handleObj, defaultValue)
        value = str2double(get(handleObj, "String"));
        if ~isfinite(value)
            value = defaultValue;
            set(handleObj, "String", num2str(defaultValue));
        end
    end

    % Append a timestamped message to the event log listbox.
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

    % Stop any active run and close the figure window.
    function onCloseFigure(~, ~)
        state.stopRequested = true;
        delete(state.fig);
    end
end

%--------------------------------------------------------------------------
% File-level mechanism evaluators
%--------------------------------------------------------------------------
% The nested app code above handles UI, plotting, and the GA loop.
% The functions below are pure-ish evaluators: they decode a chromosome,
% compute the mechanism kinematics over one input cycle, compare the traced
% path against the target, and return a result struct.

% Dispatch a chromosome to the correct evaluator for the selected
% mechanism family.
function result = linkageEvaluateCandidate(candidate, target, isClosedPath, mechanismMode, allowMovingTracePoint)
if nargin < 5
    allowMovingTracePoint = true;
end

switch mechanismMode
    case 'standard_fourbar'
        result = standardFourbarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint);
    case 'advanced_fourbar'
        result = advancedFourbarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint);
    case {'slider_fourbar', 'fourbar'}
        result = fourbarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint);
        mechanismMode = 'slider_fourbar';
    case 'fivebar'
        result = fivebarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint);
    case 'advanced_fivebar'
        result = advancedFivebarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint);
    case 'sixbar'
        result = sixbarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint);
    case 'advanced_sixbar'
        result = advancedSixbarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint);
    otherwise
        result = standardFourbarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint);
        mechanismMode = 'standard_fourbar';
end

result = finalizeLinkageResult(result, target, mechanismMode);
end

% Make sure every result struct has the same standard fields so the
% plotting code can treat different mechanisms uniformly.
function result = finalizeLinkageResult(result, target, mechanismMode)
sampleCount = size(target, 1);
fieldList = {'A', 'B', 'C', 'D', 'E', 'F', 'J', 'sliderB', 'sliderC'};
idx = 1;
while idx <= numel(fieldList)
    fieldName = fieldList{idx};
    if ~isfield(result, fieldName)
        result.(fieldName) = nan(sampleCount, 2);
    end
    idx = idx + 1;
end

if ~isfield(result, 'order')
    result.order = 1:sampleCount;
end

result.mechanismMode = mechanismMode;
if isfield(result, 'params')
    result.params.mode = mechanismMode;
end
end

% Create a standard empty result struct before one evaluator fills in the
% mechanism-specific coordinates and fitness values.
function result = linkageResultTemplate(candidate, target, params)
result = struct();
result.fitness = inf;
result.rmsError = inf;
result.penalty = inf;
result.genes = candidate;
result.params = params;
result.path = nan(size(target));
result.A = nan(size(target));
result.B = nan(size(target));
result.C = nan(size(target));
result.D = nan(size(target));
result.E = nan(size(target));
result.F = nan(size(target));
result.J = nan(size(target));
result.sliderB = nan(size(target));
result.sliderC = nan(size(target));
result.order = 1:size(target, 1);
result.isValid = false;
end

% Clamp a scalar or vector to the interval [0, 1].
function value = clampUnitInterval(value)
value = min(max(value, 0), 1);
end

% Enforce the GUI's fixed-vs-moving tracing-point setting by zeroing the
% trace-motion amplitudes when fixed-trace mode is selected.
function params = applyTraceMotionMode(params, allowMovingTracePoint)
if nargin < 2
    allowMovingTracePoint = true;
end

if allowMovingTracePoint
    params.tracePointMode = "moving";
    return;
end

zeroFieldList = {'traceBlendAmp', 'offsetAmp', 'traceOffsetAmp', 'bridgeLongAmp', 'bridgeNormalAmp'};
for fieldIdx = 1:numel(zeroFieldList)
    fieldName = zeroFieldList{fieldIdx};
    if isfield(params, fieldName)
        params.(fieldName) = 0;
    end
end
params.tracePointMode = "fixed";
end

% Evaluate a classic 4-bar linkage with a coupler tracing point.
%
% The tracing point is parameterized by:
% - a blend along the coupler from joint B to joint C
% - a normal offset from the coupler line
% - optional time-varying blend and offset amplitudes
function result = standardFourbarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint)
if nargin < 4
    allowMovingTracePoint = true;
end
params = standardFourbarDecodeCandidate(candidate, size(target, 1));
params = applyTraceMotionMode(params, allowMovingTracePoint);
result = linkageResultTemplate(candidate, target, params);

sampleCount = numel(params.inputAngles);
A = repmat(params.groundA, sampleCount, 1);
D = repmat(params.groundD, sampleCount, 1);
B = nan(sampleCount, 2);
C = nan(sampleCount, 2);
P = nan(sampleCount, 2);

invalidCount = 0;
for idx = 1:sampleCount
    theta = params.inputAngles(idx);
    B(idx, :) = params.groundA + params.crankLength * [cos(theta), sin(theta)];
    [pointC, isValid] = fourbarCircleIntersection(B(idx, :), params.couplerLength, params.groundD, params.rockerLength, params.branchSign);
    if ~isValid
        invalidCount = invalidCount + 1;
        continue;
    end

    C(idx, :) = pointC;
    couplerDirection = pointC - B(idx, :);
    couplerNorm = norm(couplerDirection);
    if couplerNorm < 1e-10
        invalidCount = invalidCount + 1;
        continue;
    end

    couplerUnit = couplerDirection / couplerNorm;
    couplerNormal = [-couplerUnit(2), couplerUnit(1)];
    traceBlend = clampUnitInterval(params.traceBlend + params.traceBlendAmp * sin(theta + params.traceBlendPhase));
    connectorOffset = params.connectorOffset + params.offsetAmp * sin(2 * theta + params.offsetPhase);
    P(idx, :) = (1 - traceBlend) * B(idx, :) + traceBlend * pointC + connectorOffset * couplerNormal;
end

[fitness, rmsError, penalties, order, validMask] = linkageFitness(P, target, isClosedPath, invalidCount);
if all(validMask) && isClosedPath
    A = A(order, :);
    B = B(order, :);
    C = C(order, :);
    D = D(order, :);
    P = P(order, :);
end

penalties = penalties + 0.008 * (abs(params.connectorOffset) + 0.35 * params.offsetAmp + 0.15 * params.traceBlendAmp);
fitness = rmsError + penalties;

result.fitness = fitness;
result.rmsError = rmsError;
result.penalty = penalties;
result.path = P;
result.A = A;
result.B = B;
result.C = C;
result.D = D;
result.order = order;
result.isValid = invalidCount == 0 && all(validMask);
end

% Decode the standard 4-bar chromosome into named parameters.
function params = standardFourbarDecodeCandidate(candidate, sampleCount)
params = struct();
params.groundA = candidate(1:2);
params.groundAngle = candidate(3);
params.groundLength = candidate(4);
params.crankLength = candidate(5);
params.couplerLength = candidate(6);
params.rockerLength = candidate(7);
params.traceBlend = candidate(8);
params.connectorOffset = candidate(9);
params.traceBlendAmp = candidate(10);
params.traceBlendPhase = candidate(11);
params.offsetAmp = candidate(12);
params.offsetPhase = candidate(13);
params.thetaStart = candidate(14);
params.thetaSpan = candidate(15);
params.branchSign = 2 * (candidate(16) >= 0.5) - 1;
params.directionSign = 2 * (candidate(17) >= 0.5) - 1;
params.groundD = params.groundA + params.groundLength * [cos(params.groundAngle), sin(params.groundAngle)];
params.inputAngles = params.thetaStart + params.directionSign * linspace(0, params.thetaSpan, sampleCount);
end

% Evaluate the multi-slider 4-bar variant.
%
% This mechanism adds two slider rails attached to the main 4-bar plus a
% dynamic bridge point between slider carriages for richer path shapes.
function result = advancedFourbarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint)
if nargin < 4
    allowMovingTracePoint = true;
end
params = advancedFourbarDecodeCandidate(candidate, size(target, 1));
params = applyTraceMotionMode(params, allowMovingTracePoint);
result = linkageResultTemplate(candidate, target, params);

sampleCount = numel(params.inputAngles);
A = repmat(params.groundA, sampleCount, 1);
D = repmat(params.groundD, sampleCount, 1);
B = nan(sampleCount, 2);
C = nan(sampleCount, 2);
sliderB = nan(sampleCount, 2);
sliderC = nan(sampleCount, 2);
bridgePoints = nan(sampleCount, 2);
P = nan(sampleCount, 2);

invalidCount = 0;
for idx = 1:sampleCount
    theta = params.inputAngles(idx);
    B(idx, :) = params.groundA + params.crankLength * [cos(theta), sin(theta)];
    [pointC, isValid] = fourbarCircleIntersection(B(idx, :), params.couplerLength, params.groundD, params.rockerLength, params.branchSign);
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
    dirB = cos(params.sliderAngleB) * ux + sin(params.sliderAngleB) * uy;
    dirC = cos(params.sliderAngleC) * ux + sin(params.sliderAngleC) * uy;
    displacementB = params.sliderOffsetB ...
        + params.sliderAmpB1 * sin(theta + params.sliderPhaseB1) ...
        + params.sliderAmpB2 * sin(2 * theta + params.sliderPhaseB2) ...
        + params.sliderAmpB3 * sin(3 * theta + params.sliderPhaseB3);
    displacementC = params.sliderOffsetC ...
        + params.sliderAmpC1 * sin(theta + params.sliderPhaseC1) ...
        + params.sliderAmpC2 * sin(2 * theta + params.sliderPhaseC2) ...
        + params.sliderAmpC3 * sin(3 * theta + params.sliderPhaseC3);

    sliderB(idx, :) = B(idx, :) + displacementB * dirB;
    sliderC(idx, :) = C(idx, :) + displacementC * dirC;
    connector = sliderC(idx, :) - sliderB(idx, :);
    connectorNorm = norm(connector);
    if connectorNorm < 1e-10
        invalidCount = invalidCount + 1;
        continue;
    end

    connectorUnit = connector / connectorNorm;
    connectorNormal = [-connectorUnit(2), connectorUnit(1)];
    traceBlend = clampUnitInterval(params.traceBlend + params.traceBlendAmp * sin(theta + params.traceBlendPhase));
    connectorOffset = params.connectorOffset + params.offsetAmp * sin(2 * theta + params.offsetPhase);
    coreBase = (1 - traceBlend) * sliderB(idx, :) + traceBlend * sliderC(idx, :);
    dynamicBridge = params.bridgeBlend * ( ...
        params.bridgeLongAmp * sin(theta + params.bridgeLongPhase) * connectorUnit + ...
        params.bridgeNormalAmp * sin(2 * theta + params.bridgeNormalPhase) * connectorNormal);
    bridgePoints(idx, :) = coreBase + dynamicBridge;
    P(idx, :) = bridgePoints(idx, :) + connectorOffset * connectorNormal;
end

[fitness, rmsError, penalties, order, validMask] = linkageFitness(P, target, isClosedPath, invalidCount);
if all(validMask) && isClosedPath
    A = A(order, :);
    B = B(order, :);
    C = C(order, :);
    D = D(order, :);
    sliderB = sliderB(order, :);
    sliderC = sliderC(order, :);
    bridgePoints = bridgePoints(order, :);
    P = P(order, :);
end

penalties = penalties + 0.01 * ( ...
    abs(params.sliderOffsetB) + abs(params.sliderOffsetC) + ...
    params.sliderAmpB1 + params.sliderAmpB2 + params.sliderAmpB3 + ...
    params.sliderAmpC1 + params.sliderAmpC2 + params.sliderAmpC3 + ...
    params.bridgeBlend * (params.bridgeLongAmp + params.bridgeNormalAmp) + ...
    abs(params.connectorOffset) + 0.35 * params.offsetAmp + 0.15 * params.traceBlendAmp);
fitness = rmsError + penalties;

result.fitness = fitness;
result.rmsError = rmsError;
result.penalty = penalties;
result.path = P;
result.A = A;
result.B = B;
result.C = C;
result.D = D;
result.E = bridgePoints;
result.sliderB = sliderB;
result.sliderC = sliderC;
result.order = order;
result.isValid = invalidCount == 0 && all(validMask);
end

% Decode the advanced 4-bar chromosome.
function params = advancedFourbarDecodeCandidate(candidate, sampleCount)
params = fourbarDecodeCandidate(candidate(1:29), sampleCount);
params.sliderAmpB3 = candidate(30);
params.sliderPhaseB3 = candidate(31);
params.sliderAmpC3 = candidate(32);
params.sliderPhaseC3 = candidate(33);
params.bridgeBlend = candidate(34);
params.bridgeLongAmp = candidate(35);
params.bridgeLongPhase = candidate(36);
params.bridgeNormalAmp = candidate(37);
params.bridgeNormalPhase = candidate(38);
params.sliderRailHalfLengthB = max(0.18 * params.couplerLength, ...
    abs(params.sliderOffsetB) + params.sliderAmpB1 + params.sliderAmpB2 + params.sliderAmpB3);
params.sliderRailHalfLengthC = max(0.18 * params.couplerLength, ...
    abs(params.sliderOffsetC) + params.sliderAmpC1 + params.sliderAmpC2 + params.sliderAmpC3);
end

% Evaluate a planar 5-bar linkage with a tracer defined relative to the
% distal-joint closure point and the midpoint of the crank endpoints.
function result = fivebarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint)
if nargin < 4
    allowMovingTracePoint = true;
end
params = fivebarDecodeCandidate(candidate, size(target, 1));
params = applyTraceMotionMode(params, allowMovingTracePoint);
result = linkageResultTemplate(candidate, target, params);

sampleCount = numel(params.leftInputAngles);
A = repmat(params.groundA, sampleCount, 1);
D = repmat(params.groundD, sampleCount, 1);
B = nan(sampleCount, 2);
C = nan(sampleCount, 2);
E = nan(sampleCount, 2);
P = nan(sampleCount, 2);

invalidCount = 0;
for idx = 1:sampleCount
    theta = params.leftInputAngles(idx);
    B(idx, :) = params.groundA + params.leftCrankLength * [cos(params.leftInputAngles(idx)), sin(params.leftInputAngles(idx))];
    C(idx, :) = params.groundD + params.rightCrankLength * [cos(params.rightInputAngles(idx)), sin(params.rightInputAngles(idx))];

    [pointE, isValid] = fourbarCircleIntersection(B(idx, :), params.leftDistalLength, C(idx, :), params.rightDistalLength, params.branchSign);
    if ~isValid
        invalidCount = invalidCount + 1;
        continue;
    end

    E(idx, :) = pointE;
    midpoint = 0.5 * (B(idx, :) + C(idx, :));
    reference = pointE - midpoint;
    if norm(reference) < 1e-10
        reference = C(idx, :) - B(idx, :);
    end
    referenceNorm = norm(reference);
    if referenceNorm < 1e-10
        invalidCount = invalidCount + 1;
        continue;
    end

    unit = reference / referenceNorm;
    normal = [-unit(2), unit(1)];
    traceBlend = clampUnitInterval(params.traceBlend + params.traceBlendAmp * sin(theta + params.traceBlendPhase));
    connectorOffset = params.connectorOffset + params.offsetAmp * sin(2 * theta + params.offsetPhase);
    P(idx, :) = (1 - traceBlend) * pointE + traceBlend * midpoint + connectorOffset * normal;
end

[fitness, rmsError, penalties, order, validMask] = linkageFitness(P, target, isClosedPath, invalidCount);
if all(validMask) && isClosedPath
    A = A(order, :);
    B = B(order, :);
    C = C(order, :);
    D = D(order, :);
    E = E(order, :);
    P = P(order, :);
end

penalties = penalties + 0.008 * (abs(params.connectorOffset) + 0.35 * params.offsetAmp + 0.15 * params.traceBlendAmp) ...
    + 0.01 * (0.4 * abs(params.phaseOffset) + abs(params.crankRatio - 1));
fitness = rmsError + penalties;

result.fitness = fitness;
result.rmsError = rmsError;
result.penalty = penalties;
result.path = P;
result.A = A;
result.B = B;
result.C = C;
result.D = D;
result.E = E;
result.order = order;
result.isValid = invalidCount == 0 && all(validMask);
end

% Evaluate the slider-enhanced 5-bar mechanism.
function result = advancedFivebarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint)
if nargin < 4
    allowMovingTracePoint = true;
end
params = advancedFivebarDecodeCandidate(candidate, size(target, 1));
params = applyTraceMotionMode(params, allowMovingTracePoint);
result = linkageResultTemplate(candidate, target, params);

sampleCount = numel(params.leftInputAngles);
A = repmat(params.groundA, sampleCount, 1);
D = repmat(params.groundD, sampleCount, 1);
B = nan(sampleCount, 2);
C = nan(sampleCount, 2);
E = nan(sampleCount, 2);
sliderL = nan(sampleCount, 2);
sliderR = nan(sampleCount, 2);
P = nan(sampleCount, 2);

invalidCount = 0;
for idx = 1:sampleCount
    theta = params.leftInputAngles(idx);
    B(idx, :) = params.groundA + params.leftCrankLength * [cos(params.leftInputAngles(idx)), sin(params.leftInputAngles(idx))];
    C(idx, :) = params.groundD + params.rightCrankLength * [cos(params.rightInputAngles(idx)), sin(params.rightInputAngles(idx))];

    [pointE, isValid] = fourbarCircleIntersection(B(idx, :), params.leftDistalLength, C(idx, :), params.rightDistalLength, params.branchSign);
    if ~isValid
        invalidCount = invalidCount + 1;
        continue;
    end

    E(idx, :) = pointE;
    leftVec = pointE - B(idx, :);
    rightVec = pointE - C(idx, :);
    leftNorm = norm(leftVec);
    rightNorm = norm(rightVec);
    if leftNorm < 1e-10 || rightNorm < 1e-10
        invalidCount = invalidCount + 1;
        continue;
    end

    uL = leftVec / leftNorm;
    nL = [-uL(2), uL(1)];
    uR = rightVec / rightNorm;
    nR = [-uR(2), uR(1)];
    dirL = cos(params.leftSliderAngle) * uL + sin(params.leftSliderAngle) * nL;
    dirR = cos(params.rightSliderAngle) * uR + sin(params.rightSliderAngle) * nR;

    sliderL(idx, :) = B(idx, :) + params.leftSliderBlend * leftVec + ...
        params.leftSliderAmp * sin(theta + params.leftSliderPhase) * dirL;
    sliderR(idx, :) = C(idx, :) + params.rightSliderBlend * rightVec + ...
        params.rightSliderAmp * sin(theta + params.rightSliderPhase) * dirR;

    connector = sliderR(idx, :) - sliderL(idx, :);
    connectorNorm = norm(connector);
    if connectorNorm < 1e-10
        invalidCount = invalidCount + 1;
        continue;
    end

    connectorUnit = connector / connectorNorm;
    connectorNormal = [-connectorUnit(2), connectorUnit(1)];
    bridgeBase = (1 - params.bridgeBlend) * sliderL(idx, :) + params.bridgeBlend * sliderR(idx, :);
    P(idx, :) = bridgeBase ...
        + params.bridgeLongAmp * sin(theta + params.bridgeLongPhase) * connectorUnit ...
        + params.bridgeNormalAmp * sin(2 * theta + params.bridgeNormalPhase) * connectorNormal;
end

[fitness, rmsError, penalties, order, validMask] = linkageFitness(P, target, isClosedPath, invalidCount);
if all(validMask) && isClosedPath
    A = A(order, :);
    B = B(order, :);
    C = C(order, :);
    D = D(order, :);
    E = E(order, :);
    sliderL = sliderL(order, :);
    sliderR = sliderR(order, :);
    P = P(order, :);
end

penalties = penalties + 0.01 * ( ...
    params.leftSliderAmp + params.rightSliderAmp + ...
    params.bridgeLongAmp + params.bridgeNormalAmp + ...
    0.35 * abs(params.phaseOffset) + abs(params.crankRatio - 1));
fitness = rmsError + penalties;

result.fitness = fitness;
result.rmsError = rmsError;
result.penalty = penalties;
result.path = P;
result.A = A;
result.B = B;
result.C = C;
result.D = D;
result.E = E;
result.sliderB = sliderL;
result.sliderC = sliderR;
result.order = order;
result.isValid = invalidCount == 0 && all(validMask);
end

% Decode the advanced 5-bar chromosome.
function params = advancedFivebarDecodeCandidate(candidate, sampleCount)
params = struct();
params.groundA = candidate(1:2);
params.groundAngle = candidate(3);
params.groundLength = candidate(4);
params.leftCrankLength = candidate(5);
params.leftDistalLength = candidate(6);
params.rightCrankLength = candidate(7);
params.rightDistalLength = candidate(8);
params.phaseOffset = candidate(9);
params.crankRatio = candidate(10);
params.leftSliderBlend = candidate(11);
params.leftSliderAngle = candidate(12);
params.leftSliderAmp = candidate(13);
params.leftSliderPhase = candidate(14);
params.rightSliderBlend = candidate(15);
params.rightSliderAngle = candidate(16);
params.rightSliderAmp = candidate(17);
params.rightSliderPhase = candidate(18);
params.bridgeBlend = candidate(19);
params.bridgeLongAmp = candidate(20);
params.bridgeLongPhase = candidate(21);
params.bridgeNormalAmp = candidate(22);
params.bridgeNormalPhase = candidate(23);
params.thetaStart = candidate(24);
params.thetaSpan = candidate(25);
params.branchSign = 2 * (candidate(26) >= 0.5) - 1;
params.directionSign = 2 * (candidate(27) >= 0.5) - 1;
params.groundD = params.groundA + params.groundLength * [cos(params.groundAngle), sin(params.groundAngle)];
baseSweep = linspace(0, params.thetaSpan, sampleCount);
params.leftInputAngles = params.thetaStart + params.directionSign * baseSweep;
params.rightInputAngles = params.thetaStart + params.phaseOffset + params.directionSign * params.crankRatio * baseSweep;
end

% Decode the standard 5-bar chromosome.
function params = fivebarDecodeCandidate(candidate, sampleCount)
params = struct();
params.groundA = candidate(1:2);
params.groundAngle = candidate(3);
params.groundLength = candidate(4);
params.leftCrankLength = candidate(5);
params.leftDistalLength = candidate(6);
params.rightCrankLength = candidate(7);
params.rightDistalLength = candidate(8);
params.phaseOffset = candidate(9);
params.crankRatio = candidate(10);
params.traceBlend = candidate(11);
params.connectorOffset = candidate(12);
params.traceBlendAmp = candidate(13);
params.traceBlendPhase = candidate(14);
params.offsetAmp = candidate(15);
params.offsetPhase = candidate(16);
params.thetaStart = candidate(17);
params.thetaSpan = candidate(18);
params.branchSign = 2 * (candidate(19) >= 0.5) - 1;
params.directionSign = 2 * (candidate(20) >= 0.5) - 1;
params.groundD = params.groundA + params.groundLength * [cos(params.groundAngle), sin(params.groundAngle)];
baseSweep = linspace(0, params.thetaSpan, sampleCount);
params.leftInputAngles = params.thetaStart + params.directionSign * baseSweep;
params.rightInputAngles = params.thetaStart + params.phaseOffset + params.directionSign * params.crankRatio * baseSweep;
end

% Evaluate a 6-bar Stephenson-style mechanism built from a base 4-bar plus
% an auxiliary loop attached to a point on the main coupler.
function result = sixbarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint)
if nargin < 4
    allowMovingTracePoint = true;
end
params = sixbarDecodeCandidate(candidate, size(target, 1));
params = applyTraceMotionMode(params, allowMovingTracePoint);
result = linkageResultTemplate(candidate, target, params);

sampleCount = numel(params.inputAngles);
A = repmat(params.groundA, sampleCount, 1);
D = repmat(params.groundD, sampleCount, 1);
F = repmat(params.auxGroundPivot, sampleCount, 1);
B = nan(sampleCount, 2);
C = nan(sampleCount, 2);
J = nan(sampleCount, 2);
E = nan(sampleCount, 2);
P = nan(sampleCount, 2);

invalidCount = 0;
for idx = 1:sampleCount
    theta = params.inputAngles(idx);
    B(idx, :) = params.groundA + params.crankLength * [cos(theta), sin(theta)];
    [pointC, isValidBase] = fourbarCircleIntersection(B(idx, :), params.couplerLength, params.groundD, params.rockerLength, params.branchSign);
    if ~isValidBase
        invalidCount = invalidCount + 1;
        continue;
    end

    C(idx, :) = pointC;
    couplerVector = pointC - B(idx, :);
    couplerNorm = norm(couplerVector);
    if couplerNorm < 1e-10
        invalidCount = invalidCount + 1;
        continue;
    end

    couplerUnit = couplerVector / couplerNorm;
    couplerNormal = [-couplerUnit(2), couplerUnit(1)];
    J(idx, :) = (1 - params.couplerBlend) * B(idx, :) + params.couplerBlend * pointC + params.couplerOffset * couplerNormal;

    [pointE, isValidAux] = fourbarCircleIntersection(J(idx, :), params.auxCouplerLength, params.auxGroundPivot, params.auxRockerLength, params.auxBranchSign);
    if ~isValidAux
        invalidCount = invalidCount + 1;
        continue;
    end

    E(idx, :) = pointE;
    traceVector = pointE - J(idx, :);
    traceNorm = norm(traceVector);
    if traceNorm < 1e-10
        invalidCount = invalidCount + 1;
        continue;
    end

    traceUnit = traceVector / traceNorm;
    traceNormal = [-traceUnit(2), traceUnit(1)];
    traceBlend = clampUnitInterval(params.traceBlend + params.traceBlendAmp * sin(theta + params.traceBlendPhase));
    traceOffset = params.traceOffset + params.traceOffsetAmp * sin(2 * theta + params.traceOffsetPhase);
    P(idx, :) = (1 - traceBlend) * J(idx, :) + traceBlend * pointE + traceOffset * traceNormal;
end

[fitness, rmsError, penalties, order, validMask] = linkageFitness(P, target, isClosedPath, invalidCount);
if all(validMask) && isClosedPath
    A = A(order, :);
    B = B(order, :);
    C = C(order, :);
    D = D(order, :);
    E = E(order, :);
    F = F(order, :);
    J = J(order, :);
    P = P(order, :);
end

penalties = penalties + 0.008 * ( ...
    abs(params.couplerOffset) + abs(params.auxGroundOffset) + abs(params.traceOffset) + ...
    0.40 * params.traceOffsetAmp + 0.15 * params.traceBlendAmp);
fitness = rmsError + penalties;

result.fitness = fitness;
result.rmsError = rmsError;
result.penalty = penalties;
result.path = P;
result.A = A;
result.B = B;
result.C = C;
result.D = D;
result.E = E;
result.F = F;
result.J = J;
result.order = order;
result.isValid = invalidCount == 0 && all(validMask);
end

% Decode the standard 6-bar chromosome.
function params = sixbarDecodeCandidate(candidate, sampleCount)
params = struct();
params.groundA = candidate(1:2);
params.groundAngle = candidate(3);
params.groundLength = candidate(4);
params.crankLength = candidate(5);
params.couplerLength = candidate(6);
params.rockerLength = candidate(7);
params.auxGroundBlend = candidate(8);
params.auxGroundOffset = candidate(9);
params.couplerBlend = candidate(10);
params.couplerOffset = candidate(11);
params.auxCouplerLength = candidate(12);
params.auxRockerLength = candidate(13);
params.traceBlend = candidate(14);
params.traceOffset = candidate(15);
params.traceBlendAmp = candidate(16);
params.traceBlendPhase = candidate(17);
params.traceOffsetAmp = candidate(18);
params.traceOffsetPhase = candidate(19);
params.thetaStart = candidate(20);
params.thetaSpan = candidate(21);
params.branchSign = 2 * (candidate(22) >= 0.5) - 1;
params.auxBranchSign = 2 * (candidate(23) >= 0.5) - 1;
params.directionSign = 2 * (candidate(24) >= 0.5) - 1;
params.groundD = params.groundA + params.groundLength * [cos(params.groundAngle), sin(params.groundAngle)];
groundUnit = (params.groundD - params.groundA) / max(params.groundLength, 1e-12);
groundNormal = [-groundUnit(2), groundUnit(1)];
params.auxGroundPivot = (1 - params.auxGroundBlend) * params.groundA + params.auxGroundBlend * params.groundD + params.auxGroundOffset * groundNormal;
params.inputAngles = params.thetaStart + params.directionSign * linspace(0, params.thetaSpan, sampleCount);
end

% Evaluate the slider-enhanced 6-bar mechanism.
function result = advancedSixbarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint)
if nargin < 4
    allowMovingTracePoint = true;
end
params = advancedSixbarDecodeCandidate(candidate, size(target, 1));
params = applyTraceMotionMode(params, allowMovingTracePoint);
result = linkageResultTemplate(candidate, target, params);

sampleCount = numel(params.inputAngles);
A = repmat(params.groundA, sampleCount, 1);
D = repmat(params.groundD, sampleCount, 1);
F = repmat(params.auxGroundPivot, sampleCount, 1);
B = nan(sampleCount, 2);
C = nan(sampleCount, 2);
J = nan(sampleCount, 2);
E = nan(sampleCount, 2);
sliderJ = nan(sampleCount, 2);
sliderF = nan(sampleCount, 2);
P = nan(sampleCount, 2);

invalidCount = 0;
for idx = 1:sampleCount
    theta = params.inputAngles(idx);
    B(idx, :) = params.groundA + params.crankLength * [cos(theta), sin(theta)];
    [pointC, isValidBase] = fourbarCircleIntersection(B(idx, :), params.couplerLength, params.groundD, params.rockerLength, params.branchSign);
    if ~isValidBase
        invalidCount = invalidCount + 1;
        continue;
    end

    C(idx, :) = pointC;
    couplerVector = pointC - B(idx, :);
    couplerNorm = norm(couplerVector);
    if couplerNorm < 1e-10
        invalidCount = invalidCount + 1;
        continue;
    end

    couplerUnit = couplerVector / couplerNorm;
    couplerNormal = [-couplerUnit(2), couplerUnit(1)];
    J(idx, :) = (1 - params.couplerBlend) * B(idx, :) + params.couplerBlend * pointC + params.couplerOffset * couplerNormal;

    [pointE, isValidAux] = fourbarCircleIntersection(J(idx, :), params.auxCouplerLength, params.auxGroundPivot, params.auxRockerLength, params.auxBranchSign);
    if ~isValidAux
        invalidCount = invalidCount + 1;
        continue;
    end

    E(idx, :) = pointE;
    jVec = pointE - J(idx, :);
    fVec = pointE - params.auxGroundPivot;
    jNorm = norm(jVec);
    fNorm = norm(fVec);
    if jNorm < 1e-10 || fNorm < 1e-10
        invalidCount = invalidCount + 1;
        continue;
    end

    uJ = jVec / jNorm;
    nJ = [-uJ(2), uJ(1)];
    uF = fVec / fNorm;
    nF = [-uF(2), uF(1)];
    dirJ = cos(params.sliderJAngle) * uJ + sin(params.sliderJAngle) * nJ;
    dirF = cos(params.sliderFAngle) * uF + sin(params.sliderFAngle) * nF;

    sliderJ(idx, :) = J(idx, :) + params.sliderJBlend * jVec + ...
        params.sliderJAmp * sin(theta + params.sliderJPhase) * dirJ;
    sliderF(idx, :) = params.auxGroundPivot + params.sliderFBlend * fVec + ...
        params.sliderFAmp * sin(theta + params.sliderFPhase) * dirF;

    connector = sliderF(idx, :) - sliderJ(idx, :);
    connectorNorm = norm(connector);
    if connectorNorm < 1e-10
        invalidCount = invalidCount + 1;
        continue;
    end

    connectorUnit = connector / connectorNorm;
    connectorNormal = [-connectorUnit(2), connectorUnit(1)];
    bridgeBase = (1 - params.bridgeBlend) * sliderJ(idx, :) + params.bridgeBlend * sliderF(idx, :);
    P(idx, :) = bridgeBase ...
        + params.bridgeLongAmp * sin(theta + params.bridgeLongPhase) * connectorUnit ...
        + params.bridgeNormalAmp * sin(2 * theta + params.bridgeNormalPhase) * connectorNormal;
end

[fitness, rmsError, penalties, order, validMask] = linkageFitness(P, target, isClosedPath, invalidCount);
if all(validMask) && isClosedPath
    A = A(order, :);
    B = B(order, :);
    C = C(order, :);
    D = D(order, :);
    E = E(order, :);
    F = F(order, :);
    J = J(order, :);
    sliderJ = sliderJ(order, :);
    sliderF = sliderF(order, :);
    P = P(order, :);
end

penalties = penalties + 0.01 * ( ...
    abs(params.couplerOffset) + abs(params.auxGroundOffset) + ...
    params.sliderJAmp + params.sliderFAmp + ...
    params.bridgeLongAmp + params.bridgeNormalAmp);
fitness = rmsError + penalties;

result.fitness = fitness;
result.rmsError = rmsError;
result.penalty = penalties;
result.path = P;
result.A = A;
result.B = B;
result.C = C;
result.D = D;
result.E = E;
result.F = F;
result.J = J;
result.sliderB = sliderJ;
result.sliderC = sliderF;
result.order = order;
result.isValid = invalidCount == 0 && all(validMask);
end

% Decode the advanced 6-bar chromosome.
function params = advancedSixbarDecodeCandidate(candidate, sampleCount)
params = struct();
params.groundA = candidate(1:2);
params.groundAngle = candidate(3);
params.groundLength = candidate(4);
params.crankLength = candidate(5);
params.couplerLength = candidate(6);
params.rockerLength = candidate(7);
params.auxGroundBlend = candidate(8);
params.auxGroundOffset = candidate(9);
params.couplerBlend = candidate(10);
params.couplerOffset = candidate(11);
params.auxCouplerLength = candidate(12);
params.auxRockerLength = candidate(13);
params.sliderJBlend = candidate(14);
params.sliderJAngle = candidate(15);
params.sliderJAmp = candidate(16);
params.sliderJPhase = candidate(17);
params.sliderFBlend = candidate(18);
params.sliderFAngle = candidate(19);
params.sliderFAmp = candidate(20);
params.sliderFPhase = candidate(21);
params.bridgeBlend = candidate(22);
params.bridgeLongAmp = candidate(23);
params.bridgeLongPhase = candidate(24);
params.bridgeNormalAmp = candidate(25);
params.bridgeNormalPhase = candidate(26);
params.thetaStart = candidate(27);
params.thetaSpan = candidate(28);
params.branchSign = 2 * (candidate(29) >= 0.5) - 1;
params.auxBranchSign = 2 * (candidate(30) >= 0.5) - 1;
params.directionSign = 2 * (candidate(31) >= 0.5) - 1;
params.groundD = params.groundA + params.groundLength * [cos(params.groundAngle), sin(params.groundAngle)];
groundUnit = (params.groundD - params.groundA) / max(params.groundLength, 1e-12);
groundNormal = [-groundUnit(2), groundUnit(1)];
params.auxGroundPivot = (1 - params.auxGroundBlend) * params.groundA + params.auxGroundBlend * params.groundD + params.auxGroundOffset * groundNormal;
params.inputAngles = params.thetaStart + params.directionSign * linspace(0, params.thetaSpan, sampleCount);
end

% Shared path-comparison objective function.
%
% Fitness = RMS path error + penalties for invalid poses, missing points,
% and excessive path roughness. Closed paths are allowed to cyclically
% shift (and reverse) to best align with the target.
function [fitness, rmsError, penalties, order, validMask] = linkageFitness(pathPoints, targetPoints, isClosedPath, invalidCount)
sampleCount = size(pathPoints, 1);
penalties = 0;
if invalidCount > 0
    penalties = penalties + 1000 * invalidCount;
end

if any(any(isnan(pathPoints)))
    penalties = penalties + 500 * sum(any(isnan(pathPoints), 2));
end

validMask = ~any(isnan(pathPoints), 2);
if nnz(validMask) < max(4, floor(0.8 * sampleCount))
    penalties = penalties + 5000;
end

if all(validMask) && isClosedPath
    order = fourbarBestClosedCurveOrder(pathPoints, targetPoints);
    pathPoints = pathPoints(order, :);
else
    order = 1:sampleCount;
end

if any(validMask)
    distances = vecnorm(pathPoints(validMask, :) - targetPoints(validMask, :), 2, 2);
    rmsError = sqrt(mean(distances .^ 2));
else
    rmsError = 1e6;
end

if nnz(validMask) >= 3
    smoothness = diff(pathPoints(validMask, :), 2, 1);
    penalties = penalties + 0.02 * mean(vecnorm(smoothness, 2, 2));
end

fitness = rmsError + penalties;
end

% Evaluate the slider-enhanced 4-bar mechanism used by the legacy
% `fourbar` / `slider_fourbar` mode.
function result = fourbarEvaluateCandidate(candidate, target, isClosedPath, allowMovingTracePoint)
if nargin < 4
    allowMovingTracePoint = true;
end
params = fourbarDecodeCandidate(candidate, size(target, 1));
params = applyTraceMotionMode(params, allowMovingTracePoint);
result = struct();
result.fitness = inf;
result.rmsError = inf;
result.penalty = inf;
result.genes = candidate;
result.params = params;
result.path = nan(size(target));
result.A = nan(size(target));
result.B = nan(size(target));
result.C = nan(size(target));
result.D = nan(size(target));
result.sliderB = nan(size(target));
result.sliderC = nan(size(target));
result.order = 1:size(target, 1);
result.isValid = false;

inputAngles = params.inputAngles(:);
sampleCount = numel(inputAngles);
A = repmat(params.groundA, sampleCount, 1);
D = repmat(params.groundD, sampleCount, 1);
B = nan(sampleCount, 2);
C = nan(sampleCount, 2);
sliderB = nan(sampleCount, 2);
sliderC = nan(sampleCount, 2);
P = nan(sampleCount, 2);

invalidCount = 0;
branchSign = params.branchSign;
for idx = 1:sampleCount
    B(idx, :) = params.groundA + params.crankLength * [cos(inputAngles(idx)), sin(inputAngles(idx))];
    [pointC, isValid] = fourbarCircleIntersection(B(idx, :), params.couplerLength, params.groundD, params.rockerLength, branchSign);
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
    theta = inputAngles(idx);
    dirB = cos(params.sliderAngleB) * ux + sin(params.sliderAngleB) * uy;
    dirC = cos(params.sliderAngleC) * ux + sin(params.sliderAngleC) * uy;
    displacementB = params.sliderOffsetB ...
        + params.sliderAmpB1 * sin(theta + params.sliderPhaseB1) ...
        + params.sliderAmpB2 * sin(2 * theta + params.sliderPhaseB2);
    displacementC = params.sliderOffsetC ...
        + params.sliderAmpC1 * sin(theta + params.sliderPhaseC1) ...
        + params.sliderAmpC2 * sin(2 * theta + params.sliderPhaseC2);

    sliderB(idx, :) = B(idx, :) + displacementB * dirB;
    sliderC(idx, :) = C(idx, :) + displacementC * dirC;
    connector = sliderC(idx, :) - sliderB(idx, :);
    connectorNorm = norm(connector);
    if connectorNorm < 1e-10
        invalidCount = invalidCount + 1;
        continue;
    end
    connectorUnit = connector / connectorNorm;
    connectorNormal = [-connectorUnit(2), connectorUnit(1)];
    traceBlend = clampUnitInterval(params.traceBlend + params.traceBlendAmp * sin(theta + params.traceBlendPhase));
    connectorOffset = params.connectorOffset + params.offsetAmp * sin(2 * theta + params.offsetPhase);
    P(idx, :) = (1 - traceBlend) * sliderB(idx, :) ...
        + traceBlend * sliderC(idx, :) ...
        + connectorOffset * connectorNormal;
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

if all(validMask) && isClosedPath
    order = fourbarBestClosedCurveOrder(P, target);
    A = A(order, :);
    B = B(order, :);
    C = C(order, :);
    D = D(order, :);
    sliderB = sliderB(order, :);
    sliderC = sliderC(order, :);
    P = P(order, :);
else
    order = 1:sampleCount;
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

penalties = penalties + 0.01 * ( ...
    abs(params.sliderOffsetB) + abs(params.sliderOffsetC) + ...
    params.sliderAmpB1 + params.sliderAmpB2 + ...
    params.sliderAmpC1 + params.sliderAmpC2 + ...
    abs(params.connectorOffset) + 0.35 * params.offsetAmp + 0.15 * params.traceBlendAmp);

result.fitness = fitError + penalties;
result.rmsError = fitError;
result.penalty = penalties;
result.path = P;
result.A = A;
result.B = B;
result.C = C;
result.D = D;
result.sliderB = sliderB;
result.sliderC = sliderC;
result.order = order;
result.isValid = invalidCount == 0 && all(validMask);
end

% Decode the slider-enhanced 4-bar chromosome.
function params = fourbarDecodeCandidate(candidate, sampleCount)
params = struct();
params.groundA = candidate(1:2);
params.groundAngle = candidate(3);
params.groundLength = candidate(4);
params.crankLength = candidate(5);
params.couplerLength = candidate(6);
params.rockerLength = candidate(7);
params.sliderAngleB = candidate(8);
params.sliderOffsetB = candidate(9);
params.sliderAmpB1 = candidate(10);
params.sliderPhaseB1 = candidate(11);
params.sliderAmpB2 = candidate(12);
params.sliderPhaseB2 = candidate(13);
params.sliderAngleC = candidate(14);
params.sliderOffsetC = candidate(15);
params.sliderAmpC1 = candidate(16);
params.sliderPhaseC1 = candidate(17);
params.sliderAmpC2 = candidate(18);
params.sliderPhaseC2 = candidate(19);
params.traceBlend = candidate(20);
params.connectorOffset = candidate(21);
params.traceBlendAmp = candidate(22);
params.traceBlendPhase = candidate(23);
params.offsetAmp = candidate(24);
params.offsetPhase = candidate(25);
params.thetaStart = candidate(26);
params.thetaSpan = candidate(27);
params.branchSign = 2 * (candidate(28) >= 0.5) - 1;
params.directionSign = 2 * (candidate(29) >= 0.5) - 1;
params.groundD = params.groundA + params.groundLength * [cos(params.groundAngle), sin(params.groundAngle)];
params.inputAngles = params.thetaStart + params.directionSign * linspace(0, params.thetaSpan, sampleCount);
params.sliderRailHalfLengthB = max(0.15 * params.couplerLength, ...
    abs(params.sliderOffsetB) + params.sliderAmpB1 + params.sliderAmpB2);
params.sliderRailHalfLengthC = max(0.15 * params.couplerLength, ...
    abs(params.sliderOffsetC) + params.sliderAmpC1 + params.sliderAmpC2);
end

% Best cyclic/reversed alignment for closed-path comparison.
function order = fourbarBestClosedCurveOrder(pathPoints, targetPoints)
pointCount = size(targetPoints, 1);
bestScore = inf;
order = 1:pointCount;
forward = 1:pointCount;
reverse = pointCount:-1:1;

for shift = 0:(pointCount - 1)
    candidateOrder = circshift(forward, [0, shift]);
    score = sqrt(mean(vecnorm(pathPoints(candidateOrder, :) - targetPoints, 2, 2).^2));
    if score < bestScore
        bestScore = score;
        order = candidateOrder;
    end

    candidateOrder = circshift(reverse, [0, shift]);
    score = sqrt(mean(vecnorm(pathPoints(candidateOrder, :) - targetPoints, 2, 2).^2));
    if score < bestScore
        bestScore = score;
        order = candidateOrder;
    end
end
end

% Circle-circle closure equation for linkage position analysis.
%
% Geometrically, many of these mechanisms are solved by locating a joint as
% the intersection of two circles with known centers and radii.
function [intersectionPoint, isValid] = fourbarCircleIntersection(center1, radius1, center2, radius2, branchSign)
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
