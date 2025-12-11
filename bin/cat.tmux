#!/usr/bin/env sh

SESSION="cat"
CWD="/data/dev/cat-trap"

# If the session exists, just attach
tmux has-session -t $SESSION 2>/dev/null
if [ $? -eq 0 ]; then
    tmux kill-session -t $SESSION
fi

tmux new-session -d -s $SESSION -c "$CWD" -x- -y-

tmux send-keys -t $SESSION:1.0 'helix src/main.rs' C-m
tmux splitw -h -c "$CWD"
tmux selectw -t $SESSION:1.0
tmux resize-pane -R 20
tmux attach -t $SESSION
