# idea.md

## Project Overview

This project implements an **environment-aware property-based testing (PBT) framework** for distributed systems using Nix and NixOS. The goal is to systematically explore how variations in execution environments affect system correctness, going beyond traditional input-focused testing.

Instead of testing only application-level inputs, this framework treats **system configuration as a first-class test dimension**, enabling automated generation and evaluation of diverse environments.

---

## Core Concepts

### 1. Property-Based Testing (PBT)

* Tests assert **invariants (properties)** rather than specific outputs.
* Properties must hold across a wide range of generated configurations.
* Example properties:

  * System eventually becomes consistent
  * Nodes can communicate under allowed conditions
  * Service remains available under restarts
  * No unexpected crashes occur

---

### 2. Environment-Aware Testing

The framework explores variations in:

* Network configuration (IP ranges, topology, latency assumptions)
* Filesystem types and layouts
* Dependency versions
* System services and daemons
* User permissions and isolation
* Kernel/system-level parameters

Each variation defines a **test case environment**, not just input data.

---

### 3. Nix as a Test Generator

Nix is used to:

* Define configurations as **pure functions**
* Generate **combinatorial test spaces**
* Ensure **reproducibility and determinism**
* Build **isolated system environments**

Key principle:

> Tests are generated, not written individually.

---

### 4. NixOS Test Framework

Tests are executed using NixOS VM-based integration tests:

* Each test defines one or more **nodes (VMs)**
* Nodes are instantiated from parametrized configurations
* Test logic is executed via `testScript`

---

## Example Property Categories

### Connectivity

* Nodes can reach each other when allowed

### Availability

* Service responds within time constraints

### Fault Tolerance

* System survives node/service failure

### Configuration Robustness

* System behaves correctly under varying environments

---

## Systems Under Test

The framework is designed to evaluate distributed systems such as:

* etcd
* Kafka

These systems are sensitive to:

* network conditions
* storage backends
* version mismatches

---

## Limitations

* No native randomness in Nix
* No automatic shrinking (must be external)
* VM-based tests can be slow
* State space must be carefully bounded

