# Neural Network vs. Finite Difference Derivative Demo
### *by Jon Komperda, PhD*

`Neural_network_derivative_demo.m` is a MATLAB teaching example that compares two ways of taking a derivative from sampled function data:

- a classical second-order finite-difference method
- a manually trained one-hidden-layer neural network differentiated analytically

The script is set up as a clear side-by-side demonstration of a traditional numerical method and a simple machine-learning approach for the same derivative-estimation problem.

## Running the demo

In MATLAB:

```matlab
run("Neural_network_derivative_demo.m")
```

You can also open and run `Neural_network_derivative_demo.mlx` in the Live Editor for a more presentation-friendly walkthrough.

## What the demo does

At a high level, the workflow is:

1. Define a polynomial function and a uniform grid.
2. Evaluate the function values at the grid points.
3. Compute the derivative using second-order finite differences.
4. Normalize the data and train a small neural network with gradient descent.
5. Differentiate the trained neural network analytically using the chain rule.
6. Compare the finite-difference and neural-network derivatives with tables, plots, and error metrics.

## Inputs you can change

The script exposes several parameters near the top so the example can be adjusted easily:

- `poly_coeffs`
  Polynomial coefficients in descending powers
- `x_min`, `x_max`
  Range of the sampled interval
- `dx`
  Uniform grid spacing
- `hiddenLayerSize`
  Number of neurons in the hidden layer
- `learningRate`
  Gradient-descent step size
- `epochs`
  Number of training iterations
- `randomSeed`
  Random seed for repeatable neural-network initialization

These inputs make it easy to explore how derivative accuracy changes with both numerical resolution and neural-network training choices.

## Finite-difference method

The finite-difference portion uses standard second-order formulas:

- a forward-difference formula at the first grid point
- a centered-difference formula at interior points
- a backward-difference formula at the last grid point

This is the classical numerical-analysis reference solution in the demo. It is straightforward, fast, and directly tied to the grid spacing `dx`.

## Neural-network method

The neural-network portion builds a small fully manual model with:

- one input
- one hidden layer with `tanh` activation
- one linear output
- gradient-descent training on normalized data

After training, the model is not just used to predict the function values. Its derivative is computed analytically by differentiating the network equations themselves. That makes this example especially useful for showing that a trained neural network can act as a smooth approximation whose derivative can be written down explicitly.

## What is being compared

The main comparison in this example is not just "which method gives a derivative," but how the two approaches behave conceptually:

- `Finite difference`
  Uses nearby function samples directly and depends strongly on grid spacing
- `Neural network`
  Learns a smooth approximation of the function first, then differentiates the learned model

This creates a nice teaching contrast between:

- local numerical approximation
- global function fitting
- explicit numerical formulas
- learned parametric models

## Outputs and visualizations

The script produces:

- a sample data table of `x` and `y`
- summary error metrics including RMSE, maximum absolute error, and mean absolute error
- a detailed comparison table with both derivative estimates
- a four-panel figure showing:
  function comparison,
  derivative comparison,
  derivative error,
  and training loss history

These outputs make it easy to discuss where the neural-network approximation tracks the finite-difference result well and where discrepancies remain.

