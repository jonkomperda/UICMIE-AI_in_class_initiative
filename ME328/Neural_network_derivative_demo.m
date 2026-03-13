%% Neural Network Derivative Demo
%
% _By: Jon Komperda, PhD 2026_ 
%
% This live script walks through every step used to compare a manual neural 
% network derivative against a second-order finite-difference derivative.
% 
% The workflow is:
% 
% 1. Define a polynomial function and a uniform grid.
% 
% 2. Evaluate the sample data $y = f(x)$.
% 
% 3. Compute the finite-difference derivative.
% 
% 4. Train a one-hidden-layer neural network manually with gradient descent.
% 
% 5. Differentiate the trained neural network analytically.
% 
% 6. Compare both derivatives with tables, error metrics, and plots.
%% Live Editor Inputs
% Edit these values directly in the Live Editor.
% 
% The polynomial is
% 
% $$f(x)=c_1x^n+c_2x^{n-1}+\cdots+c_nx+c_{n+1}$$
% 
% where the coefficients are stored in descending powers.

clear;
clc;
close all;

poly_coeffs = [1, -3, 2, 1, -5];
x_min = -4;
x_max = 4;
dx = 0.25;

hiddenLayerSize = 10;
learningRate = 0.1;
epochs = 5000;
randomSeed = 0;
%% Build the Function and the Uniform Grid
% The function handle is created from the polynomial coefficients.
% 
% The grid is
% 
% $$x_i=x_{\min}+(i-1)\Delta x$$
% 
% for equally spaced points between $x_{\min}$ and $x_{\max}$ .

if x_max <= x_min
    error('x_max must be greater than x_min.');
end

if dx <= 0
    error('dx must be positive.');
end

f = @(x) polyval(poly_coeffs, x);
x = x_min:dx:x_max;

if numel(x) < 3
    error('At least 3 grid points are required for second-order finite differences.');
end

y = f(x);
%% Sample Data
% This is the dataset the neural network will learn. Each row contains one x 
% location and the corresponding $y = f(x)$ value.

sample_data_table = table(x(:), y(:), 'VariableNames', {'x', 'y'});
disp(sample_data_table);
%% Finite-Difference Derivative
% We compute the derivative with second-order accurate formulas.
% 
% At the first point:
% 
% $$y_1' \approx \frac{-3y_1+4y_2-y_3}{2\Delta x}$$
% 
% At interior points:
% 
% $$y_i' \approx \frac{y_{i+1}-y_{i-1}}{2\Delta x}$$
% 
% At the last point:
% 
% $$y_n' \approx \frac{3y_n-4y_{n-1}+y_{n-2}}{2\Delta x}$$

dydx_fd = zeros(size(y));

dydx_fd(1) = (-3 * y(1) + 4 * y(2) - y(3)) / (2 * dx);
dydx_fd(2:end-1) = (y(3:end) - y(1:end-2)) / (2 * dx);
dydx_fd(end) = (3 * y(end) - 4 * y(end-1) + y(end-2)) / (2 * dx);
%% Neural Network Model
% The neural network has one input, one hidden layer, and one output.
% 
% For each sample:
% 
% $$z=W_1x_{\mathrm{norm}}+b_1$$
% 
% $$a=\tanh(z)$$
% 
% $$\hat{y}_{\mathrm{norm}}=W_2a+b_2$$
% 
% where $x_{norm}$ and $y_{norm}$ are normalized variables.

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
sampleCount = numel(x_norm);

rng(randomSeed);
W1 = 0.5 * randn(hiddenLayerSize, 1);
b1 = zeros(hiddenLayerSize, 1);
W2 = 0.5 * randn(1, hiddenLayerSize);
b2 = 0;

loss_history = zeros(epochs, 1);
%% Loss Function and Gradient Descent
% The loss is the mean squared error on normalized outputs:
% 
% $$L=\mathrm{mean}\left((\hat{y}_{\mathrm{norm}}-y_{\mathrm{norm}})^2\right)$$
% 
% The output-layer gradient is based on
% 
% $$\frac{\partial L}{\partial \hat{y}_{\mathrm{norm}}} =\frac{2}{N}\left(\hat{y}_{\mathrm{norm}}-y_{\mathrm{norm}}\right)$$
% 
% The $\tanh$ derivative is
% 
% $$\frac{d}{dz}\tanh(z)=1-\tanh^2(z)$$
% 
% Each epoch performs a full forward pass, a full backward pass, and then a 
% gradient-descent parameter update.

