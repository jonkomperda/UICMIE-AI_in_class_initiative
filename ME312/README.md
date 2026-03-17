# HVAC PID / Neural Network Control Demo
### *by Jon Komperda, PhD*

`hvac_pid_nn_control_demo.m` is an interactive MATLAB teaching app for introductory HVAC temperature control. The current version compares three controllers on the same cooling-only room model:

- a basic on/off thermostat with hysteresis
- a PID controller with duty-cycle and two-stage actuation modes
- a neural-network controller trained to imitate the PID duty-cycle response

The app keeps the broader `pid_nn` framing so students can compare simple rule-based control, classical feedback control, and an early AI-based controller in the same interface.

## Running the demo

Run the file from the `ME312` folder or add that folder to your MATLAB path first:

```matlab
hvac_pid_nn_control_demo
```

## What the app does

At a high level, the workflow is:

1. Load a built-in ambient temperature profile or click points to define a custom profile over a 24-hour window.
2. Set the room-model, thermostat, and PID parameters.
3. Train the neural-network controller if you want to include it in the comparison.
4. Run the HVAC simulation.
5. Compare thermostat, PID, and NN temperature responses, cooling effort, and summary metrics.

## Current scope

The current version includes:

- three built-in ambient profiles:
  - `Summer Warm-Up`
  - `Heat-Wave Spike`
  - `Day-Night Cycle`
- manual point-based ambient profile creation by clicking in the left plot
- a simple first-order cooling-room model
- a shared setpoint used by all controllers
- independent enable toggles for:
  - basic thermostat
  - PID controller
  - neural-network controller
- a PID controller with two selectable actuation modes:
  - `Duty Cycle`
    continuous PWM-like cooling between `0` and `1`
  - `Two Stage`
    staged cooling levels at `0`, `0.5`, and `1`
- a neural-network controller that:
  - is implemented in plain MATLAB without Neural Network Toolbox / Deep Learning Toolbox
  - uses a one-hidden-layer multilayer perceptron
  - learns from PID duty-cycle training targets generated from simulated HVAC runs
  - outputs a continuous cooling level between `0` and `1`
- a right-side comparison plot showing:
  - outdoor temperature
  - thermostat indoor temperature
  - PID indoor temperature
  - NN indoor temperature
  - setpoint
  - thermostat AC state
  - PID cooling level
  - NN cooling level
- an optional 3-second animation of the comparison plot
- left-panel run statistics for thermostat and PID
- right-panel training summary and NN run statistics

## UI layout

The app is split into four main regions:

- `Controls` panel on the left
  - ambient-profile tools
  - room-model controls
  - thermostat controls
  - PID controls
  - run button and animation toggle
  - thermostat and PID statistics
  - shared status line at the bottom
- `Ambient Temperature Profile` plot
  - shows the outdoor temperature profile that drives the room model
- `Controller Comparison` plot
  - overlays all enabled controller temperature and cooling traces
- `NN Controls` panel on the right
  - NN enable toggle
  - `Train NN` button
  - feature-selection checkboxes
  - NN hyperparameters
  - training summary
  - NN run statistics

## Inputs you can change

### Room Model

- `Initial Indoor (degF)`
  Starting room temperature at the beginning of the simulation.

- `Room Response (1/hr)`
  A simple thermal-response coefficient that pulls the indoor temperature toward the ambient temperature.

- `AC Cooling (degF/hr)`
  The maximum cooling strength applied when the controller command is fully on.

### Basic Thermostat

- `Enable`
  Turns the thermostat comparison path on or off.

- `Setpoint (degF)`
  Shared indoor target temperature for all controllers.

- `Deadband (degF)`
  Thermostat hysteresis width. Larger values reduce switching chatter.

### PID Controls

- `Enable`
  Turns the PID comparison path on or off.

- `Kp`
  Proportional gain.

- `Ki`
  Integral gain.

- `Kd`
  Derivative gain.

- `PID Mode`
  Selects either continuous duty-cycle cooling or two-stage cooling.

### NN Controls

- `Enable`
  Turns the NN comparison path on or off.

- `Train NN`
  Builds a training dataset from simulated PID duty-cycle runs and fits the NN weights.

- `Temp Error (required)`
  Always included as an NN input feature.

- `Ambient Temp`
  Optional NN input feature.

- `Error Trend`
  Optional NN input feature.

- `Hidden Neurons`
  Number of hidden-layer neurons in the NN.

- `Learning Rate`
  Batch-gradient-descent learning rate.

- `Epochs`
  Number of training passes through the dataset.

## Simple thermal model

The room is modeled as a single thermal state:

- ambient temperature acts as an external disturbance
- the room temperature drifts toward ambient temperature at a user-controlled rate
- controller output removes heat at a fixed maximum rate scaled by the command signal

This is not intended to be a high-fidelity building model. It is an educational example that keeps the dynamics easy to explain and modify.

