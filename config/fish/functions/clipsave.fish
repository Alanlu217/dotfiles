function clipsave
    mkdir -p (dirname $argv[1]); and wl-paste >$argv[1]; and echo -n "#image(\"$argv[1]\")" | wl-copy
end
