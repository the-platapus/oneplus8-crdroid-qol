#!/vendor/bin/sh
# Lowers the kernel's skin-temperature throttling trip points by 4°C.
# Installed as /odm/bin/thermal_tune.sh and run once at boot (odm_overlay.rc).
# It's labeled as thermal-engine's executable so it runs in that SELinux domain,
# one of only two allowed to write trip points. That domain can't run toybox,
# so this uses shell builtins only.
#
# Values are in millidegrees C, trip 0 first. Stock values in comments.
SKIN_THERM="42000 43000 44000 46000"     # 46000 47000 48000 50000
SKIN_MSM_THERM_STEP="59000 61000"        # 63000 65000

set_trips() {  # <zone type> <temps...>
    want=$1; shift
    for z in /sys/class/thermal/thermal_zone*; do
        read -r t < "$z/type" || continue
        [ "$t" = "$want" ] || continue
        i=0
        for v in "$@"; do
            echo "$v" > "$z/trip_point_${i}_temp"
            i=$((i + 1))
        done
    done
}

set_trips skin-therm $SKIN_THERM
set_trips skin-msm-therm-step $SKIN_MSM_THERM_STEP
