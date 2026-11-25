#!/usr/bin/env bash
# Renders the scripted gameplay scenarios offscreen (Xvfb + OpenGL compatibility renderer).
cd "$(dirname "$0")"
for s in ${@:-onfoot driving traffic police signals damage explosion wasted shooting driveby cars v4_steal v4_carjack v4_footcops v4_roadblock v4_swat v4_respray v4_busted v4_hospital v4_phone v4_gangs v4_crusher v4_shop v4_frenzy v4_mug}; do
  timeout 60 xvfb-run -a -s "-screen 0 1280x720x24" ./tools/godot --path . --rendering-driver opengl3 \
    --resolution 1280x720 --position 0,0 -- --shot=$s 2>&1 | grep -E "SAVED|ERROR|SCRIPT|error" | head -20
done
