# UIC Mechanical and Industrial Engineering - AI Examples for Required Courses

This repository collects course-connected examples showing how artificial intelligence, machine learning, and modern computational tools can be used to solve real engineering problems across the required Mechanical and Industrial Engineering curriculum at UIC.

Rather than presenting AI as a separate topic, these examples are designed to connect directly to familiar subjects from required courses. Each folder demonstrates how an AI or ML approach can be paired with a traditional engineering method, numerical technique, or design problem so students can see both the underlying course concept and a modern computational extension of it.

The overall goal is to give students and instructors practical, concrete examples of how AI-assisted modeling, optimization, and approximation can support engineering analysis, mechanism design, and data-driven problem solving.

## Repository overview

### `ME320`

`ME320` contains a MATLAB app for mechanism synthesis using a genetic algorithm. The example focuses on four-bar and multi-bar linkage path generation, where a target path is specified and the solver searches for mechanism parameters that reproduce it as closely as possible.

This folder highlights how an AI-inspired optimization method can be used in a classical mechanical design setting:

- a user-defined or example path is treated as the design target
- a population-based search explores candidate linkage geometries
- candidates are scored by path error
- the best designs evolve over generations toward improved motion synthesis

This example connects machine intelligence ideas such as population search, mutation, crossover, and fitness-based selection to traditional mechanism design and kinematics.

### `ME328`

`ME328` contains a MATLAB derivative-comparison demo that contrasts a standard finite-difference approximation with a small manually trained neural network. A polynomial function is sampled on a uniform grid, differentiated using second-order finite differences, then learned with a one-hidden-layer neural network whose derivative is obtained analytically from the trained model.

This folder shows how a familiar numerical methods topic can be compared directly with an ML-based function approximation workflow:

- finite differences provide the classical numerical derivative
- a neural network learns the sampled function data
- the trained network is differentiated analytically using the chain rule
- plots, tables, and error metrics show how the two derivative estimates compare

This example is especially useful for illustrating the relationship between traditional numerical analysis and data-driven modeling.

## Why this repository exists

Engineering students increasingly encounter AI and ML tools in industry, research, and advanced coursework. This repository is intended to make those ideas approachable by grounding them in topics they already study in required classes. The examples are meant to be readable, modifiable, and discussion-friendly, so they can support lecture demonstrations, student exploration, and future expansion into other courses.

## Credit

Developed by **Jon Komperda, PhD**  
Clinical Associate Professor and Director of Undergraduate Studies

[Faculty Profile](https://mie.uic.edu/profiles/jonathan-komperda/) || [LinkedIn](https://www.linkedin.com/in/jkomperda/)

## License

[![Creative Commons License: CC BY-NC-ND 4.0](https://licensebuttons.net/l/by-nc-nd/4.0/88x31.png)](https://creativecommons.org/licenses/by-nc-nd/4.0/deed.en)

This repository is licensed under the **Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International License (CC BY-NC-ND 4.0)**.

### You are free to

- **Share** the material in any medium or format

### Under the following terms

- **Attribution**: You must give appropriate credit, provide a link to the license, and indicate if changes were made.
- **NonCommercial**: You may not use the material for commercial purposes.
- **NoDerivatives**: If you remix, transform, or build upon the material, you may not distribute the modified material.
- **No additional restrictions**: You may not apply legal terms or technological measures that legally restrict others from doing anything the license permits.

For the full human-readable summary, see the [CC BY-NC-ND 4.0 deed](https://creativecommons.org/licenses/by-nc-nd/4.0/deed.en).  
For the complete legal text, see the [official legal code](https://creativecommons.org/licenses/by-nc-nd/4.0/legalcode.en).
