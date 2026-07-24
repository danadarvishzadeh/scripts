# Agent Instructions

## Project

- This repository contains Bash scripts for Linux server administration. 

## Runtime And Dependencies

- Use Bash, not `sh`: the script relies on arrays, `mapfile`, `[[ ]]`, `local`, and `set -euo pipefail`.

## Implementation Conventions

- Keep changes focused on the script and preserve strict mode, quoted arguments, explicit dependency checks, and the `run_command` logging pattern.
- Validate all arguments and external data before mutating system state.
- Avoid introducing dependencies or broad refactors without a clear operational need.

## Documentation

- Update [README.md](README.md) when command-line usage, dependencies, firewall behavior, or operational warnings change.
- Do not claim that rules persist across reboot unless persistence is explicitly implemented and documented.