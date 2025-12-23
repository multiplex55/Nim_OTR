# Nim build configuration for Nim_OTR
# Targets Windows GUI binaries with ARC/ORC memory management and profile-aware flags.

# Platform and application type
switch("os", "windows")
switch("app", "gui")
# Always link as a GUI subsystem binary so the EXE never spawns a console window.
switch("subsystem", "windows")

# Prefer ORC; allow ARC if explicitly requested.
if defined(arc):
  switch("mm", "arc")
else:
  switch("mm", "orc")

# Profile-specific settings
when defined(release):
  switch("opt", "speed")
  switch("checks", "off")
  switch("assertions", "off")
  switch("debuginfo", "off")
  # Logging stays off unless explicitly re-enabled with -d:enableLogging
else:
  # Debug-friendly defaults
  switch("assertions", "on")
  switch("debuginfo", "2")
  define("enableLogging")
