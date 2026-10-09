#!/bin/sh

set -eu

SVN_ROOT="/var/svn"
AUTH_ROOT="/etc/apache2/svn-auth"
GENERATED_CONFIG="/etc/apache2/svn-repositories.conf"
CERT_DIR="/etc/apache2/certs"

echo
echo "=============================================="
echo " svngate"
echo "=============================================="
echo

mkdir -p \
    "$SVN_ROOT" \
    "$AUTH_ROOT" \
    "$CERT_DIR" \
    /run/apache2

# ============================================================
# Apache repository configuration
# ============================================================

rm -f "$GENERATED_CONFIG"

touch "$GENERATED_CONFIG"


# ============================================================
# WebSVN configuration
# ============================================================

WEBSVN_CONFIG="/var/www/websvn/include/config.php"

cat > "$WEBSVN_CONFIG" <<'PHP'
<?php

/*
 * svngate WebSVN configuration.
 *
 * Generated at container startup.
 */

$config->setDefaultLanguage('english');

/*
 * WebSVN templates.
 *
 * The first template added becomes the default.
 */
$config->addTemplatePath(
    $locwebsvnreal . '/templates/calm/'
);

$config->addTemplatePath(
    $locwebsvnreal . '/templates/BlueGrey/'
);

$config->addTemplatePath(
    $locwebsvnreal . '/templates/Elegant/'
);

/*
 * WebSVN is intentionally UNAUTHENTICATED for now.
 *
 * Authentication will be added here later.
 */

/*
 * Repositories are added below automatically.
 */

PHP

# ============================================================
# Discover and add repositories
# ============================================================

for repo in "$SVN_ROOT"/*; do

    [ -d "$repo" ] || continue

    # A real SVN repository has both "db" and "format" directories
    if [ ! -d "$repo/db" ] || [ ! -f "$repo/format" ]; then
        continue
    fi

    REPO_NAME="$(basename "$repo")"

    echo "Adding WebSVN repository: $REPO_NAME"

    cat >> "$WEBSVN_CONFIG" <<PHP

\$config->addRepository(
    '$REPO_NAME',
    'file://$repo'
);

PHP

done

# ============================================================
# Repository discovery
# ============================================================

REPOSITORIES=0

for repo in "$SVN_ROOT"/*; do

    [ -d "$repo" ] || continue

    # --------------------------------------------------------
    # Determine whether this is actually an SVN repository.
    # --------------------------------------------------------

    if [ ! -d "$repo/db" ]; then
        continue
    fi

    if [ ! -f "$repo/format" ]; then
        continue
    fi

    REPO_NAME="$(basename "$repo")"

    PASSWD="$repo/conf/passwd"
    AUTHZ="$repo/conf/authz"

    echo "Found SVN repository: $REPO_NAME"

    REPOSITORIES=$((REPOSITORIES + 1))


    # ========================================================
    # Apache authentication file
    # ========================================================

    AUTH_FILE="$AUTH_ROOT/$REPO_NAME"

    rm -f "$AUTH_FILE"

    touch "$AUTH_FILE"

    chmod 640 "$AUTH_FILE"


    if [ -f "$PASSWD" ]; then

        echo "  Reading users from:"
        echo "    $PASSWD"

        IN_USERS_SECTION=0

        while IFS= read -r line || [ -n "$line" ]; do

            # Remove CR from Windows-style files.
            line="$(printf '%s' "$line" | tr -d '\r')"

            # Trim leading/trailing whitespace.
            line="$(printf '%s' "$line" \
                | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

            [ -n "$line" ] || continue

            case "$line" in
                \#*)
                    continue
                    ;;
            esac

            # Only read [users].
            case "$line" in
                "[users]")
                    IN_USERS_SECTION=1
                    continue
                    ;;
                "[")
                    IN_USERS_SECTION=0
                    continue
                    ;;
            esac

            [ "$IN_USERS_SECTION" -eq 1 ] || continue

            case "$line" in
                *=*)
                    ;;
                *)
                    continue
                    ;;
            esac

            username="$(printf '%s' "$line" \
                | cut -d '=' -f 1 \
                | sed 's/[[:space:]]*$//')"

            password="$(printf '%s' "$line" \
                | cut -d '=' -f 2- \
                | sed 's/^[[:space:]]*//')"

            [ -n "$username" ] || continue

            echo "    user: $username"

            # ------------------------------------------------
            # SVN passwd files are plaintext.
            #
            # Apache cannot consume an SVN passwd file
            # directly, so create a separate bcrypt database.
            # ------------------------------------------------

            htpasswd \
                -B \
                -b \
                "$AUTH_FILE" \
                "$username" \
                "$password" \
                >/dev/null

        done < "$PASSWD"

    else

        echo "  WARNING: no conf/passwd"

    fi


    # ========================================================
    # Apache per-repository configuration
    # ========================================================

    cat >> "$GENERATED_CONFIG" <<EOF

# ============================================================
# $REPO_NAME
# ============================================================

<Location /svn/$REPO_NAME>

    # Intentionally no DAV/SVNPath here.
    #
    # This block only adds authentication. The repository itself is
    # served by the <Location /svn> SVNParentPath block in apache.conf.
    #
    # Declaring "SVNPath" here as well would make mod_dav_svn fail with
    # "The URI does not contain the name of a repository" (HTTP 500).

    AuthType Basic
    AuthName "$REPO_NAME"

    AuthBasicProvider file

    AuthUserFile $AUTH_FILE

    Require valid-user

</Location>

EOF


    # ========================================================
    # WebSVN repository configuration
    # ========================================================
    #
    # parentPath() already discovers repositories.
    #
    # If authz exists, configure it for WebSVN.
    #
    # This controls authorization inside WebSVN, but does NOT
    # enable authentication. WebSVN remains public for now.
    #

    if [ -f "$AUTHZ" ]; then

        # Escape single quotes in filesystem paths.
        AUTHZ_ESCAPED="$(printf '%s' "$AUTHZ" | sed "s/'/\\\\'/g")"

# TODO: check why this thing doesn't work properly, we cannot see any svn repos with this enabled.
#        cat >> "$WEBSVN_CONFIG" <<PHP
#
#\$config->setAccessFile(
#    '$AUTHZ_ESCAPED',
#    '$REPO_NAME'
#);
#
#PHP

    fi

done


# ============================================================
# Permissions
# ============================================================

# Apache runs as the unprivileged "apache" user and must be able to
# read these files, so hand them over before tightening the mode.
chown -R apache:apache "$AUTH_ROOT" 2>/dev/null || true

chmod 640 "$AUTH_ROOT"/* 2>/dev/null || true

chown -R apache:apache /var/www/websvn


# ============================================================
# Summary
# ============================================================

echo
echo "=============================================="
echo "Repositories discovered: $REPOSITORIES"
echo "=============================================="
echo

echo "Apache modules:"
httpd -M 2>&1 | grep -E 'dav|ssl|rewrite' || true

echo
echo "Testing Apache configuration..."

httpd -t

echo " ... Apache config ok ... "

echo
echo "Starting Daemons..."

exec /usr/local/bin/daemon-start.sh
