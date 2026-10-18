# HEAT_SOAK body, loaded by heat_soak.cfg via Kalico's "!!include".
# Kalico injects params, printer, emit, sleep, math, etc. as globals.
# ruff: noqa: F821
# pyright: reportUndefinedVariable=false

sensor = "temperature_sensor chamber_temp"
target_chamber = int(float(params.get("CHAMBER", 45)))
target_chamber_minimal = int(float(params.get("CHAMBER_MINIMAL", 0)))
soak = int(float(params.get("SOAK", 0)))
poll = 10
minimal = target_chamber_minimal if target_chamber_minimal > 0 else target_chamber
target = max(target_chamber, minimal)
if target <= 0:
    # printer-specific status indicator, no-op where not supported
    emit('_HEAT_SOAK_SKIPPED_NOTIFY MSG="⏭️ No chamber target set. Skipping heat soak..."')
else:
    emit(f'_HEAT_SOAK_NOTIFY MSG="♨️ Heat soak until chamber reaches {minimal}C..."')
    # run cooling fans at full power to circulate air
    emit("M106 S255")
    emit(f'TEMPERATURE_WAIT SENSOR="{sensor}" MINIMUM={minimal}')
    if soak > 0 and target > minimal:
        emit(f'_HEAT_SOAK_NOTIFY MSG="⏳ Chamber at {minimal}C, soaking up to {round(soak / 60, 1)} min toward {target}C..."')
        # sleep() is interruptible, so a cancel mid-soak aborts here
        for _ in range(math.ceil(soak / poll)):
            if printer[sensor]["temperature"] >= target:
                break
            sleep(poll)
    emit("M107")
emit("M117")
