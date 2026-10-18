# HEAT_SOAK body, loaded by heat_soak.cfg via Kalico's "!!include".
# Kalico injects params, printer, emit, sleep, math, etc. as globals.
# ruff: noqa: F821, PLW0604
# pyright: reportUndefinedVariable=false

# Kalico execs with a separate locals dict; "global" lets these functions call each other
global chamber_temp, notify, notify_skipped, start_circulating_air
global stop_circulating_air, clear_lcd_status, wait_for_chamber_minimum
global soak_toward_target


def chamber_temp(sensor):
    return printer[sensor]["temperature"]


def notify(msg):
    emit(f'_HEAT_SOAK_NOTIFY MSG="{msg}"')


def notify_skipped():
    # printer-specific status indicator, no-op where not supported
    emit(
        '_HEAT_SOAK_SKIPPED_NOTIFY MSG="⏭️ No chamber target set. Skipping heat soak..."'
    )


def start_circulating_air():
    # run cooling fans at full power to circulate air
    emit("M106 S255")


def stop_circulating_air():
    emit("M107")


def clear_lcd_status():
    emit("M117")


def wait_for_chamber_minimum(sensor, minimum_temp):
    emit(f'TEMPERATURE_WAIT SENSOR="{sensor}" MINIMUM={minimum_temp}')


def soak_toward_target(
    sensor,
    target_temp,
    max_soak_seconds,
    poll_seconds,
    stall_window_seconds,
    stall_rise_temp,
):
    stall_steps = math.ceil(stall_window_seconds / poll_seconds)
    ref_temp = chamber_temp(sensor)
    steps = 0

    # sleep() is interruptible, so a cancel mid-soak aborts here
    for _ in range(math.ceil(max_soak_seconds / poll_seconds)):
        temp = chamber_temp(sensor)

        if temp >= target_temp:
            return

        if stall_window_seconds > 0 and steps >= stall_steps:
            if temp - ref_temp < stall_rise_temp:
                notify(
                    f"📉 Chamber stalled at {temp:.1f}C (+{temp - ref_temp:.1f}C in {round(stall_window_seconds / 60, 1)} min), ending soak..."
                )
                return

            ref_temp = temp
            steps = 0

        sleep(poll_seconds)
        steps += 1


chamber_param = int(float(params.get("CHAMBER", 45)))
chamber_minimal_param = int(float(params.get("CHAMBER_MINIMAL", 0)))
max_soak_seconds = int(float(params.get("SOAK", 0)))
# end the soak early if the chamber rises less than STALL_RISE C per STALL_WINDOW s (0 = off)
stall_window_seconds = int(float(params.get("STALL_WINDOW", 300)))
stall_rise_temp = float(params.get("STALL_RISE", 0.7))

sensor = "temperature_sensor chamber_temp"
poll_seconds = 10
minimum_temp = chamber_minimal_param if chamber_minimal_param > 0 else chamber_param
target_temp = max(chamber_param, minimum_temp)

if target_temp <= 0:
    notify_skipped()
else:
    notify(f"♨️ Heat soak until chamber reaches {minimum_temp}C...")
    start_circulating_air()
    wait_for_chamber_minimum(sensor, minimum_temp)

    if max_soak_seconds > 0 and target_temp > minimum_temp:
        notify(
            f"⏳ Chamber at {minimum_temp}C, soaking up to {round(max_soak_seconds / 60, 1)} min toward {target_temp}C, or until it stops rising..."
        )
        soak_toward_target(
            sensor,
            target_temp,
            max_soak_seconds,
            poll_seconds,
            stall_window_seconds,
            stall_rise_temp,
        )

    stop_circulating_air()

clear_lcd_status()
