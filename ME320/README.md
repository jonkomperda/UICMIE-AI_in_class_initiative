# Four-Bar / Multi-Bar Linkage GA Synthesizer
### *by Jon Komperda, PhD*

`fourbar_ga_app.m` is an interactive MATLAB app for path calculation of linkages using a genetic algorithm (GA) based approach.

The app lets you:

- draw or load a target path
- choose a mechanism family
- tune GA settings such as population, generations, mutation, crossover, elites, tournament size, workers, and target RMSE
- choose whether the tracing point is fixed or allowed to move during the cycle
- watch the linkage evolve during optimization
- play the final mechanism animation

## Running the app

In MATLAB:

```matlab
fourbar_ga_app
```
or, just run the script...

## What the app does

At a high level, the workflow is:

1. Let the user define a target path.
2. Convert that path to evenly spaced target samples.
3. Choose a mechanism family and a tracing-point mode.
4. Runs a genetic algorithm that searches mechanism parameters.
5. Score each candidate by comparing its traced path to the target.
6. Preview the best mechanism during the run.
7. Animate the best final solution.

## GUI overview

The GUI has three plots:

- `Target Path`: the user-defined or example path
- `Fitness History`: best score over generations
- `Mechanism Evolution`: current best mechanism geometry and traced path

The left control panel contains the solver inputs and run controls.

## Path controls

- `Example Menu`
  Chooses one of the built-in target paths.

- `Load`
  Loads the selected example path.

- `Select Path Points`
  Turns on click-to-add mode for manually drawing a path in the `Target Path` axes.

- `Undo`
  Removes the last clicked point.

- `Clear`
  Clears the current path and solver history.

- `Closed Path`
  Treats the path as a loop. This matters for cyclic alignment during fitness scoring.

- `Path Samples`
  Number of evenly spaced target points used by the solver.
  Larger values increase fidelity but also computation time.

## Mechanism controls

- `Mechanism Mode`
  Selects the linkage family being optimized.

- `Moving Trace Point`
  If checked, the tracing point is allowed to move along the linkage geometry over the cycle.
  If unchecked, the tracing point stays fixed relative to the mechanism parameters.

## View controls

- `Fit Axes`
  Automatically fits the path and mechanism plots.

- `Zoom In`
  Zooms both plots inward.

- `Zoom Out`
  Zooms both plots outward.

- `Lock View`
  Freezes the current axis limits during updates.

- `Pan Left`, `Pan Right`, `Pan Up`, `Pan Down`
  Shifts both plots without changing the current zoom.

## Animation controls

- `Anim. Cycles`
  Number of times the final animation repeats.

- `Frame Pause (s)`
  Delay between animation frames.

## Genetic algorithm controls

- `Population`
  Number of candidate mechanisms per generation.

- `Generations`
  Maximum number of generations for one attempt.

- `Mutation Rate`
  Probability that a given gene is perturbed during mutation.

- `Crossover Rate`
  Probability that two parents are blended instead of copied directly.

- `Elite Count`
  Number of best candidates copied unchanged into the next generation.

- `Tournament`
  Tournament-selection size used to choose parents.

- `Workers`
  Number of MATLAB parallel workers used for population evaluation.
  `1` means serial evaluation. This is needed sometimes for huge runs and complex mechanisms (like the 6-bar or a crazy shape that requires alot of mutations).

- `Target RMSE`
  Desired RMS path error threshold. If the solution is above this value, the app can offer stronger retry settings after not converging. 

## Run controls

- `Run Genetic Algorithm`
  Starts the solver.

- `Stop`
  Requests a graceful stop after the current generation completes.

- `Status`
  Shows whether the app is idle, running, or stalled.

- `Event Log`
  Timestamped messages about solver progress, retries, and final results.

## Built-in shapes

The app currently includes:

- `Ellipse`
- `Circle`
- `Rounded Rectangle`
- `Rounded Square`
- `Half Moon`
- `Heart`
- `Lemniscate`
- `Teardrop`
- `Bean`
- `S Curve`

Most of these are closed loops. `S Curve` is open.

## Mechanism families

The app supports multiple mechanism families with different parameterizations.

### 1. 4-Bar Standard

A classic planar four-bar:

- ground link
- crank
- coupler
- rocker

The tracing point is defined relative to the coupler:

- by a blend along the line from joint `B` to joint `C`
- by a normal offset from that line

### 2. 4-Bar Slider-Enhanced

A four-bar with slider attachments tied to the coupler endpoints.

- one slider attached near `B`
- one slider attached near `C`
- the tracing point taken relative to the connector between slider carriages

This gives more shape freedom than a classic fixed coupler point.

### 3. 4-Bar Multi-Slider

A richer version of the slider-enhanced four-bar.

- extra slider harmonics
- dynamic bridge point between slider carriages
- richer tracing-point motion

This mode is intended for more difficult targets.

### 4. 5-Bar Parallel

A planar five-bar loop formed by:

- left ground pivot and crank
- right ground pivot and crank
- two distal links that meet at a closure point

The tracer is defined relative to the closure point and midpoint geometry.

### 5. 5-Bar Slider-Enhanced

A five-bar with slider-assisted distal-link tracing geometry.

This gives additional degrees of freedom for matching complex paths.

### 6. 6-Bar Stephenson

A six-bar formed by:

- a base four-bar
- an auxiliary ground pivot
- an auxiliary coupler/rocker loop attached to a point on the base coupler

### 7. 6-Bar Slider-Enhanced

A six-bar with slider-assisted tracer geometry on the auxiliary loop.

