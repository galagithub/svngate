#!/bin/sh

set -eu

SVNSERVE_PID=""
APACHE_PID=""
STOPPING=0
SIGNAL_RECEIVED=0

cleanup() {

    if [ "$STOPPING" -eq 1 ]; then
        return 0
    fi

    STOPPING=1

    echo "Stopping svngate..."

    if [ -n "$APACHE_PID" ] && kill -0 "$APACHE_PID" 2>/dev/null; then
        echo "Stopping Apache..."
        kill -TERM "$APACHE_PID" 2>/dev/null || true
    fi

    if [ -n "$SVNSERVE_PID" ] && kill -0 "$SVNSERVE_PID" 2>/dev/null; then
        echo "Stopping svnserve..."
        kill -TERM "$SVNSERVE_PID" 2>/dev/null || true
    fi

    wait "$APACHE_PID" 2>/dev/null || true
    wait "$SVNSERVE_PID" 2>/dev/null || true

    echo "svngate stopped."
}

handle_signal() {
    SIGNAL_RECEIVED=1
    echo "Received shutdown signal."
    cleanup
}

trap handle_signal TERM INT HUP

echo "Starting svnserve..."

svnserve \
    --daemon \
    --foreground \
    --root /var/svn \
    --listen-port 3690 &

SVNSERVE_PID=$!

echo "svnserve PID: $SVNSERVE_PID"

echo "Starting Apache..."

httpd -D FOREGROUND &

APACHE_PID=$!

echo "Apache PID: $APACHE_PID"

# Watch both daemons. If either one dies, tear the other one down and exit
# non-zero so Docker's restart policy can bring the container back cleanly.
while kill -0 "$APACHE_PID" 2>/dev/null && kill -0 "$SVNSERVE_PID" 2>/dev/null; do
    sleep 2
done

# A shutdown signal means this exit is intentional, not a failure.
if [ "$SIGNAL_RECEIVED" -eq 1 ]; then
    exit 0
fi

cleanup

echo "A daemon exited unexpectedly. Stopping container so it can be restarted."
exit 1
