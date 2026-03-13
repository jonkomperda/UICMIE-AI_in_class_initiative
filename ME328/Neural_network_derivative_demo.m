
clear;
clc;
close all;

% User-editable inputs
f = @(x) x.^4 - 3*x.^3 + 2*x.^2 + x - 5;
x_min = -2;
x_max = 4;
dx = 0.5;

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
dydx = zeros(size(y));

% Second-order forward difference at the first point.
dydx(1) = (-3 * y(1) + 4 * y(2) - y(3)) / (2 * dx);

% Second-order central difference at the interior points.
dydx(2:end-1) = (y(3:end) - y(1:end-2)) / (2 * dx);

% Second-order backward difference at the last point.
dydx(end) = (3 * y(end) - 4 * y(end-1) + y(end-2)) / (2 * dx);

results_table = table(x(:), y(:), dydx(:), ...
    'VariableNames', {'x', 'y', 'y_prime'});

disp(results_table);

figure('Name', 'Function and Derivative', 'Color', 'w');

subplot(2, 1, 1);
plot(x, y, 'b-o', 'LineWidth', 1.5, 'MarkerSize', 5);
grid on;
xlabel('x');
ylabel('y = f(x)');
title('Function Values');

subplot(2, 1, 2);
plot(x, dydx, 'r-s', 'LineWidth', 1.5, 'MarkerSize', 5);
grid on;
xlabel('x');
ylabel('dy/dx');
title('Numerical Derivative');
