#!/usr/bin/env bash
# Builds the wallpaper picker's thumbnails. Runs every time Super + W opens.
#
# Fedora port changes vs upstream:
#  - one run at a time (flock): reopening the picker used to start a second
#    run writing the same files, leaving half-written thumbnails
#  - thumbnails are written to a temp file and renamed, so the picker never
#    loads a partial image
#  - parallel jobs capped at CPU count, one thread each: 20 ImageMagick
#    processes each using every core made the picker (and desktop) lag
#  - .webp included (the picker lists webp files but they were never cached)
#  - thumbnails of deleted wallpapers are removed

CONFIG="$1/config.json"

expand_home() {
    local path="$1"

    if [[ "$path" == '$HOME' ]]; then
        printf '%s\n' "$HOME"
    elif [[ "$path" == '$HOME/'* ]]; then
        printf '%s/%s\n' "$HOME" "${path#'$HOME/'}"
    else
        printf '%s\n' "$path"
    fi
}

wallpaper_path=$(expand_home "$(jq -r '.wallpaper_path' "$CONFIG")")
cache_path=$(expand_home "$(jq -r '.cache_path' "$CONFIG")")
cache_batch_size=$(jq -r '.cache_batch_size // 0' "$CONFIG")

mkdir -p "$cache_path"

exec 9>"$cache_path/.lock"
if ! flock -n 9; then
    echo "Thumbnail generation already running."
    exit 0
fi

# ImageMagick 7 uses `magick`; `convert` is a deprecated alias some distros drop
if command -v magick >/dev/null 2>&1; then
    im=(magick)
elif command -v convert >/dev/null 2>&1; then
    im=(convert)
else
    echo "ImageMagick not found (install ImageMagick); thumbnails can't be made." >&2
    exit 1
fi

cores=$(nproc 2>/dev/null || echo 2)
jobs_max=$cores
if [[ "$cache_batch_size" =~ ^[0-9]+$ ]] && (( cache_batch_size > 0 && cache_batch_size < cores )); then
    jobs_max=$cache_batch_size
fi

echo "Wallpaper path: $wallpaper_path"
echo "Cache path: $cache_path"
echo "Parallel jobs: $jobs_max"

# Drop thumbnails whose wallpaper is gone
for thumb in "$cache_path"/*; do
    [[ -f "$thumb" ]] || continue
    name=$(basename "$thumb")
    [[ "$name" == .* ]] && continue
    [[ -e "$wallpaper_path/$name" ]] || rm -f -- "$thumb"
done

make_thumb() {
    local img="$1" out="$2" tmp
    tmp="$(dirname "$out")/.tmp.$$.$RANDOM.$(basename "$out")"
    # -define jpeg:size lets the JPEG decoder downscale while reading (much faster on 4K+)
    if "${im[@]}" -limit thread 1 -define jpeg:size=2000x1000 "$img" \
            -thumbnail x500 -strip -quality 85 "$tmp" 2>/dev/null; then
        mv -f -- "$tmp" "$out"
    else
        rm -f -- "$tmp"
        echo "Failed: $(basename "$img")" >&2
    fi
}

while IFS= read -r -d '' img; do
    filename=$(basename "$img")
    out="$cache_path/$filename"

    # skip if a thumbnail exists and is newer than the wallpaper
    if [[ -f "$out" && "$out" -nt "$img" ]]; then
        continue
    fi

    echo "Generating thumbnail for $filename"
    make_thumb "$img" "$out" &

    while (( $(jobs -rp | wc -l) >= jobs_max )); do
        wait -n
    done
done < <(find "$wallpaper_path" -maxdepth 1 -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \
\) -print0)

wait
echo "Thumbnail generation complete."
