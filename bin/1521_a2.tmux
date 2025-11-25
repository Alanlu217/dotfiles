#!/usr/bin/env bash

SESSION="1521_a2"
CWD="/data/unsw/comp/1521_code/a2"

# If the session exists, just attach
tmux has-session -t $SESSION 2>/dev/null
if [ $? -eq 0 ]; then
    tmux attach -t $SESSION
    exit 0
fi

tmux new-session -d -s $SESSION -c "$CWD" -x- -y-
tmux send-keys -t $SESSION:1.0 'helix aif-tools.c' C-m
tmux split-window -h -t $SESSION:1.0 -c "$CWD"
tmux split-window -v -p 95 -t $SESSION:1.1 -c "$CWD"
tmux resize-pane -t $SESSION:1.1 -y 5
tmux send-keys -t $SESSION:1.2 'ssh -t vlab "cd 1521_code/a2; clear; bash -i"' C-m
tmux select-pane -t $SESSION:1.0
tmux attach -t $SESSION