## How the kinematics are solved

Most positions are computed using circle-circle intersection.

If a point `P` must lie:

- at distance `r1` from center `C1`
- at distance `r2` from center `C2`

then `P` is one of the intersections of those two circles.

This is the core closure operation used throughout the app.

### Standard four-bar position analysis

For a given input angle `theta`:

1. Crank joint `B` is computed from the ground pivot `A`:

```text
B = A + Lcrank [cos(theta), sin(theta)]
```

2. Joint `C` is found from the intersection of:

- a circle centered at `B` with radius `Lcoupler`
- a circle centered at `D` with radius `Lrocker`

3. The tracing point is built from the coupler line:

```text
P = (1 - s) B + s C + d n
```

where:

- `s` is the blend along the coupler
- `d` is a normal offset
- `n` is the unit normal to the coupler

If moving-trace mode is enabled, the blend and offset can vary with angle:

```text
s(theta) = s0 + As sin(theta + phis)
d(theta) = d0 + Ad sin(2 theta + phid)
```

with clamping of the blend to `[0, 1]`.

### Slider-enhanced mechanisms

For slider-based modes, slider carriage positions are typically modeled as:

```text
S = base_point + displacement(theta) * rail_direction
```

The displacement can contain harmonic terms like:

```text
displacement(theta) = a0 + a1 sin(theta + p1) + a2 sin(2 theta + p2) + ...
```

The tracing point is then defined from:

- a connector between slider positions
- a bridge point between sliders
- a normal/longitudinal offset from that connector

### Five-bar position analysis

The two crank endpoints are first computed from their ground pivots.
The distal closure point is then found by circle intersection.
The tracing point is defined relative to that closure point and reference geometry.

### Six-bar position analysis

The base four-bar is solved first.
Then an auxiliary loop is solved from a point on the base coupler.
The tracer is defined from the auxiliary geometry.

## Genetic algorithm details

The app uses a custom GA rather than MATLAB's built-in `ga` function. Mostly because I couldn't figure out how to get the MATLAB one to work. If you can do it, push me a commit so I can update it.

### Chromosome

A chromosome is a vector of real-valued design variables.

Depending on the selected mechanism, the vector may include:

- ground-pivot coordinates
- ground angle
- link lengths
- branch selectors
- input angle start/sweep
- slider rail angles
- slider amplitudes and phases
- coupler blend values
- tracing-point offset values
- tracing-point motion amplitudes and phases

Each mechanism mode has its own chromosome layout and bounds.

### Population initialization

The initial population is built by:

- drawing random samples inside bounds
- optionally cloning around a warm start
- injecting several heuristic seeds scaled to the target path size

The heuristic seeds are important because they place some initial mechanisms near plausible link-length scales instead of relying on purely random sampling.

Most of this was figured out by trial and error, as well as alot of time crawling the internet.

### Fitness function

Each candidate is scored by:

```text
fitness = RMS path error + penalties
```

The penalties include terms for:

- invalid kinematic closures
- missing path points
- too few valid samples
- roughness / lack of smoothness
- overly large offsets or slider amplitudes in some modes

For closed paths, the code allows:

- cyclic shifts
- reversed point ordering

so a candidate is not unfairly penalized just because it starts at a different point on the loop.

Sometimes this doesn't work, and it simply doesn't converge. Try again, from a fresh seed, in that case. A couple of attempts will usually get a good path. I'll look into ways of making this more robust.

### Selection

The app uses tournament selection.

For each parent:

1. Randomly choose `k` candidates.
2. Pick the best among them.

Larger tournaments increase selection pressure.

### Crossover

If crossover occurs, two parents are blended arithmetically.

This creates children whose genes are mixtures of the parents rather than simple one-point swaps.

### Mutation

Mutation is Gaussian:

```text
gene_new = gene_old + sigma * randn
```

with mutation applied independently to each gene with probability equal to `Mutation Rate`.

All genes are clamped back to their bounds afterward.

### Elitism

The best `Elite Count` individuals are copied unchanged into the next generation.

This prevents the GA from losing its best-so-far solutions.

### Stall detection and restarts

If the best score stops improving for too many generations:

- the app marks the run as stalled and stops
- the mutation rate and perturbation scale are increased (you can pick how much)
- restart launches around the best design so far, but only the best
- fresh candidates are injected into the population

This helps the search escape local minima. Sometimes it does, sometimes it doesn't. Occassionally you just need to restart with a new seed.

### Local refinement

After the GA ends, the best candidate is refined using:

- random perturbation trials
- a coordinate-wise sweep over individual genes

This often improves the final RMSE without needing a much larger population.

## Suggested starting values

Reasonable default starting points:

- `Population`: `200` to `400`
- `Generations`: `400` to `800`
- `Mutation Rate`: `0.18` to `0.32`
- `Crossover Rate`: `0.80` to `0.95`
- `Elite Count`: `6` to `15`
- `Tournament`: `3` to `5`
- `Workers`: `2` to `8` if Parallel Computing Toolbox is available
- `Path Samples`: `28` to `48`
- `Target RMSE`: `0.10` to `0.20` for realistic goals, `0.05` to `0.10` for ambitious goals

## Notes on convergence

- A simple 1-DOF linkage cannot exactly trace every arbitrary symbol.
- Rounded curves are typically easier than sharp-cornered paths.
- Moving-trace mode usually helps with more interesting shapes.
- Advanced slider-enhanced mechanisms provide more flexibility, but they also increase search difficulty, more stalling, and take way longer to compute.
- More complex mechanisms usually benefit from larger populations and more generations.

