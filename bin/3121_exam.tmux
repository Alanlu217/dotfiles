#!/usr/bin/env sh

SESSION="3121_exam"
CWD="/data/unsw/comp/3121_code"

# If the session exists, just attach
tmux has-session -t $SESSION 2>/dev/null
if [ $? -eq 0 ]; then
    tmux kill-session -t $SESSION
fi

tmux new-session -d -s $SESSION -c "$CWD" -x- -y-

tmux send-keys -t $SESSION:1.0 'helix exam_notes.typ' C-m
tmux neww -c "$CWD"
tmux send-keys -t $SESSION:2.0 'wtyp exam_notes.typ' C-m
tmux selectw -t $SESSION:1.0
tmux attach -t $SESSION
