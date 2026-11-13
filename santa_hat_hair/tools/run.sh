#!/bin/bash
# usage: run.sh tag [close]
cd /tmp/claude-0/-home-user-ugc/fafe1d93-7aa1-5198-bd6e-efebdda97893/scratchpad/hat
B=../bvenv/bin/python
$B assemble3.py -- $PWD 2>&1 | grep -E "TRIS|rror|Trace|hair tris" || exit 1
$B uvbake.py -- $PWD 2>&1 | grep -iE "error|Trace"
python3 tex.py 2>&1 | grep -iE "error|Trace"
$B mktex.py -- $PWD 2>&1 | grep -iE "error|Trace"
$B rview.py -- $PWD/tex.blend $PWD/$1 1.6 700 6.2 2>&1 | grep -iE "error|Trace"
$B rview.py -- $PWD/tex.blend $PWD/$1c 1.6 900 3.6 close 2>&1 | grep -iE "error|Trace"
ls $1_sheet.png $1c_sheet.png
