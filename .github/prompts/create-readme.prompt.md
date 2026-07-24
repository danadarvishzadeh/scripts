---
name: "Create Project or Feature README"
description: "Create or update a factual README for a project or feature by inspecting the workspace, preserving local conventions, and documenting verified usage and operational risks."
argument-hint: "Describe the project or feature, target README path, and any audience or content requirements"
agent: "agent"
---
Create a README for the requested project or feature.

## Inputs
- Request: ${input:request:Describe the project or feature to document}
- Target README path: ${input:targetPath:Path to the README, such as README.md or allow_cf/README.md}
- Optional audience or requirements: ${input:requirements:Audience, required sections, or constraints}

## Workflow
1. Inspect the target directory and relevant source files, scripts, configuration, tests, and existing documentation before writing.
2. Read and follow the repository's `AGENTS.md`, `copilot-instructions.md`, and nearby documentation conventions when present.
3. Determine whether the target is a project README or a feature README. Keep the scope limited to that project or feature.
4. Document only behavior, commands, dependencies, ports, firewall effects, persistence, and operational warnings that are supported by the inspected files. Mark uncertain details for clarification instead of guessing.
5. Preserve existing README content unless the request explicitly asks for a rewrite. When updating a README, make the smallest coherent change and keep headings and terminology consistent.
6. Use copyable code blocks for commands and examples. Use tables only when they improve scanning. Keep prose concise and task-oriented.
7. For Bash or Linux administration projects, use Bash syntax in examples, quote arguments, identify required privileges and external dependencies, explain system-state changes, and state whether behavior persists across reboot only when persistence is implemented and verified.
8. Include the sections that fit the target: overview, prerequisites, installation or setup, usage, options or inputs, examples, behavior, verification or troubleshooting, and warnings or limitations. Do not add empty sections.
9. If the README already exists, check links, command examples, and claims against the current implementation after editing.

## Output
- Write the README at the requested target path.
- Finish with a brief summary of what was documented and list any unresolved questions or facts that could not be verified.
- Do not claim that tests, commands, or deployments were run unless you actually ran them.
