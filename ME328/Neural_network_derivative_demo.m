function Neural_network_derivative_demo

    clc;
    close all;

    % User-editable inputs
    f = @(x) x.^4 - 3*x.^3 + 2*x.^2 + x - 5;
    x_min = -4;
    x_max = 4;
    dx = 0.25;

    if x_max <= x_min
        error('x_max must be greater than x_min.');
    end
    if dx <= 0
        error('dx must be positive.');
    end

    x = x_min:dx:x_max;

    if numel(x) < 3
        error('At least 3 grid points are required for second-order finite differences.');
    end

    y = f(x);
    dydx_fd = numericalDerivatives(y, dx);
    [y_nn, model, loss_history] = trainFunctionNetwork(x, y);
    dydx_nn = neuralNetworkDerivative(x, model);
    derivative_error = dydx_nn - dydx_fd;
    absolute_error = abs(derivative_error);
    rmse_error = sqrt(mean(derivative_error .^ 2));
    max_abs_error = max(absolute_error);
    results_table = makeResultsTable(x, y, y_nn, dydx_fd, dydx_nn, derivative_error, absolute_error);

    disp(results_table);
    fprintf('Derivative RMSE: %.6f\n', rmse_error);
    fprintf('Max absolute derivative error: %.6f\n', max_abs_error);
    makePlots(x, y, y_nn, dydx_fd, dydx_nn, derivative_error, loss_history);
end

function dydx = numericalDerivatives(y, dx)
% compute first derivatives using second-order accurate
% forward, central, and backward finite differences.

    dydx = zeros(size(y));

    % Second-order forward difference at the first point.
    dydx(1) = (-3 * y(1) + 4 * y(2) - y(3)) / (2 * dx);

    % Second-order central difference at interior points.
    dydx(2:end-1) = (y(3:end) - y(1:end-2)) / (2 * dx);

    % Second-order backward difference at the last point.
    dydx(end) = (3 * y(end) - 4 * y(end-1) + y(end-2)) / (2 * dx);
end

function [y_nn, model, loss_history] = trainFunctionNetwork(x, y)
% Train a small neural network manually with gradient descent to
% learn y = f(x) without toolbox dependencies, because I can't
% get them to work.

    x_train = x(:).';
    y_train = y(:).';

    inputMean = mean(x_train);
    inputStd = std(x_train);
    if inputStd == 0
        inputStd = 1;
    end

    outputMean = mean(y_train);
    outputStd = std(y_train);
    if outputStd == 0
        outputStd = 1;
    end

    x_norm = (x_train - inputMean) / inputStd;
    y_norm = (y_train - outputMean) / outputStd;

    hiddenLayerSize = 10;
    learningRate = 0.1;
    epochs = 5000;
    sampleCount = numel(x_norm);
    loss_history = zeros(epochs, 1);

    rng(0);
    W1 = 0.5 * randn(hiddenLayerSize, 1);
    b1 = zeros(hiddenLayerSize, 1);
    W2 = 0.5 * randn(1, hiddenLayerSize);
    b2 = 0;

    for epoch = 1:epochs
        Z1 = W1 * x_norm + b1;
        A1 = tanh(Z1);
        y_pred = W2 * A1 + b2;

        errorSignal = y_pred - y_norm;
        loss_history(epoch) = mean(errorSignal .^ 2);
        dY = (2 / sampleCount) * errorSignal;

        dW2 = dY * A1.';
        db2 = sum(dY, 2);

        dA1 = W2.' * dY;
        dZ1 = dA1 .* (1 - A1.^2);
        dW1 = dZ1 * x_norm.';
        db1 = sum(dZ1, 2);

        W1 = W1 - learningRate * dW1;
        b1 = b1 - learningRate * db1;
        W2 = W2 - learningRate * dW2;
        b2 = b2 - learningRate * db2;

        if mod(epoch, 1000) == 0
            learningRate = 0.98 * learningRate;
        end
    end

    Z1 = W1 * x_norm + b1;
    A1 = tanh(Z1);
    y_pred_norm = W2 * A1 + b2;
    y_nn = y_pred_norm * outputStd + outputMean;
    y_nn = y_nn(:).';

    model.W1 = W1;
    model.b1 = b1;
    model.W2 = W2;
    model.b2 = b2;
    model.inputMean = inputMean;
    model.inputStd = inputStd;
    model.outputMean = outputMean;
    model.outputStd = outputStd;
end

function dydx_nn = neuralNetworkDerivative(x, model)
% Compute the derivative analytically from the trained neural network.

    x_row = x(:).';
    x_norm = (x_row - model.inputMean) / model.inputStd;
    Z1 = model.W1 * x_norm + model.b1;
    A1 = tanh(Z1);
    dA1dXnorm = 1 - A1 .^ 2;

    dydx_norm = model.W2 * (dA1dXnorm .* model.W1);
    scaleFactor = model.outputStd / model.inputStd;
    dydx_nn = scaleFactor * dydx_norm;
    dydx_nn = dydx_nn(:).';
end

function results_table = makeResultsTable(x, y, y_nn, dydx_fd, dydx_nn, derivative_error, absolute_error)
% Assemble function, derivative, and error comparison data into a MATLAB table.

    results_table = table(x(:), y(:), y_nn(:), dydx_fd(:), dydx_nn(:), ...
        derivative_error(:), absolute_error(:), ...
        'VariableNames', {'x', 'y', 'y_nn', 'y_prime_fd', 'y_prime_nn', 'error', 'abs_error'});
end

function makePlots(x, y, y_nn, dydx_fd, dydx_nn, derivative_error, loss_history)
% Plot function comparison, derivative comparison, derivative error, and loss.

    figure('Name', 'Function and Derivative', 'Color', 'w');

    subplot(4, 1, 1);
    plot(x, y, 'r-', 'LineWidth', 1.5);
    hold on;
    plot(x, y_nn, 'b--o', 'LineWidth', 1.5, 'MarkerSize', 5);
    hold off;
    grid on;
    xlabel('x');
    ylabel('y = f(x)');
    title('Function Values and Neural Network Fit');
    legend('Function reference', 'Neural network prediction', 'Location', 'best');

    subplot(4, 1, 2);
    plot(x, dydx_fd, 'r-', 'LineWidth', 1.5);
    hold on;
    plot(x, dydx_nn, 'b--o', 'LineWidth', 1.5, 'MarkerSize', 5);
    hold off;
    grid on;
    xlabel('x');
    ylabel('dy/dx');
    title('Derivative Comparison');
    legend('Finite difference', 'Neural network derivative', 'Location', 'best');

    subplot(4, 1, 3);
    plot(x, derivative_error, 'r-', 'LineWidth', 1.5);
    hold on;
    yline(0, 'k--', 'LineWidth', 1.0);
    hold off;
    grid on;
    xlabel('x');
    ylabel('Error');
    title('Derivative Error (NN - Finite Difference)');

    subplot(4, 1, 4);
    semilogy(1:numel(loss_history), loss_history, 'm-', 'LineWidth', 1.5);
    grid on;
    xlabel('Epoch');
    ylabel('Loss');
    title('Training Loss Over Epochs');
end