for epoch = 1:epochs
    Z1 = W1 * x_norm + b1;
    A1 = tanh(Z1);
    y_pred_norm = W2 * A1 + b2;

    errorSignal = y_pred_norm - y_norm;
    loss_history(epoch) = mean(errorSignal .^ 2);

    dY = (2 / sampleCount) * errorSignal;
    dW2 = dY * A1.';
    db2 = sum(dY, 2);

    dA1 = W2.' * dY;
    dZ1 = dA1 .* (1 - A1 .^ 2);
    dW1 = dZ1 * x_norm.';
    db1 = sum(dZ1, 2);

    W1 = W1 - learningRate * dW1;
    b1 = b1 - learningRate * db1;
    W2 = W2 - learningRate * dW2;
    b2 = b2 - learningRate * db2;
end
%% Neural Network Prediction in Original Units
% The network is trained in normalized coordinates, so we scale its output back 
% to the original y units:
% 
% $$\hat{y}=\hat{y}_{\mathrm{norm}}\cdot \mathrm{outputStd}+\mathrm{outputMean}$$

Z1 = W1 * x_norm + b1;
A1 = tanh(Z1);
y_pred_norm = W2 * A1 + b2;
y_nn = y_pred_norm * outputStd + outputMean;
y_nn = y_nn(:).';
%% Analytic Neural Network Derivative
% The neural-network derivative is computed analytically with the chain rule.
% 
% Because
% 
% $$x_{\mathrm{norm}}=\frac{x-\mathrm{inputMean}}{\mathrm{inputStd}}$$
% 
% we have
% 
% $$\frac{d x_{\mathrm{norm}}}{dx}=\frac{1}{\mathrm{inputStd}}$$
% 
% Also,
% 
% $$\hat{y}=\mathrm{outputStd}\cdot \hat{y}_{\mathrm{norm}}+\mathrm{outputMean}$$
% 
% so
% 
% $$\frac{d\hat{y}}{dx} =\frac{\mathrm{outputStd}}{\mathrm{inputStd}} \frac{d\hat{y}_{\mathrm{norm}}}{d 
% x_{\mathrm{norm}}}$$
% 
% For the hidden layer:
% 
% $$\frac{d\hat{y}_{\mathrm{norm}}}{d x_{\mathrm{norm}}} =W_2\left(\left(1-\tanh^2(z)\right)\odot 
% W_1\right)$$

dA1dXnorm = 1 - A1 .^ 2;
dydx_norm = W2 * (dA1dXnorm .* W1);
scaleFactor = outputStd / inputStd;
dydx_nn = scaleFactor * dydx_norm;
dydx_nn = dydx_nn(:).';
%% Error Metrics
% We compare the neural-network derivative to the finite-difference derivative 
% point by point.
% 
% $$\mathrm{error}=y'_{\mathrm{nn}}-y'_{\mathrm{fd}}$$
% 
% $$\mathrm{abs\_error}=|\mathrm{error}|$$
% 
% $$\mathrm{RMSE}=\sqrt{\mathrm{mean}\left(\mathrm{error}^2\right)}$$

derivative_error = dydx_nn - dydx_fd;
absolute_error = abs(derivative_error);
rmse_error = sqrt(mean(derivative_error .^ 2));
max_abs_error = max(absolute_error);
mean_abs_error = mean(absolute_error);

summary_metrics_table = table(rmse_error, max_abs_error, mean_abs_error, ...
    'VariableNames', {'rmse_error', 'max_abs_error', 'mean_abs_error'});

disp(summary_metrics_table);
%% Comparison Table
% This table contains the function values, both derivative estimates, and the 
% resulting pointwise error values.

results_table = table( ...
    x(:), ...
    y(:), ...
    y_nn(:), ...
    dydx_fd(:), ...
    dydx_nn(:), ...
    derivative_error(:), ...
    absolute_error(:), ...
    'VariableNames', {'x', 'y', 'y_nn', 'y_prime_fd', 'y_prime_nn', 'error', 'abs_error'});

disp(results_table);
%% Comparison Plots
% Plot styling:
% 
% - Reference curves are red solid lines with no markers. 
% 
% - Neural-network predictions are blue dashed lines with blue markers.

figure('Name', 'Neural Network Derivative Demo', 'Color', 'w');

subplot(4, 1, 1);
plot(x, y, 'r-', 'LineWidth', 1.5);
hold on;
plot(x, y_nn, 'b--o', 'LineWidth', 1.5, 'MarkerSize', 5);
hold off;
grid on;
xlabel('x');
ylabel('y');
title('Function Comparison');
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
set(gcf, 'Visible', 'on');
theme(gcf,"light")