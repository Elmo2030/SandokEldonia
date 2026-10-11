#!/bin/bash
# Synthetic test media for the player checks (no copyrighted content): ffmpeg test patterns with a visible timestamp/counter, a sine
# tone, two audio tracks and two subtitle tracks. Usage: ios/UITests/Fixtures/make-media.sh <output dir>   (needs ffmpeg with libx264)
set -euo pipefail
OUT="${1:?output dir}"; mkdir -p "$OUT"; cd "$OUT"
printf '1\n00:00:00,000 --> 00:03:00,000\nThis is the English subtitle track\n' > en.srt
printf '1\n00:00:00,000 --> 00:03:00,000\nזוהי כתובית בעברית\n' > he.srt
printf '1\n00:00:00,000 --> 00:00:24,000\nEpisode subtitle\n' > ep.srt     # as long as the episode: a longer cue would make the file longer than its video
V="-c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -b:a 64k"
# movie: 3 minutes, keyframe every second, English + Hebrew audio, English + Hebrew subtitles
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc=size=1280x720:rate=25:duration=180" -f lavfi -i "sine=frequency=440:duration=180" \
  -f lavfi -i "sine=frequency=660:duration=180" -i en.srt -i he.srt -map 0:v -map 1:a -map 2:a -map 3 -map 4 $V -g 25 -b:v 600k -c:s srt \
  -metadata:s:a:0 language=eng -metadata:s:a:0 title=English -metadata:s:a:1 language=heb -metadata:s:a:1 title=Hebrew \
  -metadata:s:s:0 language=eng -metadata:s:s:1 language=heb vod.mkv
# two 25 second episodes (up next), the same pattern with a different tone
for n in 1 2; do
  ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=25" -f lavfi -i "sine=frequency=$((300+n*100)):duration=25" \
    -i ep.srt -map 0:v -map 1:a -map 2 $V -g 25 -b:v 400k -c:s srt -metadata:s:s:0 language=eng ep$n.mkv
done
# a 15 minute "live" transport stream
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=900" -f lavfi -i "sine=frequency=330:duration=900" \
  $V -g 50 -b:v 400k -f mpegts live.ts
ls -la
