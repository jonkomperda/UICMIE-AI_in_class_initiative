# HVAC PID / Neural Network Control Demo
### *by Jon Komperda, PhD*

`hvac_pid_nn_control_demo.m` is an interactive MATLAB teaching app for introductory HVAC temperature control. The first version is intentionally simple: it uses a cooling-only room model and an on/off thermostat controller, while the file and app framing leave room for later PID and neural-network control extensions.

## Running the demo

In MATLAB:

Run the file from the `ME312` folder or add that folder to your MATLAB path first.

## What the app does

At a high level, the workflow is:

1. Load a built-in ambient temperature profile or click points to define a custom profile over a 24-hour window.
2. Set the thermostat and room-model parameters.
3. Run the HVAC simulation.
4. Compare the ambient disturbance, indoor temperature response, setpoint, and AC on/off history.

This makes the app useful for discussing how a simple thermostat responds to changing outdoor conditions and why more advanced control strategies may be desirable.

## Current v1 scope

The first version includes:

- three built-in ambient profiles:
  - `Summer Warm-Up`
  - `Heat-Wave Spike`
  - `Day-Night Cycle`
- manual point-based ambient profile creation by clicking in the left plot
- a simple first-order cooling-room model
- an on/off thermostat with hysteresis (deadband)
- a right-side result plot showing:
  - ambient temperature
  - indoor temperature
  - setpoint
  - AC on/off state

The app name includes `pid_nn` because it is meant to grow into a larger control-comparison demo, but v1 only runs the thermostat-style on/off control mode.

## Inputs you can change

The control panel exposes a small set of teaching-friendly parameters:

- `Setpoint (degF)`
  Desired indoor temperature.

- `Deadband (degF)`
  Thermostat hysteresis width. This prevents rapid switching near the setpoint.

- `Initial Indoor (degF)`
  Starting room temperature at the beginning of the day.

- `Room Response (1/hr)`
  A simple thermal-response coefficient that pulls the indoor temperature toward the ambient temperature.

- `AC Cooling (degF/hr)`
  The cooling strength applied when the air conditioner is on.

## Simple thermal model

The room is modeled as a single thermal state:

- ambient temperature acts as an external disturbance
- the room temperature drifts toward ambient temperature at a user-controlled rate
- the AC removes heat at a fixed rate whenever the controller commands it on

This is not intended to be a high-fidelity building model. It is an educational example that keeps the dynamics easy to explain and modify.

## On/off control logic

The current controller is a thermostat with hysteresis:

- AC turns on when the indoor temperature rises above `setpoint + deadband/2`
- AC turns off when the indoor temperature falls below `setpoint - deadband/2`
- inside that band, the controller keeps the previous on/off state

This makes it easy to show how thermostat deadband affects comfort and switching behavior.

## Future plans

This demo is designed to grow in stages. Planned future directions include:

- `PID control mode`
  Add a classical PID controller with tunable `Kp`, `Ki`, and `Kd` gains so students can compare thermostat control with proportional-integral-derivative control.

- `Controller comparison`
  Allow side-by-side comparisons between on/off control and PID control for the same ambient profile and setpoint.

- `Neural-network extension`
  Add a neural-network-based temperature-control component, such as:
  - a learned room-response predictor
  - a data-driven controller or adaptive supervisory controller
  - a comparison between classical model-based control and AI-assisted control

- `Teaching comparison workflow`
  Use the same HVAC example to discuss the tradeoffs among:
  - simple rule-based control
  - classical feedback control
  - data-driven / AI-based control