## Controllers in the app

### Basic thermostat

The thermostat uses hysteresis:

- AC turns on when indoor temperature rises above `setpoint + deadband/2`
- AC turns off when indoor temperature falls below `setpoint - deadband/2`
- inside that band, it keeps the previous on/off state

In equation form, with indoor temperature $T_{\mathrm{in}}(t)$, setpoint $T_{\mathrm{set}}$, deadband $\Delta T$, and thermostat state $u_{\mathrm{th}}(t) \in \{0,1\}$:

$$
u_{\mathrm{th}}(t)=
\begin{cases}
1, & T_{\mathrm{in}}(t) > T_{\mathrm{set}} + \dfrac{\Delta T}{2} \\
0, & T_{\mathrm{in}}(t) < T_{\mathrm{set}} - \dfrac{\Delta T}{2} \\
u_{\mathrm{th}}(t^-), & \text{otherwise}
\end{cases}
$$

### PID controller

The PID branch uses:

- proportional, integral, and derivative error terms
- a selectable cooling actuator mode:
  - `Duty Cycle`
    applies continuous cooling between `0` and `1`
  - `Two Stage`
    maps the PID demand to stepped cooling levels at `0`, `0.5`, and `1`

The PID governing equation is based on the temperature error
$e(t)=T_{\mathrm{in}}(t)-T_{\mathrm{set}}$,
with cooling demand written as:

$$
u_{\mathrm{PID}}(t) = K_p e(t) + K_i \int_0^t e(\tau)\,d\tau + K_d \frac{de(t)}{dt}
$$

In the implementation, this raw PID demand is then mapped into the selected actuator mode:

$$
u_{\mathrm{cool}}(t)=
\begin{cases}
\mathrm{clip}\!\left(u_{\mathrm{PID}}(t),\,0,\,1\right), & \text{Duty Cycle mode} \\
0,\ 0.5,\ \text{or }1, & \text{Two Stage mode}
\end{cases}
$$

where $\mathrm{clip}(x,0,1)$ limits the command to the interval $[0,1]$.

### Neural-network controller

The current NN controller is a supervised approximation of the PID duty-cycle controller:

- the NN is trained from simulated HVAC runs rather than external data files
- the teacher target is the PID duty-cycle cooling level
- the model is a one-hidden-layer multilayer perceptron
- hidden activation uses `tanh`
- output activation uses a sigmoid so the output stays between `0` and `1`
- the network input always includes temperature error and can optionally include:
  - ambient temperature
  - error trend

At training time, the app:

1. Simulates PID duty-cycle control on all built-in ambient profiles.
2. Adds the currently active ambient profile snapshot to the training set when available.
3. Collects feature vectors and PID cooling targets.
4. Normalizes the inputs.
5. Trains the NN with batch gradient descent in plain MATLAB.

After training, the NN can be enabled as a third controller in the comparison plot. If the room-model parameters, setpoint, PID gains, or NN feature/hyperparameter settings change, the app marks the NN model as stale but still allows it to run.

## Training summary and run statistics

The NN panel reports:

- `Training Status`
  `Untrained`, `Ready`, or `Stale`

- `Training Loss`
  Final mean-squared error from NN training

- `Model Features`
  Feature set stored with the trained model

- `Current Features`
  Feature set currently selected in the UI

- `Teacher`
  Currently fixed as `PID Duty Cycle`

The NN run statistics report:

- `NN Eqv Runtime`
  Equivalent runtime computed from the continuous cooling command

- `NN Duty`
  Mean cooling level expressed as a percentage

- `NN Avg Temp`
  Average indoor temperature over the day

- `Training Loss`
  The stored training loss for the currently loaded NN model

- `Model Status`
  Whether the model is `Ready`, `Stale`, or `Untrained`

## Future plans

This demo is designed to grow further. Planned future directions include:

- `Expose two-stage PID thresholds`
  The current two-stage PID thresholds are hardcoded in the MATLAB file and should be exposed to the user in a later version so they can be tuned directly from the app.
  The current hardcoded values are:
  - `stage1OnThreshold = 0.12`
  - `stage1OffThreshold = 0.05`
  - `stage2OnThreshold = 0.60`
  - `stage2OffThreshold = 0.40`

- `Neural-network direct objective`
  Replace PID-imitation training with a more ambitious NN training objective that directly minimizes temperature-tracking error instead of copying PID output.

- `NN staged-output option`
  Add a user-selectable NN actuator mode so the NN can run either:
  - continuous duty-cycle output in `0..1`
  - staged output at `0`, `0.5`, and `1`

- `Expose staged-controller hysteresis details`
  Expose the two-stage decision logic to the user later, including stage hysteresis, second-stage drop-back behavior, and anti-chatter tuning.

- `Classical vs AI comparison`
  Continue expanding the side-by-side comparison of thermostat, PID, and neural-network control on the same HVAC example.
