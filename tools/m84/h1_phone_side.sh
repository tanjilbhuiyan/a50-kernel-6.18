#!/bin/sh
# M8.4 H1 phone-side test (runs detached; survives a USB-networking drop): passive capture of the "Hall sensors" input
# from 40 s to 280 s; three 300 ms vibration pulses at ~85 s through /sys/class/leds/vibrator (duration/state/activate,
# the interface the vendor HAL and hfd-service use), with the motor GPIO read during and after each pulse. Findings are
# written to /dev/kmsg at ~395 s for the 420 s timed dump. Writes only the vibrator LED attributes.
D=/run/a50-k1
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
k() { echo "<6>A50H1: $*" > /dev/kmsg; }
gpioline() { grep -E 'vibrator' /sys/kernel/debug/gpio 2>/dev/null | tr -s ' ' | head -n 1; }
wait_up 40
timeout 250 $D/evcap "Hall sensors" 240 > $D/hall.txt 2>&1 &
V=/sys/class/leds/vibrator
{
    echo "attrs $(ls $V 2>&1 | tr '\n' ' ')"
    echo "trigger $(cat $V/trigger 2>&1 | tr -s ' ' | cut -c1-200)"
    echo "brightness $(cat $V/brightness 2>&1) max $(cat $V/max_brightness 2>&1)"
    echo "gpio_idle $(gpioline)"
} > $D/vib.txt
wait_up 85
for n in 1 2 3; do
    t0=$(cut -d' ' -f1 /proc/uptime)
    echo 300 > $V/duration 2>>$D/vib.txt; r1=$?
    echo 1 > $V/state 2>>$D/vib.txt; r2=$?
    echo 1 > $V/activate 2>>$D/vib.txt; r3=$?
    sleep 0.1
    during="$(cat $V/activate 2>&1) $(gpioline)"
    sleep 0.5
    after="$(cat $V/activate 2>&1) $(gpioline)"
    echo "pulse $n t=$t0 rc=$r1/$r2/$r3 during: $during | after: $after" >> $D/vib.txt
    sleep 1
done
wait_up 395
while read -r l; do k "vib $(echo "$l" | cut -c1-220)"; done < $D/vib.txt
k "hall $(grep 'type 5 code' $D/hall.txt | awk '{print $1":"$5"="$7}' | tr '\n' ' ' | cut -c1-900)"
k "hallsummary $(grep -E '^device|summary' $D/hall.txt | tr '\n' ' ')"
