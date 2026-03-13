# HVAC PID / Neural Network Control Demo
### *by Jon Komperda, PhD*

`hvac_pid_nn_control_demo.m` is an interactive MATLAB teaching app for introductory HVAC temperature control. The current version compares two controllers on the same cooling-only room model:

- a basic on/off thermostat with hysteresis
- a cooling-only PID controller with tunable `Kp`, `Ki`, and `Kd`

The app still keeps the broader `pid_nn` framing because the long-term goal is to compare classical control ideas with future neural-network-based control extensions.

## Running the demo

Run the file from the `ME312` folder or add that folder to your MATLAB path first.

## What the app does

At a high level, the workflow is:

1. Load a built-in ambient temperature profile or click points to define a custom profile over a 24-hour window.
2. Set the room-model, basic thermostat, and PID parameters.
3. Run the HVAC simulation.
4. Compare the thermostat and PID temperature responses, controller effort, and summary metrics.

This makes the app useful for discussing how a simple hysteresis controller differs from a continuous PID controller under the same outdoor disturbance.

## Current scope

The current version includes:

- three built-in ambient profiles:
  - `Summer Warm-Up`
  - `Heat-Wave Spike`
  - `Day-Night Cycle`
- manual point-based ambient profile creation by clicking in the left plot
- a simple first-order cooling-room model
- a shared setpoint used by both controllers
- a basic thermostat with hysteresis (deadband)
- a PID controller with two selectable actuation modes:
  - `Duty Cycle`
    continuous PWM-like cooling between `0` and `1`
  - `Two Stage`
    staged cooling levels at `0`, `0.5`, and `1`
- a right-side comparison plot showing:
  - outdoor temperature
  - thermostat indoor temperature
  - PID indoor temperature
  - setpoint
  - thermostat control output
  - PID cooling level
- an optional 3-second animation of the comparison plot
- controller enable checkboxes so the thermostat and PID can be run independently
- a run-statistics summary inside the control panel comparing controller runtime, duty cycle, and average indoor temperature

## Inputs you can change

The control panel is divided into three sections:

### Room Model

- `Initial Indoor (degF)`
  Starting room temperature at the beginning of the day.

- `Room Response (1/hr)`
  A simple thermal-response coefficient that pulls the indoor temperature toward the ambient temperature.

- `AC Cooling (degF/hr)`
  The maximum cooling strength applied when the controller command is fully on.

### Basic Thermostat

- `Enable`
  Turns the thermostat comparison path on or off.

- `Setpoint (degF)`
  Shared indoor target temperature for both controllers.

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
    maps the PID demand to stepped cooling levels at `0`, `0.5`, and `1` using lower and higher demand bands so stage 1 engages earlier and stage 2 engages only at stronger cooling demand

This creates a classroom-friendly comparison between rule-based switching and continuous feedback control.

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

## Future plans

This demo is designed to grow further. Planned future directions include:

- `Expose two-stage PID thresholds`
  The current two-stage PID thresholds are hardcoded in the MATLAB file and should be exposed to the user in a later version so they can be tuned directly from the app.
  The current hardcoded values are:
  - `stage1OnThreshold = 0.12`
  - `stage1OffThreshold = 0.05`
  - `stage2OnThreshold = 0.60`
  - `stage2OffThreshold = 0.40`

- `Neural-network extension`
  Add a neural-network-based temperature-control component, such as a learned room-response predictor or a data-driven supervisory controller.

- `Classical vs AI comparison`
  Compare thermostat control, PID control, and neural-network-assisted control on the same HVAC example.

- `Expanded teaching workflow`
  Use the same app to discuss the tradeoffs among:
  - simple rule-based control
  - classical feedback control
  - data-driven / AI-based control
