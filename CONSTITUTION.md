
# TUTTO OS Constitution

## Purpose

TUTTO OS is a visual trading operating system.
Preserve trading logic at all times.

## Immutable Rules

The following MUST NEVER be modified without explicit approval.

- RCI calculation
- Fibonacci calculation
- STATE calculation
- Entry logic
- TP / SL calculation
- Risk calculation

Only visualization and UI may be changed.

## Architecture

Engine
 ↓
Snapshot
 ↓
UI Layer
 ↓
Renderer
 ↓
ObjectManager
 ↓
MT5

## Compilation Rules

- One version per module
- No duplicate indicators
- No experimental code in stable branch
- No non-MQL code
- 0 errors
- 0 warnings

## Stable Baseline

Version:
v1.0.0-STABLE

This version is the immutable baseline.
